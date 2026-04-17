local buffer = require('buffer')
local class = require('class')

local char = string.char
local floor = math.floor

--- @class std.writer
--- @field closed boolean Indicates whether or not the writer has been closed.
--- @field buffer std.buffer
--- @field high_watermark integer
--- @field corked boolean
local writer = class('std.writer')

--- Creates an empty writer.
--- @return std.writer
function writer.empty()
	local result = writer()
	result.closed = true
	return result
end

function writer:init()
	self.closed = false
	self.buffer = buffer()
	self.high_watermark = 0x4000
	self.corked = false
end

--- Corks the writer, preventing it from flushing data until `uncork` is called. This is useful for batching multiple]
--- writes together to improve performance. If the writer is already corked, this is a no-op.
function writer:cork()
	self.corked = true
end

--- Uncorks the writer, allowing it to flush data again. If the writer is already uncorked, this is a no-op.
--- @param timeout integer
--- @return boolean success
--- @return string|nil err
function writer:uncork(timeout)
	if not self.corked then
		return true
	end

	self.corked = false
	if #self.buffer > self.high_watermark then
		return self:flushAll(timeout)
	end

	return true
end

--- Flushes as much data as possible to the underlying sink. Should return as soon as at least one byte can be flushed,
--- but may flush more data if possible before returning. If the writer returns `0` bytes flushed, it means that the end
--- of the stream has been reached and no more data can be written.
---
--- The `timeout` parameter specifies the maximum amount of time (in milliseconds) that the writer should wait for
--- the sink to become writable. If the timeout is reached before any data can be written, the writer should return an
--- error message of `'timeout'`. The default for timeout is to wait indefinitely.
---
--- Will write data regardless of the `corked` state.
--- @param timeout? integer
--- @return integer nwritten
--- @return string|nil err
function writer:flush(timeout) -- luacheck: no unused args
	return 0, 'not implemented'
end

--- Flush the write buffer to the underlying stream. This will repeatedly call `drain` until all buffered data is
--- consumed.
---
--- The `timeout` parameter specifies the maximum amount of time (in milliseconds) that the writer should wait for
--- an individual flush operation to complete.
---
--- Will write data regardless of the `corked` state.
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:flushAll(timeout)
	local total = #self.buffer
	if total == 0 then
		return true
	end

	if self.closed then
		return false, 'closed'
	end

	while true do
		local nwritten, err = self:flush(timeout)
		if nwritten == total then
			self.buffer:clear()
			return true, err
		elseif err then
			self.closed = self.closed or err ~= 'timeout'
			return false, err
		elseif nwritten == 0 then
			self.closed = true
			self.buffer:clear()
			return false, 'closed'
		end

		if nwritten > 0 then
			self.buffer:skip(nwritten)
			total = total - nwritten
		end
	end
end

--- Flushes all buffered data, and then calls `flushAll` recursively down any underlying writers. This is useful for ensuring that all data is flushed through a chain of writers.
--- @param timeout? integer
--- @return boolean
function writer:flushAllRecursive(timeout)
	return self:flushAll(timeout)
end

--- Flushes any remaining data and prevents any further writes to the stream.
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:finish(timeout)
	if self.closed then
		return false, 'closed'
	end

	local ok, err = self:flushAll(timeout)
	self.closed = true
	return ok, err
end

--- Enqueues data for writing.
--- @param data string
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:write(data, timeout)
	if self.closed then
		return false, 'closed'
	end

	self.buffer:write(data)
	if self.corked or #self.buffer < self.high_watermark then
		return true
	end

	return self:flushAll(timeout)
end

local function ensure_integer(n, name)
	if type(n) ~= 'number' or n ~= floor(n) then
		return error(name .. ' must be an integer')
	end
end

local function ensure_unsigned(n, max, name)
	ensure_integer(n, name)
	if n < 0 or n > max then
		return error(name .. ' out of range')
	end
end

local function ensure_signed(n, min, max, name)
	ensure_integer(n, name)
	if n < min or n > max then
		return error(name .. ' out of range')
	end
end

--- Writes an unsigned 8-bit integer.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeUint8(n, timeout)
	ensure_unsigned(n, 0xFF, 'uint8')
	return self:write(char(n), timeout)
end

--- Writes an unsigned 16-bit integer in little-endian byte order.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeUint16LE(n, timeout)
	ensure_unsigned(n, 0xFFFF, 'uint16')
	local a, b = n % 0x100, floor(n / 0x100) % 0x100

	return self:write(char(a, b), timeout)
end

--- Writes an unsigned 16-bit integer in big-endian byte order.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeUint16BE(n, timeout)
	ensure_unsigned(n, 0xFFFF, 'uint16')
	local b, a = n % 0x100, floor(n / 0x100) % 0x100

	return self:write(char(a, b), timeout)
end

--- Writes an unsigned 32-bit integer in little-endian byte order.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeUint32LE(n, timeout)
	ensure_unsigned(n, 0xFFFFFFFF, 'uint32')
	local a, b, c, d = n % 0x100, floor(n / 0x100) % 0x100, floor(n / 0x10000) % 0x100, floor(n / 0x1000000) % 0x100

	return self:write(char(a, b, c, d), timeout)
end

--- Writes an unsigned 32-bit integer in big-endian byte order.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeUint32BE(n, timeout)
	ensure_unsigned(n, 0xFFFFFFFF, 'uint32')
	local d, c, b, a = n % 0x100, floor(n / 0x100) % 0x100, floor(n / 0x10000) % 0x100, floor(n / 0x1000000) % 0x100

	return self:write(char(a, b, c, d), timeout)
end

--- Writes a signed 8-bit integer.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeInt8(n, timeout)
	ensure_signed(n, -0x80, 0x7F, 'int8')

	if n < 0 then
		n = n + 0x100
	end

	return self:writeUint8(n, timeout)
end

--- Writes a signed 16-bit integer in little-endian byte order.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeInt16LE(n, timeout)
	ensure_signed(n, -0x8000, 0x7FFF, 'int16')

	if n < 0 then
		n = n + 0x10000
	end

	return self:writeUint16LE(n, timeout)
end

--- Writes a signed 16-bit integer in big-endian byte order.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeInt16BE(n, timeout)
	ensure_signed(n, -0x8000, 0x7FFF, 'int16')

	if n < 0 then
		n = n + 0x10000
	end

	return self:writeUint16BE(n, timeout)
end

--- Writes a signed 32-bit integer in little-endian byte order.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeInt32LE(n, timeout)
	ensure_signed(n, -0x80000000, 0x7FFFFFFF, 'int32')

	if n < 0 then
		n = n + 0x100000000
	end

	return self:writeUint32LE(n, timeout)
end

--- Writes a signed 32-bit integer in big-endian byte order.
--- @param n integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function writer:writeInt32BE(n, timeout)
	ensure_signed(n, -0x80000000, 0x7FFFFFFF, 'int32')

	if n < 0 then
		n = n + 0x100000000
	end

	return self:writeUint32BE(n, timeout)
end

return writer
