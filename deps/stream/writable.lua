local luv = require("luv")
local buffer = import("buffer")

local function assertResume(thread, ...)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		error(debug.traceback(thread, err), 0)
	end
end

-- #region writable

---@class luvit.stream.writable
---@field protected error string|nil
---@field protected write_buffer luvit.buffer
---@field protected high_water_mark integer
---@field protected corked boolean
local writable = {}

--- Initialize the writable stream.
---
---@protected
function writable:init()
	self.write_buffer = buffer.new()
	self.high_water_mark = 4 * 1024
	self.corked = false
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string additional data to write after the buffered data
---@return integer number of bytes written from the write buffer and extra data
---@return string|nil error if an error occurred during writing
---@nodiscard
function writable:drain(extra)
	return #self.write_buffer + #extra
end

--- Flush the write buffer to the underlying stream. This will repeatedly call `:drain` until all buffered data is
--- consumed.
---
---@param extra? string
---@return boolean
---@return string|nil
---@nodiscard
function writable:flush(extra)
	if self.error then
		return false, self.error
	end

	extra = extra or ""
	while true do
		local drained = self:drain(extra)
		if self.error then
			return false, self.error
		end

		if drained == #self.write_buffer + #extra then
			-- all data consumed
			self.write_buffer:reset()
			return true
		elseif drained > #self.write_buffer then
			-- all buffer consumed, some of extra
			self.write_buffer:reset()
			extra = extra:sub(drained - #self.write_buffer + 1)
			return true
		elseif drained > 0 then
			-- some of buffer consumed, none of extra
			self.write_buffer:skip(drained)
		end
	end
end

--- Write data to the stream.
---@param data string
---@return boolean
---@return string|nil
---@nodiscard
function writable:write(data)
	if self.error then
		return false, self.error
	end

	if self.corked or #self.write_buffer + #data <= self.high_water_mark then
		self.write_buffer:write(data)
		return true
	end

	return self:flush(data)
end

--- Cork the stream. This will prevent writes from being flushed until uncorked.
function writable:cork()
	self.corked = true
end

--- Uncork the stream. This will flush the write buffer if it exceeds the high water mark.
---@return boolean
---@return string|nil
---@nodiscard
function writable:uncork()
	self.corked = false

	if #self.write_buffer > self.high_water_mark then
		return self:flush("")
	end

	return true
end

--- Finish writing. This will flush any remaining data in the write buffer.
---@return boolean
---@return string|nil
---@nodiscard
function writable:finish()
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		return self:flush()
	end

	return true
end

-- #endregion
-- #region writable.string

---@class luvit.stream.writable.string: luvit.stream.writable
---@field out_buffer luvit.buffer
---
--- A writable stream that writes to a string buffer.
writable.string = {}
writable.string.__index = writable.string

for k, v in pairs(writable) do
	writable.string[k] = v
end

--- Create a new writable string stream.
---
---@return luvit.stream.writable.string stream
---@nodiscard
function writable.string.new()
	local self = setmetatable({ out_buffer = buffer.new() }, writable.string)
	self:init()
	return self
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string additional data to write after the buffered data
---@return integer number of bytes written from the write buffer and extra data
---@return string|nil error if an error occurred during writing
---@nodiscard
function writable.string:drain(extra)
	self.out_buffer:write(self.write_buffer:read())
	self.out_buffer:write(extra)
	return #self.write_buffer + #extra
end

--- Get the contents of the string buffer and clear it.
---
---@return string
---@nodiscard
function writable.string:out()
	return self.out_buffer:read():tostring()
end

-- #endregion
-- #region writable.file

---@class luvit.stream.writable.file : luvit.stream.writable
---@field private fd integer
---@field private position integer
---
--- A writable stream that writes to a file descriptor.
writable.file = {}
writable.file.__index = writable.file

for k, v in pairs(writable) do
	writable.file[k] = v
end

--- Create a new writable stream for the given file descriptor.
---
---@param fd integer
---@return luvit.stream.writable.file stream
---@nodiscard
function writable.file.new(fd)
	local self = setmetatable({ fd = fd, position = 0 }, writable.file)
	self:init()
	return self
end

--- Open a file and return a writable stream for it.
---
---@param path string
---@param flags? string
---@param mode? integer
---@return luvit.stream.writable.file|nil stream
---@return string|nil error
---@nodiscard
function writable.file.open(path, flags, mode)
	local fd, err = luv.fs_open(path, flags or "r", mode or 438)
	if not fd then
		return nil, err
	end

	return (writable.file.new(fd))
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string additional data to write after the buffered data
---@return integer number of bytes written from the write buffer and extra data
---@return string|nil error if an error occurred during writing
---@nodiscard
function writable.file:drain(extra)
	local thread, main = coroutine.running()
	if main then
		local nwritten, err = luv.fs_write(self.fd, { self.write_buffer:peek():tostring(), extra })
		if err then
			self.error = err
			return 0
		end
		return nwritten
	end

	local yielded, nwritten = false, nil

	luv.fs_write(self.fd, { self.write_buffer:peek():tostring(), extra }, function(err, count)
		nwritten = count or 0

		if err then
			self.error = err
		end

		if yielded then
			assertResume(thread, nwritten)
		end
	end)

	if nwritten then
		return nwritten
	end

	yielded = true
	return coroutine.yield()
end

-- #endregion
-- #region writable.stream

---@class luvit.stream.writable.stream : luvit.stream.writable
---@field private stream userdata
---
--- A writable stream that writes to a libuv stream.
writable.stream = {}
writable.stream.__index = writable.stream

for k, v in pairs(writable) do
	writable.stream[k] = v
end

--- Create a new writable stream for the given libuv stream.
---
---@param stream userdata a libuv stream
---@return luvit.stream.writable.stream
---@nodiscard
function writable.stream.new(stream)
	local self = setmetatable({ stream = stream }, writable.stream)
	self:init()
	return self
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string additional data to write after the buffered data
---@return integer number of bytes written from the write buffer and extra data
---@return string|nil error if an error occurred during writing
---@nodiscard
function writable.stream:drain(extra)
	local thread, main = coroutine.running()
	if main then
		local ok, err = luv.write(self.stream, { self.write_buffer:read():tostring(), extra })
		if not ok then
			self.error = err
			return 0
		end
		return #self.write_buffer + #extra
	end

	luv.write(self.stream, { self.write_buffer:read():tostring(), extra }, function(err)
		if err then
			self.error = err
			return assertResume(thread, 0)
		end

		assertResume(thread, #self.write_buffer + #extra)
	end)

	return coroutine.yield()
end

--- Finish writing. This will flush any remaining data in the write buffer.
---@return boolean
---@return string|nil
---@nodiscard
function writable.stream:finish()
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		local ok, err = self:flush()
		if not ok then
			return false, err
		end
	end

	local thread = coroutine.running()

	luv.shutdown(self.stream, function(err)
		if err then
			self.error = err
		end

		return assertResume(thread, not err, err)
	end)

	return coroutine.yield()
end

-- #endregion
-- #region writable.filter

---@class luvit.stream.writable.filter : luvit.stream.writable
---@field private filter fun(data: string|nil): data: string|nil, err: string|nil
---@field private dest luvit.stream.writable
---
--- A writable stream that writes to another writable stream and applies a filter function to the data.
writable.filter = {}
writable.filter.__index = writable.filter

for k, v in pairs(writable) do
	writable.filter[k] = v
end

--- Create a new writable filter stream.
---
---@param dest luvit.stream.writable the destination writable stream
---@param filter fun(data: string|nil): data: string|nil, err: string|nil the filter function to apply to the data
---@return luvit.stream.writable.filter
---@nodiscard
function writable.filter.new(dest, filter)
	local self = setmetatable({ dest = dest, filter = filter }, writable.filter)
	self:init()
	return self
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string additional data to write after the buffered data
---@return integer number of bytes written from the write buffer and extra data
---@return string|nil error if an error occurred during writing
---@nodiscard
function writable.filter:drain(extra)
	local buffered = self.write_buffer:read():tostring()

	local filtered, filt_err = self.filter(buffered)
	if not filtered then
		self.error = filt_err or "filter error"
		return 0
	end

	local ok, err = self.dest:write(filtered)
	if not ok then
		self.error = err
		return 0
	end

	return #self.write_buffer
end

--- Finish writing. This will flush any remaining data in the write buffer.
---@return boolean
---@return string|nil
---@nodiscard
function writable.filter:finish()
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		local ok, err = self:flush()
		if not ok then
			return false, err
		end
	end

	local filtered, filt_err = self.filter(nil)
	if not filtered then
		self.error = filt_err
		return not self.error, self.error
	end

	local ok, err = self.dest:write(filtered)
	if not ok then
		self.error = err
		return false, err
	end

	return self.dest:finish()
end

-- #endregion

return writable
