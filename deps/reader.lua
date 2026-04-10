local buffer = require('buffer')
local class = require('class')

local byte, find = string.byte, string.find
local max = math.max

--- @class std.reader
--- @field closed boolean Indicates whether or not the reader has been closed / reached the end of the stream.
--- @field buffer std.buffer Buffer for storing data read from the underlying source.
local reader = class('std.reader')

--- Creates a new reader that is pre-filled with the given string.
--- @param str string
--- @return std.reader
function reader.fixed(str)
	local r = reader()
	r.buffer:write(str)
	return r
end

--- Creates a new reader that is already at the end of the stream.
--- @return std.reader
function reader.empty()
	local r = reader()
	r.closed = true
	return r
end

function reader:init()
	self.closed = false
	self.buffer = buffer()
end

--- Requests `n` bytes from the underlying source. The number `n` is a hint and the reader may either return fewer bytes
--- or more bytes than requested.
---
--- The reader should return as soon as at least one byte is available, but it may wait for more bytes to arrive before
--- returning. If the reader returns `0` bytes, it means that the end of the stream has been reached.
---
--- The `timeout` parameter specifies the maximum amount of time (in milliseconds) that the reader should wait for data
--- to become available. If the timeout is reached before any data is available, the reader should return an error
--- message of `"timeout"`. The default for timeout is to wait indefinitely.
--- @param n integer
--- @param timeout? integer
--- @return integer nread
--- @return string|nil err
function reader:fill(n, timeout) -- luacheck: no unused args
	return 0
end

--- Requests at least `n` bytes from the underlying source. The reader will only return fewer than `n` bytes if the
--- end of the stream has been reached. If the reader returns `0` bytes, it means that the end of the stream has been
--- reached.
---
--- The `timeout` parameter specifies the maximum amount of time (in milliseconds) that the reader should wait for data
--- to become available. If the timeout is reached before any data is available, the reader should return an error
--- message of `"timeout"`. The default for timeout is to wait indefinitely.
--- @param n integer
--- @param timeout? integer
--- @return integer nread
--- @return string|nil err
function reader:fillAtLeast(n, timeout)
	if self.closed then
		return 0
	end

	local total = 0
	repeat
		local nread, err = self:fill(n - total, timeout)
		if err then
			return total, err
		elseif nread == 0 then
			self.closed = err ~= 'timeout'
			return total
		end

		total = total + nread
	until total >= n

	return total
end

--- Reads exactly `n` bytes from the underlying source.
---
--- Will return an error if the end of the stream is reached before `n` bytes can be read.
--- @param n integer
--- @param timeout? integer
--- @return string|nil data
--- @return string|nil err
function reader:readExact(n, timeout)
	local available = #self.buffer

	if available >= n then
		return self.buffer:read(n)
	end

	local needed = n - available
	local new, err = self:fillAtLeast(needed, timeout)
	if new < needed then
		return nil, 'closed'
	end

	return self.buffer:read(n), err
end

--- Reads at least `n` bytes from the underlying source.
---
--- Will return an error if the end of the stream is reached before `n` bytes can be read.
--- @param n integer
--- @param timeout? integer
--- @return string|nil data
--- @return string|nil err
function reader:readAtLeast(n, timeout)
	local available = #self.buffer
	if available >= n then
		return self.buffer:read(n)
	end

	local needed = n - available
	local new, err = self:fillAtLeast(needed, timeout)
	if new < needed then
		return nil, 'closed'
	end

	return self.buffer:read(), err
end

--- Reads at most `n` bytes from the underlying source.
---
--- Will return an error if the end of the stream is reached before at least one byte can be read.
--- @param n integer
--- @param timeout? integer
--- @return string|nil data
--- @return string|nil err
function reader:readAtMost(n, timeout)
	local available = #self.buffer
	if available > 0 then
		return self.buffer:read(n)
	end

	local new, err = self:fillAtLeast(1, timeout)
	if new < 1 then
		return nil, 'closed'
	end

	return self.buffer:read(n), err
end

--- Reads bytes from the underlying source until the pattern `delim` is encountered.
---
--- If `max_size` is provided, the reader will return an error if `ch` is not encountered within the first `max_size`
--- bytes.
---
--- If `delim` is a pattern that can match more than `#delim` characters, then `delim_lookbehind` must be provided to
--- indicate how many bytes are required for the pattern to be fully matched. The reader will look this many bytes back
--- from the end of the buffer when searching for `delim` after receiving new data.
--- @param delim string
--- @param max_size? integer
--- @param timeout? integer
--- @param delim_lookbehind? integer
function reader:readUntil(delim, max_size, timeout, delim_lookbehind)
	max_size = max_size or math.huge
	delim_lookbehind = delim_lookbehind or #delim

	assert(type(delim) == 'string' and #delim > 0, 'delimiter must be a non-empty string')
	assert(type(max_size) == 'number' and max_size > 0, 'max_size must be a positive number')

	local last_index = 1

	local new, err
	while true do
		local data = self.buffer:peek(max_size)
		local i, j = find(data, delim, last_index)

		if i and j then
			if j > max_size then
				return nil, 'max size exceeded'
			end

			self.buffer:skip(j)
			return data:sub(1, j)
		end

		if err then
			return nil, err
		elseif #data >= max_size then
			return nil, 'max size exceeded'
		end

		new, err = self:fillAtLeast(1, timeout)
		if new < 1 then
			return nil, 'closed'
		end

		last_index = max(#data - delim_lookbehind, 1)
	end
end

--- Reads all remaining bytes from the underlying source until the end of the stream is reached.
---
--- If `max_size` is provided, the reader will return an error if the end of the stream is not reached within the first
--- `max_size` bytes.
--- @param max_size? integer
--- @param timeout? integer
--- @return string|nil data
--- @return string|nil err
function reader:readAll(max_size, timeout)
	while true do
		local new, err = self:fillAtLeast(1, timeout)
		if new == 0 then
			return self.buffer:read()
		elseif err then
			return nil, err
		elseif max_size and #self.buffer > max_size then
			return nil, 'max size exceeded'
		end
	end
end

--- Reads a unsigned 8-bit integer from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readUint8(timeout)
	local data, err = self:readExact(1, timeout)
	if not data then
		return nil, err
	end

	local a = byte(data)
	return a
end

--- Reads a unsigned 16-bit integer in little-endian byte order from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readUint16LE(timeout)
	local data, err = self:readExact(2, timeout)
	if not data then
		return nil, err
	end

	local a, b = byte(data)
	return a + b * 0x100
end

--- Reads a unsigned 16-bit integer in big-endian byte order from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readUint16BE(timeout)
	local data, err = self:readExact(2, timeout)
	if not data then
		return nil, err
	end

	local b, a = byte(data)
	return a + b * 0x100
end

--- Reads a unsigned 32-bit integer in little-endian byte order from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readUint32LE(timeout)
	local data, err = self:readExact(4, timeout)
	if not data then
		return nil, err
	end

	local a, b, c, d = byte(data)
	return a + b * 0x100 + c * 0x10000 + d * 0x1000000
end

--- Reads a unsigned 32-bit integer in big-endian byte order from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readUint32BE(timeout)
	local data, err = self:readExact(4, timeout)
	if not data then
		return nil, err
	end

	local d, c, b, a = byte(data)
	return a + b * 0x100 + c * 0x10000 + d * 0x1000000
end

--- Reads a signed 8-bit integer from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readInt8(timeout)
	local n, err = self:readUint8(timeout)
	if not n then
		return nil, err
	end

	if n >= 0x80 then
		n = n - 0x100
	end

	return n
end

--- Reads a signed 16-bit integer in little-endian byte order from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readInt16LE(timeout)
	local n, err = self:readUint16LE(timeout)
	if not n then
		return nil, err
	end

	if n >= 0x8000 then
		n = n - 0x10000
	end

	return n
end

--- Reads a signed 16-bit integer in big-endian byte order from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readInt16BE(timeout)
	local n, err = self:readUint16BE(timeout)
	if not n then
		return nil, err
	end

	if n >= 0x8000 then
		n = n - 0x10000
	end

	return n
end

--- Reads a signed 32-bit integer in little-endian byte order from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readInt32LE(timeout)
	local n, err = self:readUint32LE(timeout)
	if not n then
		return nil, err
	end

	if n >= 0x80000000 then
		n = n - 0x100000000
	end

	return n
end

--- Reads a signed 32-bit integer in big-endian byte order from the underlying source.
---
--- @param timeout? integer
--- @return integer|nil
--- @return string|nil
function reader:readInt32BE(timeout)
	local n, err = self:readUint32BE(timeout)
	if not n then
		return nil, err
	end

	if n >= 0x80000000 then
		n = n - 0x100000000
	end

	return n
end

return reader
