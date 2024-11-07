local openssl = require('openssl')

---@class git.oid : string
---@class git.oid_binary : string

---@class git.oid_type
---@field algorithm string
---@field hex_length integer
---@field bin_length integer
local oid_type = {}

local hex_alphabet = {}
for i = 0, 255 do
    hex_alphabet[i] = string.format('%02x', i)
end

---@param algo? string
---@return git.oid_type
function oid_type.new(algo)
    local self = setmetatable({}, {__index = oid_type})
    self:set_algorithm(algo)
    return self
end

---@param binhash git.oid_binary
---@return git.oid
function oid_type:bin2hex(binhash)
    assert(#binhash == self.bin_length, 'invalid object id')
    local buffer = {}

    for i = 1, self.bin_length do
        local byte = string.byte(binhash:sub(i, i))
        buffer[i] = hex_alphabet[byte]
    end

    return table.concat(buffer) ---@type git.oid
end

---@param hexhash git.oid
---@return git.oid_binary
function oid_type:hex2bin(hexhash)
    assert(#hexhash == self.hex_length, 'invalid object id')
    local buffer = {}

    for i = 1, self.hex_length, 2 do
        local byte = tonumber(hexhash:sub(i, i + 1), 16)
        buffer[(i + 1) / 2] = string.char(byte)
    end

    return table.concat(buffer) ---@type git.oid_binary
end

---@param data string
---@param kind? string
---@return git.oid
function oid_type:digest(data, kind)
    if kind then
        local digest = openssl.digest.new(self.algorithm)
        digest:update(kind .. ' ' .. #data .. '\x00')
        return digest:final(data)
    else
        return openssl.digest.digest(self.algorithm, data)
    end
end

---@param algorithm string?
function oid_type:set_algorithm(algorithm)
    if algorithm == nil then
        algorithm = 'sha1'
    end

    assert(pcall(openssl.digest.get, algorithm), 'invalid algorithm')

    self.algorithm = algorithm
    self.hex_length = #openssl.digest.digest(algorithm, '')
    self.bin_length = self.hex_length / 2
end

return oid_type
