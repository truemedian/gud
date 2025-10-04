local luv = require("luv")

local class = import("class")
local Writable = import("base.lua")
local timer = import("timer")
local utility = import("utility")

local assertresume = utility.assertresume

---@class luvit.writable.File : luvit.writable.Base
---@field private fd integer # file descriptor
---@field private position integer # current position in the file
---@field private write_timeout luvit.Timer # a libuv timer for write timeouts
---
--- A writable stream that writes to a file descriptor.
local FileWritable = class("writable.File", Writable)

---@protected
---@param fd integer
function FileWritable:init(fd)
	Writable.init(self)
	self.fd = fd
	self.position = 0
	self.write_timeout = timer.Timer()
end

--- Open a file and return a writable stream for it.
---
---@param path string # path to the file
---@param flags? string # file open flags (default "r")
---@param mode? integer # file mode (default 0o666)
---@return luvit.writable.File|nil stream # the writable file stream
---@return string|nil error # if an error occurred during opening
---@nodiscard
function FileWritable.open(path, flags, mode)
	local fd, err = luv.fs_open(path, flags or "r", mode or 438)
	if not fd then
		return nil, err
	end

	return FileWritable(fd)
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function FileWritable:drain(extra, timeout)
	local thread, main = coroutine.running()
	if main then
		-- short path for synchronous writes from the main thread, allowed but not recommended
		local amt_written, err = luv.fs_write(self.fd, { self.write_buffer:peek():tostring(), extra })
		if err then
			self.error = err
			return 0
		end
		return amt_written
	end

	-- yielded indicates whether the callback can resume a yielded coroutine
	local yielded, amt_written = false, nil
	local req, err = luv.fs_write(self.fd, { self.write_buffer:peek():tostring(), extra }, function(err, count)
		amt_written = count or 0

		if err then
			self.error = err
		end

		if yielded then
			if timeout then
				self.write_timeout:stop()
			end

			assertresume(thread, amt_written)
		end
	end)

	-- if req is nil, an error occurred immediately
	-- if amt_written is already set, the callback was called immediately
	if not req then
		self.error = err
		return 0
	elseif amt_written then
		return amt_written
	end

	if timeout then
		self.write_timeout:delayed(timeout, function()
			luv.cancel(req)
			yielded = false
			return assertresume(thread, 0, true)
		end)
	end

	yielded = true
	return coroutine.yield()
end
