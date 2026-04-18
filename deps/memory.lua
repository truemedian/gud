local byte = string.byte

local class = require('class')

--- @class std.memory : std.class<std.memory>
--- @field data string
local memory = class.new('std.memory')

function memory:init(data)
	self.data = data
end

--- Read a 8-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readUint8(offset)
	return byte(self.data, offset)
end

--- Read a big-endian 16-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readUint16BE(offset)
	local a, b = byte(self.data, offset, offset + 1)
	if not b then
		return nil
	end

	return a * 0x100 + b
end

--- Read a little-endian 16-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readUint16LE(offset)
	local a, b = byte(self.data, offset, offset + 1)
	if not b then
		return nil
	end

	return a + b * 0x100
end

--- Read a big-endian 32-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readUint32BE(offset)
	local a, b, c, d = byte(self.data, offset, offset + 3)
	if not d then
		return nil
	end

	return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

--- Read a little-endian 32-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readUint32LE(offset)
	local a, b, c, d = byte(self.data, offset, offset + 3)
	if not d then
		return nil
	end

	return a + b * 0x100 + c * 0x10000 + d * 0x1000000
end

--- Read a big-endian 64-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readUint64BE(offset)
	local hi = self:readUint32BE(offset)
	local lo = self:readUint32BE(offset + 4)
	if hi == nil or lo == nil then
		return nil
	end

	return hi * 0x100000000 + lo
end

--- Read a little-endian 64-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readUint64LE(offset)
	local lo = self:readUint32LE(offset)
	local hi = self:readUint32LE(offset + 4)
	if hi == nil or lo == nil then
		return nil
	end

	return hi * 0x100000000 + lo
end

--- Read a 8-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readInt8(offset)
	local value = self:readUint8(offset)
	if not value then
		return nil
	end

	return value < 0x80 and value or value - 0x100
end

--- Read a big-endian 16-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readInt16BE(offset)
	local value = self:readUint16BE(offset)
	if not value then
		return nil
	end

	return value < 0x8000 and value or value - 0x10000
end

--- Read a little-endian 16-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readInt16LE(offset)
	local value = self:readUint16LE(offset)
	if not value then
		return nil
	end

	return value < 0x8000 and value or value - 0x10000
end

--- Read a big-endian 32-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readInt32BE(offset)
	local value = self:readUint32BE(offset)
	if not value then
		return nil
	end

	return value < 0x80000000 and value or value - 0x100000000
end

--- Read a little-endian 32-bit integer from the memory at the given offset.
--- @param offset integer
--- @return integer|nil
function memory:readInt32LE(offset)
	local value = self:readUint32LE(offset)
	if not value then
		return nil
	end

	return value < 0x80000000 and value or value - 0x100000000
end

--- Read a string of the given length from the memory at the given offset.
--- @param offset integer
--- @param length integer
--- @return string|nil
function memory:read(offset, length)
	if offset < 1 or length < 0 or offset + length - 1 > #self.data then
		return nil
	end

	return self.data:sub(offset, offset + length - 1)
end

return memory
