local bit = require('sshkey/bcrypt/bit-compat')

local band, rshift = bit.band, bit.rshift

---@class sshkey.read_buffer
---@field str string
---@field loc integer
local read_buffer = {}
read_buffer.__index = read_buffer

---@return integer
function read_buffer:read_u32()
	local a, b, c, d = string.byte(self.str, self.loc, self.loc + 3)
	self.loc = self.loc + 4

	return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

---@return string
function read_buffer:read_string()
	local len = self:read_u32()
	local str = self.str:sub(self.loc, self.loc + len - 1)
	self.loc = self.loc + len
	return str
end

---@param n integer
---@return string
function read_buffer:read_bytes(n)
	local str = self.str:sub(self.loc, self.loc + n - 1)
	self.loc = self.loc + n
	return str
end

---@return string
function read_buffer:left()
	local str = self.str:sub(self.loc)
	self.loc = #self.str + 1
	return str
end

local function new_read_buffer(str)
	return setmetatable({ str = str, loc = 1 }, read_buffer)
end
---@class sshkey.write_buffer
---@field parts table
local write_buffer = {}
write_buffer.__index = write_buffer

---@param n integer
function write_buffer:write_u32(n)
	local a = band(rshift(n, 24), 0xff)
	local b = band(rshift(n, 16), 0xff)
	local c = band(rshift(n, 8), 0xff)
	local d = band(n, 0xff)

	table.insert(self.parts, string.char(a, b, c, d))
end

---@param str string
function write_buffer:write_string(str)
	self:write_u32(#str)
	table.insert(self.parts, str)
end

---@param bytes string
function write_buffer:write_bytes(bytes)
	table.insert(self.parts, bytes)
end

---@return string
function write_buffer:encode()
	return table.concat(self.parts)
end

local function new_write_buffer()
	return setmetatable({ parts = {} }, write_buffer)
end

return {
	read = new_read_buffer,
	write = new_write_buffer,
}
