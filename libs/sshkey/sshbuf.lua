---@class sshkey.buf
---@field str string
---@field loc integer
local sshbuf = {}
sshbuf.__index = sshbuf

---@return integer
function sshbuf:read_u32()
	local n = string.unpack('>I4', self.str, self.loc)
	self.loc = self.loc + 4
	return n
end

---@return string
function sshbuf:read_string()
	local len = self:read_u32()
	local str = self.str:sub(self.loc, self.loc + len - 1)
	self.loc = self.loc + len
	return str
end

---@param n integer
---@return string
function sshbuf:read_bytes(n)
	local str = self.str:sub(self.loc, self.loc + n - 1)
	self.loc = self.loc + n
	return str
end

---@return string
function sshbuf:left()
	local str = self.str:sub(self.loc)
	self.loc = #self.str + 1
	return str
end

---@param str string
---@return sshkey.buf
return function(str)
	return setmetatable({ str = str, loc = 1 }, sshbuf)
end
