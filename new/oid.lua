local openssl = require('openssl')

---@class git.oid : string.buffer
---@class git.oid_binary : string.buffer

---@class git.oid_type
---@field algorithm string
---@field hex_length integer
---@field bin_length integer
local oid_type = {}

local hex_alphabet = {}
for i = 0, 255 do hex_alphabet[i] = string.format('%02x', i) end

---@param buf string.buffer
---@param bin git.oid_binary
---@return git.oid
function oid_type:bin2hex(buf, bin)
    for i = 1, self.bin_length do
        local byte = string.byte(bin:get(1))
        buf:put(hex_alphabet[byte])
    end

    return buf
end

---@param buf string.buffer
---@param hexhash git.oid
---@return git.oid_binary
function oid_type:hex2bin(buf, hexhash)
    for i = 1, self.hex_length, 2 do
        local byte = tonumber(hexhash:get(2), 16)
        buf:put(string.char(byte))
    end

    return buf
end

---@param data string
---@param kind? string
function oid_type:digest(data, kind)
    if kind then
        local digest = openssl.digest.new(oid_type.algorithm)
        digest:update(kind .. #data .. '\x00')
        return digest:final(data)
    else
        return openssl.digest.digest(oid_type.algorithm, data)
    end
end

---@param algorithm string?
function oid_type:set_algorithm(algorithm)
    if algorithm == nil then algorithm = 'sha1' end

    assert(pcall(openssl.digest.get, algorithm), 'invalid algorithm')

    self.algorithm = algorithm
    self.hex_length = #openssl.digest.digest(algorithm, '')
    self.bin_length = self.bin_length / 2
end

return oid_type
