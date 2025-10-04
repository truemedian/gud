local luv = require("luv")

local class = import("class")
local Readable = import("base.lua")
local timer = import("timer")
local utility = import("utility")

local assertresume = utility.assertresume

---@class luvit.readable.File : luvit.readable.Base
---@field private fd integer # file descriptor to read from
---@field private position integer # current position in the file
---@field private read_timeout luvit.Timer # a libuv timer for read timeouts
---
--- A readable stream that reads from a file descriptor.
local FileReadable = class("readable.File", Readable)

---@protected
---@param fd integer # file descriptor to read from
function FileReadable:init(fd)
	Readable.init(self)
	self.fd = fd
	self.position = 0
	self.read_timeout = timer.Timer()
end

--- Open a file and return a readable stream for it.
---
---@param path string # path to the file to open
---@param flags? string # defaults to "r"
---@param mode? integer # defaults to 0o666
---@return luvit.readable.File|nil stream # the readable stream, or `nil` if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function FileReadable.open(path, flags, mode)
	local fd, err = luv.fs_open(path, flags or "r", mode or 438)
	if not fd then
		return nil, err
	end

	return FileReadable(fd)
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer # a hint of how many bytes the caller would like to have available
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function FileReadable:fill(count, timeout)
	local thread, main = coroutine.running()
	if main then
		-- short path for synchronous reads on the main thread, allowed but not recommended
		local chunk, err = luv.fs_read(self.fd, count, self.position)

		if chunk and #chunk > 0 then
			self.position = self.position + #chunk
			self.read_buffer:write(chunk)
			return #chunk
		elseif err then
			self.error = err
			return 0
		else
			self.ended = true
		end
	end

	-- yielded indicates whether the callback can resume a yielded coroutine
	local yielded, amt_read = false, nil

	-- ensure we read at least Readable.chunk_size bytes to avoid too many small reads
	count = math.max(count, Readable.chunk_size)
	local req, err = luv.fs_read(self.fd, count, self.position, function(err, chunk)
		if chunk and #chunk > 0 then
			amt_read = #chunk
			self.position = self.position + #chunk
			self.read_buffer:write(chunk)
		elseif err then -- error occurred
			amt_read = 0
			self.error = err
		else -- an empty chunk indicates end of file
			amt_read = 0
			self.ended = true
		end

		if yielded then
			if timeout then
				self.read_timeout:stop()
			end

			return assertresume(thread, amt_read)
		end
	end)

	-- if req is nil, an error occurred immediately
	-- if amt_read is already set, the callback was called immediately
	if not req then
		self.error = err
		return 0
	elseif amt_read then
		return amt_read
	end

	if timeout then
		self.read_timeout:delayed(timeout, function()
			luv.cancel(req)
			yielded = false
			return assertresume(thread, 0, true)
		end)
	end

	yielded = true
	return coroutine.yield()
end

return FileReadable