---@class sshkey.buffer
---@field str string
---@field loc integer
local buffer = {}
buffer.__index = buffer

---@return integer
function buffer:read_u32()
	local n = string.unpack('>I4', self.str, self.loc)
	self.loc = self.loc + 4
	return n
end

---@return string
function buffer:read_string()
	local len = self:read_u32()
	local str = self.str:sub(self.loc, self.loc + len - 1)
	self.loc = self.loc + len
	return str
end

---@param n integer
---@return string
function buffer:read_bytes(n)
	local str = self.str:sub(self.loc, self.loc + n - 1)
	self.loc = self.loc + n
	return str
end

---@return string
function buffer:left()
	local str = self.str:sub(self.loc)
	self.loc = #self.str + 1
	return str
end

---@param str string
---@return sshkey.buffer
return function(str)
	return setmetatable({ str = str, loc = 1 }, buffer)
end
