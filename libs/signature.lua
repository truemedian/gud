local openssl = require('openssl')
local base64 = require('base64')

local function decode_sshkey(data)
    local keytype_len = string.unpack('>I4', data)
    local keytype = data:sub(5, 4 + keytype_len)
    local offset = 4 + keytype_len

    if keytype == 'ssh-rsa' then
        local e_len = string.unpack('>I4', data, offset + 1)
        local e = data:sub(offset + 5, offset + 4 + e_len)
        offset = offset + 4 + e_len

        local n_len = string.unpack('>I4', data, offset + 1)
        local n = data:sub(offset + 5, offset + 4 + n_len)
        offset = offset + 4 + n_len

        return {kt = keytype, e = e, n = n}
    elseif keytype == 'ssh-ed25519' then
        local key_len = string.unpack('>I4', data, offset + 1)
        local key = data:sub(offset + 5, offset + 4 + key_len)
        return {kt = keytype, key = key}
    else
        error('unknown key type: ' .. keytype)
    end
end

local function decode_openssh_private_key(data)
    assert(data:sub(1, 15) == 'openssh-key-v1\x00', 'invalid openssh private key')
    local ciphername_len = string.unpack('>I4', data, 16)
    local ciphername = data:sub(20, 19 + ciphername_len)
    local offset = 20 + ciphername_len

    local kdfname_len = string.unpack('>I4', data, offset)
    local kdfname = data:sub(offset + 4, offset + 3 + kdfname_len)
    offset = offset + 4 + kdfname_len

    local kdf_len = string.unpack('>I4', data, offset)

    p(ciphername, kdfname)
end

local function decode_private_key(data)
    if data:sub(1, 35) == '-----BEGIN OPENSSH PRIVATE KEY-----' then
        local last = data:find('-----END OPENSSH PRIVATE KEY-----', 36, true)
        local encoded = data:sub(36, last - 1):gsub('\n', '')
        local decoded = base64.decode(encoded)

        decode_openssh_private_key(decoded)

        return nil, 'cannot decode openssh private key. use ssh-keygen -p -m pem -f key'
    elseif data:sub(1, 27) == '-----BEGIN RSA PRIVATE KEY-----' then
        return openssl.pkey.read(data, true)
    else
        error('unknown private key format')
    end
end

local d = require('fs').readFileSync('/home/nameless/.ssh/id_ed25519')
local key = decode_private_key(d)
