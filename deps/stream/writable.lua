local luv = require("luv")
local buffer = import("buffer")
local class = import("class")
local utility = import("utility")

local assertresume = utility.assertresume

-- #region writable

---@class luvit.stream.writable : luvit.class
---@field protected error string|nil
---@field protected write_buffer luvit.buffer
---@field protected high_water_mark integer
---@field protected corked boolean
local writable = class("writable")

---@protected
function writable:init()
	self.write_buffer = buffer.new()
	self.high_water_mark = 4 * 1024
	self.corked = false
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function writable:drain(extra, timeout)
	return #self.write_buffer + #extra
end

--- Flush the write buffer to the underlying stream. This will repeatedly call `:drain` until all buffered data is
--- consumed.
---
---@param extra? string # additional data to write after the buffered data
---@return boolean success # true if all buffered data was flushed, false if an error occurred
---@return string|nil error # if an error occurred during writing
---@nodiscard
function writable:flush(extra, timeout)
	if self.error then
		return false, self.error
	end

	extra = extra or ""
	while true do
		local drained, timed_out = self:drain(extra, timeout)
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

		if timed_out then
			return false, "timeout"
		end
	end
end

--- Write data to the stream.
---
---@param data string # data to write
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:write(data, timeout)
	if self.error then
		return false, self.error
	end

	if self.corked or #self.write_buffer + #data <= self.high_water_mark then
		self.write_buffer:write(data)
		return true
	end

	return self:flush(data, timeout)
end

local function complement(value, radix)
	return value < 0 and value + radix or value
end

--- Write a single 8 bit unsigned integer to the stream.
---
---@param data integer # the byte to write (0-255)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeUInt8(data, timeout)
	return self:write(string.char(data), timeout)
end

--- Write a single 8 bit signed integer to the stream.
---
---@param data integer # the byte to write (0-255)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeInt8(data, timeout)
	return self:write(string.char(complement(data)), timeout)
end

--- Write a single 16 bit unsigned integer to the stream in little-endian byte order.
---
---@param data integer # the integer to write (0-65535)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeUInt16LE(data, timeout)
	local hi, lo = math.floor(data / 256), data % 256
	return self:write(string.char(lo, hi), timeout)
end

--- Write a single 16 bit unsigned integer to the stream in big-endian byte order.
---
---@param data integer # the integer to write (0-65535)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeUInt16BE(data, timeout)
	local hi, lo = math.floor(data / 256), data % 256
	return self:write(string.char(hi, lo), timeout)
end

--- Write a single 16 bit signed integer to the stream in little-endian byte order.
---
---@param data integer # the integer to write (-32768 to 32767)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeInt16LE(data, timeout)
	return self:writeUInt16LE(complement(data, 65536), timeout)
end

--- Write a single 16 bit signed integer to the stream in big-endian byte order.
---
---@param data integer # the integer to write (-32768 to 32767)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeInt16BE(data, timeout)
	return self:writeUInt16BE(complement(data, 65536), timeout)
end

--- Write a single 32 bit unsigned integer to the stream in little-endian byte order.
---
---@param data integer # the integer to write (0-4294967295)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeUInt32LE(data, timeout)
	local hi1, hi0, lo1, lo0 =
		math.floor(data / 16777216), math.floor(data / 65536) % 256, math.floor(data / 256) % 256, data % 256
	return self:write(string.char(lo0, lo1, hi0, hi1), timeout)
end

--- Write a single 32 bit unsigned integer to the stream in big-endian byte order.
---
---@param data integer # the integer to write (0-4294967295)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeUInt32BE(data, timeout)
	local hi1, hi0, lo1, lo0 =
		math.floor(data / 16777216), math.floor(data / 65536) % 256, math.floor(data / 256) % 256, data % 256
	return self:write(string.char(hi1, hi0, lo1, lo0), timeout)
end

--- Write a single 32 bit signed integer to the stream in little-endian byte order.
---
---@param data integer # the integer to write (-2147483648 to 2147483647)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeInt32LE(data, timeout)
	return self:writeUInt32LE(complement(data, 4294967296), timeout)
end

--- Write a single 32 bit signed integer to the stream in big-endian byte order.
---
---@param data integer # the integer to write (-2147483648 to 2147483647)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:writeInt32BE(data, timeout)
	return self:writeUInt32BE(complement(data, 4294967296), timeout)
end

--- Cork the stream. This will prevent writes from being flushed until uncorked.
function writable:cork()
	self.corked = true
end

--- Uncork the stream. This will flush the write buffer if it exceeds the high water mark.
---
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or flushed successfully, false if an error occurred
---@return string|nil error # if an error occurred during flushing
---@nodiscard
function writable:uncork(timeout)
	self.corked = false

	if #self.write_buffer > self.high_water_mark then
		return self:flush(nil, timeout)
	end

	return true
end

--- Finish writing. This will flush any remaining data in the write buffer.
---
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if all data was flushed, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable:finish(timeout)
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		return self:flush(nil, timeout)
	end

	return true
end

-- #endregion
-- #region writable.string

---@class luvit.stream.writable.string: luvit.stream.writable
---@field out_buffer luvit.buffer
---
--- A writable stream that writes to a string buffer.
writable.string = class("writable.string", writable)

---@protected
function writable.string:init()
	self.__base.init(self)
	self.out_buffer = buffer.new()
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function writable.string:drain(extra, timeout)
	self.out_buffer:write(self.write_buffer:read())
	self.out_buffer:write(extra)
	return #self.write_buffer + #extra
end

--- Get the contents of the string buffer and clear it.
---
---@return string # the contents of the string buffer
---@nodiscard
function writable.string:out()
	return self.out_buffer:read():tostring()
end

-- #endregion
-- #region writable.file

---@class luvit.stream.writable.file : luvit.stream.writable
---@field private fd integer # file descriptor
---@field private position integer # current position in the file
---@field private write_timeout userdata # a libuv timer for write timeouts
---
--- A writable stream that writes to a file descriptor.
writable.file = class("writable.file", writable)

---@protected
---@param fd integer
function writable.file:init(fd)
	self.__base.init(self)
	self.fd = fd
	self.position = 0
	---@diagnostic disable-next-line: assign-type-mismatch
	self.write_timeout = assert(luv.new_timer())
end

--- Open a file and return a writable stream for it.
---
---@param path string # path to the file
---@param flags? string # file open flags (default "r")
---@param mode? integer # file mode (default 438 = 0o666)
---@return luvit.stream.writable.file|nil stream # the writable file stream
---@return string|nil error # if an error occurred during opening
---@nodiscard
function writable.file.open(path, flags, mode)
	local fd, err = luv.fs_open(path, flags or "r", mode or 438)
	if not fd then
		return nil, err
	end

	return writable.file(fd)
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function writable.file:drain(extra, timeout)
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
	local req, err = luv.fs_write(self.fd, { self.write_buffer:peek():tostring(), extra }, function(err, count)
		nwritten = count or 0

		if err then
			self.error = err
		end

		if yielded then
			if timeout then
				assert(luv.timer_stop(self.write_timeout))
			end

			assertresume(thread, nwritten)
		end
	end)

	if not req then
		self.error = err
		return 0
	elseif nwritten then
		return nwritten
	end

	if timeout then
		assert(luv.timer_start(self.write_timeout, timeout, 0, function()
			luv.cancel(req)
			yielded = false
			return assertresume(thread, 0, true)
		end))
	end

	yielded = true
	return coroutine.yield()
end

-- #endregion
-- #region writable.stream

---@class luvit.stream.writable.stream : luvit.stream.writable
---@field private stream userdata # a libuv stream (e.g. a tcp or pipe handle)
---@field private write_timeout userdata # a libuv timer for write timeouts
---
--- A writable stream that writes to a libuv stream.
writable.stream = class("writable.stream", writable)

---@protected
function writable.stream:init(stream)
	self.__base.init(self)
	self.stream = stream
	---@diagnostic disable-next-line: assign-type-mismatch
	self.write_timeout = assert(luv.new_timer())
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function writable.stream:drain(extra, timeout)
	local thread, main = coroutine.running()
	if main then
		local ok, err = luv.write(self.stream, { self.write_buffer:read():tostring(), extra })
		if not ok then
			self.error = err
			return 0
		end
		return #self.write_buffer + #extra
	end

	local ok, err = luv.write(self.stream, { self.write_buffer:read():tostring(), extra }, function(err)
		if timeout then
			assert(luv.timer_stop(self.write_timeout))
		end

		if err then
			self.error = err
			return assertresume(thread, 0)
		end

		assertresume(thread, #self.write_buffer + #extra)
	end)

	if not ok then
		self.error = err
		return 0
	end

	if timeout then
		assert(luv.timer_start(self.write_timeout, timeout, 0, function()
			return assertresume(thread, 0, true)
		end))
	end

	return coroutine.yield()
end

--- Finish writing. This will flush any remaining data in the write buffer.
---
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if all data was flushed, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable.stream:finish(timeout)
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		local ok, err = self:flush(nil, timeout)
		if err == "timeout" then
			return false, "timeout"
		elseif not ok then
			return false, err
		end
	end

	local thread = coroutine.running()
	local req, err = luv.shutdown(self.stream, function(err)
		if err then
			self.error = err
		end

		if timeout then
			assert(luv.timer_stop(self.write_timeout))
		end

		return assertresume(thread, not err, err)
	end)

	if not req then
		self.error = err
		return false, err
	end

	if timeout then
		assert(luv.timer_start(self.write_timeout, timeout, 0, function()
			luv.cancel(req)
			return assertresume(thread, false, "timeout")
		end))
	end

	return coroutine.yield()
end

-- #endregion
-- #region writable.filter

---@class luvit.stream.writable.filter : luvit.stream.writable
---@field private dest luvit.stream.writable # the destination writable stream
---@field private filter fun(data: string|nil): data: string|nil, err: string|nil # the filter function to apply to the data
---
--- A writable stream that writes to another writable stream and applies a filter function to the data.
writable.filter = class("writable.filter", writable)

---@protected
---@param dest luvit.stream.writable the destination writable stream
---@param filter fun(data: string|nil): data: string|nil, err: string|nil the filter function to apply to the data
function writable.filter:init(dest, filter)
	self.__base.init(self)
	self.dest = dest
	self.filter = filter
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function writable.filter:drain(extra, timeout)
	local buffered = self.write_buffer:read():tostring()

	local filtered, filt_err = self.filter(buffered)
	if not filtered then
		self.error = filt_err or "filter error"
		return 0
	end

	local ok, err = self.dest:write(filtered, timeout)
	if err == "timeout" then
		return 0, true
	elseif not ok then
		self.error = self.dest.error
		return 0
	end

	return #self.write_buffer
end

--- Finish writing. This will flush any remaining data in the write buffer.
---
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if all data was flushed, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function writable.filter:finish(timeout)
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		local ok, err = self:flush(nil, timeout)
		if err == "timeout" then
			return false, "timeout"
		elseif not ok then
			self.error = err
			return false, err
		end
	end

	local filtered, filt_err = self.filter(nil)
	if not filtered then
		self.error = filt_err
		return not self.error, self.error
	end

	local ok, err = self.dest:write(filtered)
	if err == "timeout" then
		return false, "timeout"
	elseif not ok then
		self.error = err
		return false, err
	end

	return self.dest:finish(timeout)
end

-- #endregion

return writable
