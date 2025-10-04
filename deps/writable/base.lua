local buffer = import("buffer")
local class = import("class")

---@class luvit.writable.Base : luvit.class
---@field protected error string|nil
---@field protected write_buffer luvit.buffer
---@field public high_water_mark integer
---@field protected corked boolean
local Writable = class("writable.Base")
Writable.chunk_size = 16384

---@protected
function Writable:init()
	self.write_buffer = buffer.new()
	self.high_water_mark = Writable.chunk_size
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
function Writable:drain(extra, timeout)
	return #self.write_buffer + #extra
end

--- Flush the write buffer to the underlying stream. This will repeatedly call `:drain` until all buffered data is
--- consumed.
---
---@param extra? string # additional data to write after the buffered data
---@return boolean success # true if all buffered data was flushed, false if an error occurred
---@return string|nil error # if an error occurred during writing
---@nodiscard
function Writable:flush(extra, timeout)
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

		-- didn't consume enough data, try again unless we timed out
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
function Writable:write(data, timeout)
	if self.error then
		return false, self.error
	end

	-- buffer if corked or under high water mark
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
function Writable:writeUInt8(data, timeout)
	return self:write(string.char(data), timeout)
end

--- Write a single 8 bit signed integer to the stream.
---
---@param data integer # the byte to write (0-255)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function Writable:writeInt8(data, timeout)
	return self:write(string.char(complement(data)), timeout)
end

--- Write a single 16 bit unsigned integer to the stream in little-endian byte order.
---
---@param data integer # the integer to write (0-65535)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function Writable:writeUInt16LE(data, timeout)
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
function Writable:writeUInt16BE(data, timeout)
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
function Writable:writeInt16LE(data, timeout)
	return self:writeUInt16LE(complement(data, 65536), timeout)
end

--- Write a single 16 bit signed integer to the stream in big-endian byte order.
---
---@param data integer # the integer to write (-32768 to 32767)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function Writable:writeInt16BE(data, timeout)
	return self:writeUInt16BE(complement(data, 65536), timeout)
end

--- Write a single 32 bit unsigned integer to the stream in little-endian byte order.
---
---@param data integer # the integer to write (0-4294967295)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function Writable:writeUInt32LE(data, timeout)
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
function Writable:writeUInt32BE(data, timeout)
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
function Writable:writeInt32LE(data, timeout)
	return self:writeUInt32LE(complement(data, 4294967296), timeout)
end

--- Write a single 32 bit signed integer to the stream in big-endian byte order.
---
---@param data integer # the integer to write (-2147483648 to 2147483647)
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or sent, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function Writable:writeInt32BE(data, timeout)
	return self:writeUInt32BE(complement(data, 4294967296), timeout)
end

--- Cork the stream. This will prevent writes from being flushed until uncorked.
function Writable:cork()
	self.corked = true
end

--- Uncork the stream. This will flush the write buffer if it exceeds the high water mark.
---
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if the data was buffered or flushed successfully, false if an error occurred
---@return string|nil error # if an error occurred during flushing
---@nodiscard
function Writable:uncork(timeout)
	self.corked = false

	-- flush if data was corked over the high water mark
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
function Writable:finish(timeout)
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		return self:flush(nil, timeout)
	end

	return true
end

return Writable