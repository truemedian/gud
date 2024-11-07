local openssl = require('openssl')
local asn1 = openssl.asn1

local oid = asn1.new_object('1.3.101.112')
local algorithm_identifier = asn1.put_object(asn1.SEQUENCE, 0, oid:i2d(), true)

local function encode_publickey_der(pk)
    local public_key = asn1.new_string(pk, asn1.BIT_STRING)
    local public_key_info = asn1.put_object(asn1.SEQUENCE, 0, algorithm_identifier .. public_key:i2d(), true)

    return public_key_info
end

local function deserialize_public(buf)
    local pk = buf:read_string()
    if #pk ~= 32 then
        return nil, 'invalid ed25519 public key'
    end

    -- lua-openssl does not support directly creating ed25519 keys, so we must
    -- load it into DER form and then ask it to parse it.
    local encoded_key = encode_publickey_der(pk)

    local pubkey, err = openssl.pkey.read(encoded_key, false)
    if not pubkey then
        return nil, 'parse public key failed: ' .. err
    end

    return {kt = 'ed25519', pk = pubkey}
end

local ed25519_impl = {name = 'ssh-ed25519', keybits = 256, deserialize_public = deserialize_public}

return {ed25519 = ed25519_impl}
