local buffer = import("buffer")
local class = import("class")

---@class luvit.readable.Base : luvit.class
---@field protected error string|nil
---@field protected read_eof boolean
---@field protected read_buffer luvit.buffer
local Readable = class("readable.Base")
Readable.chunk_size = 16384

---@protected
---@param size? integer # initial size of the internal buffer
function Readable:init(size)
	self.error = nil
	self.read_eof = false
	self.read_buffer = buffer.new(size)
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer # a hint of how many bytes the caller would like to have available
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function Readable:fill(count, timeout)
	return 0
end

--- Peek at the contents of the internal buffer without consuming any data.
---
---@return luvit.slice # the contents of the internal buffer
---@nodiscard
function Readable:peek()
	return self.read_buffer:peek()
end

--- Fills the internal buffer with at least `count` more bytes, unless the stream ends or an error occurs.
---
---@param count integer # the minimum number of new bytes to fill
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@nodiscard
function Readable:fillAtLeast(count, timeout)
	if self.read_eof or self.error then
		return 0
	end

	local written = 0
	repeat
		local new, timed_out = self:fill(count - written, timeout)
		written = written + new
	until written >= count or self.read_eof or self.error or timed_out

	return written
end

--- Read exactly `bytes` bytes from the stream. Will return `nil` if the stream ends before `bytes` bytes can be read.
---
---@param bytes integer # the exact number of bytes to read
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return string|nil data # either `nil` (if not enough data is available), or a string with exactly `bytes` bytes
---@return string|nil error # if an error occurred, or "timeout" if the timeout was reached
---@nodiscard
function Readable:readExact(bytes, timeout)
	local available = #self.read_buffer

	if available < bytes then
		local needed = bytes - available
		local new = self:fillAtLeast(needed, timeout)

		if new < needed then
			if self.error or self.read_eof then
				return nil, self.error
			else
				-- no error or eof but not enough data was read, must be timeout
				return nil, "timeout"
			end
		end
	end

	return self.read_buffer:read(bytes):tostring()
end

--- Read at least `bytes` bytes from the stream. Will return `nil` if the stream ends before `bytes` bytes can be read.
---
---@param bytes integer # the minimum number of bytes to read
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return string|nil data # either `nil` (if not enough data is available), or a string with at least `bytes` bytes
---@return string|nil error # if an error occurred, or "timeout" if the timeout was reached
---@nodiscard
function Readable:readAtLeast(bytes, timeout)
	local available = #self.read_buffer
	if available < bytes then
		local needed = bytes - available
		local new = self:fillAtLeast(needed, timeout)

		if new < needed then
			if self.error or self.read_eof then
				return nil, self.error
			else
				-- no error or eof but not enough data was read, must be timeout
				return nil, "timeout"
			end
		end
	end

	return self.read_buffer:read():tostring()
end

--- Read at most `bytes` bytes from the stream. Will return `nil` if the stream has ended and no more data is available.
---
---@param bytes integer # the maximum number of bytes to read
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return string|nil data # either `nil` (if no data is available), or a string with at most `bytes` bytes
---@return string|nil error # if an error occurred, or "timeout" if the timeout was reached
---@nodiscard
function Readable:readAtMost(bytes, timeout)
	local available = #self.read_buffer

	if available == 0 then
		local new = self:fillAtLeast(1, timeout)
		available = #self.read_buffer

		if new < 1 then
			if self.error or self.read_eof then
				return nil, self.error
			else
				-- no error or eof but not enough data was read, must be timeout
				return nil, "timeout"
			end
		end
	end

	local count = math.min(bytes, available)
	return self.read_buffer:read(count):tostring()
end

--- Continuously read from this stream and write to the given writable stream until this stream ends or an error occurs.
---
---@param writable luvit.writable.Base # a writable stream to pump data into
---@param finish boolean # if `true`, the writable stream will be finished after the pump is done
---@param timeout integer|nil # a timeout for individual read and write operations in milliseconds
---@param chunk_size? integer # maximum number of bytes to read from this stream at a time
---@return boolean success # `true` if the pump completed successfully
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:pump(writable, finish, timeout, chunk_size)
	chunk_size = chunk_size or Readable.chunk_size

	while true do
		local chunk, read_err = self:readAtMost(chunk_size, timeout)
		if read_err then
			return false, read_err
		elseif not chunk then
			break
		end

		local ok, write_err = writable:write(chunk, timeout)
		if not ok then
			return false, write_err
		end
	end

	if finish then
		local ok, finish_err = writable:finish(timeout)
		if not ok then
			return false, finish_err
		end
	end

	return true
end

--- Read from the stream until "\r\n" or "\n".
---
---@param max_size? number # maximum number of bytes to read, defaults to infinity
---@param include_delimiter? boolean # whether or not the line ending should be included in the returned data
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return luvit.slice|nil data # the line that was read, or `nil` if the stream ended before a line ending was found
---@return string|nil error # if an error occurred, or "line too long" if the line exceeded `max_size`
---@nodiscard
function Readable:readLine(max_size, include_delimiter, timeout)
	max_size = max_size or math.huge

	local pos = 1
	while true do
		local idx = self.read_buffer:peek():find("\n", pos)

		if idx then
			if idx > max_size then
				return nil, "line too long"
			end

			if include_delimiter then
				return self.read_buffer:read(idx)
			else
				local data = self.read_buffer:peek(idx - 1)
				if data:byte(-1) == 13 then
					data = data:sub(1, -2)
				end

				self.read_buffer:skip(idx)
				return data
			end
		elseif #self.read_buffer >= max_size then
			return nil, "line too long"
		end

		pos = #self.read_buffer + 1
		local new = self:fillAtLeast(1, timeout)

		if self.read_eof or self.error then
			return nil, self.error
		elseif new < 1 then
			-- no error but nothing was read, must be timeout
			return nil, "timeout"
		end
	end
end

--- Read from the stream until the given delimiter is found.
---
---@param delimiter string # the delimiter to read until
---@param max_size? number # maximum number of bytes to read, defaults to infinity
---@param include_delimiter? boolean # whether or not the delimiter should be included in the returned data
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return luvit.slice|nil data # the data that was read, or `nil` if the stream ended before the delimiter was found
---@return string|nil error # if an error occurred, or "delimiter not found" if the delimiter was not found before `max_size` bytes were read
---@nodiscard
function Readable:readUntil(delimiter, max_size, include_delimiter, timeout)
	max_size = max_size or math.huge

	local pos = 1
	while true do
		local idx = self.read_buffer:peek():find(delimiter, pos)

		if idx then
			if idx > max_size then
				return nil, "delimiter not found"
			end

			if include_delimiter then
				return self.read_buffer:read(idx + #delimiter - 1)
			else
				self.read_buffer:skip(#delimiter)
				return self.read_buffer:read(idx - 1)
			end
		elseif #self.read_buffer >= max_size then
			return nil, "delimiter not found"
		end

		pos = #self.read_buffer - #delimiter + 2
		local new = self:fillAtLeast(1, timeout)

		if self.read_eof or self.error then
			return nil, self.error
		elseif new < 1 then
			-- no error but nothing was read, must be timeout
			return nil, "timeout"
		end
	end
end

local function complement(value, radix)
	return value >= radix / 2 and value - radix or value
end

--- Read a single 8 bit unsigned integer from the stream.
---
---@param timeout integer|nil # a timeout for an individual read operation in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred, or "timeout" if the timeout was reached
---@nodiscard
function Readable:readUInt8(timeout)
	local data, err = self:readExact(1, timeout)
	if not data then
		return nil, err
	end

	return (string.byte(data, 1))
end

--- Read a single 8 bit signed integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:readInt8(timeout)
	local data, err = self:readUInt8(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x100)
end

--- Read a single 16 bit unsigned little-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:readUInt16LE(timeout)
	local data, err = self:readExact(2, timeout)
	if not data then
		return nil, err
	end

	local a, b = string.byte(data, 1, 2)
	return b * 0x100 + a
end

--- Read a single 16 bit unsigned big-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:readUInt16BE(timeout)
	local data, err = self:readExact(2, timeout)
	if not data then
		return nil, err
	end

	local a, b = string.byte(data, 1, 2)
	return a * 0x100 + b
end

--- Read a single 16 bit signed little-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:readInt16LE(timeout)
	local data, err = self:readUInt16LE(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x10000)
end

--- Read a single 16 bit signed big-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:readInt16BE(timeout)
	local data, err = self:readUInt16BE(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x10000)
end

--- Read a single 32 bit unsigned little-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:readUInt32LE(timeout)
	local data, err = self:readExact(4, timeout)
	if not data then
		return nil, err
	end

	local a, b, c, d = string.byte(data, 1, 4)
	return d * 0x1000000 + c * 0x10000 + b * 0x100 + a
end

--- Read a single 32 bit unsigned big-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:readUInt32BE(timeout)
	local data, err = self:readExact(4, timeout)
	if not data then
		return nil, err
	end

	local a, b, c, d = string.byte(data, 1, 4)
	return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

--- Read a single 32 bit signed little-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:readInt32LE(timeout)
	local data, err = self:readUInt32LE(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x100000000)
end

--- Read a single 32 bit signed big-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function Readable:readInt32BE(timeout)
	local data, err = self:readUInt32BE(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x100000000)
end

return Readable
