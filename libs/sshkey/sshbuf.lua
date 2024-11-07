local sshbuf = {}
sshbuf.__index = sshbuf

function sshbuf:read_u32()
    local n = string.unpack('>I4', self.str, self.loc)
    self.loc = self.loc + 4
    return n
end

function sshbuf:read_string()
    local len = self:read_u32()
    local str = self.str:sub(self.loc, self.loc + len - 1)
    self.loc = self.loc + len
    return str
end

function sshbuf:read_bytes(n)
    local str = self.str:sub(self.loc, self.loc + n - 1)
    self.loc = self.loc + n
    return str
end

return function(str)
    return setmetatable({str = str, loc = 1}, sshbuf)
end
