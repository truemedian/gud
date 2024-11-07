local openssl = require('openssl')
local base64 = require('base64')

local bcrypt = require('sshkey/bcrypt')
local sshbuf = require('sshkey/sshbuf')

local ciphername_translation = {
    ['3des-ctr'] = 'des-ede3-cbc',
    ['aes128-cbc'] = 'aes-128-cbc',
    ['aes192-cbc'] = 'aes-192-cbc',
    ['aes256-cbc'] = 'aes-256-cbc',
    ['aes128-ctr'] = 'aes-128-ctr',
    ['aes192-ctr'] = 'aes-192-ctr',
    ['aes256-ctr'] = 'aes-256-ctr',
    ['aes128-gcm@openssh.com'] = 'aes-128-gcm',
    ['aes256-gcm@openssh.com'] = 'aes-256-gcm'
}

local impls = {
    require('sshkey/impl/ed25519').ed25519,
}

local function decode_public_sshkey(buf)
    local ktype = buf:read_string()
    for _, impl in ipairs(impls) do
        if impl.name == ktype then
            return impl.deserialize_public(buf)
        end
    end

    return nil, 'unknown key type: ' .. ktype
end

local function decode_openssh_private_key(buf, passphrase)
    if buf:read_bytes(15) ~= 'openssh-key-v1\x00' then
        return nil, 'invalid openssh private key: bad magic'
    end

    local ciphername = buf:read_string()
    local kdfname = buf:read_string()
    local kdfoptions = buf:read_string()
    local nkeys = buf:read_u32()

    local pubkey_s = buf:read_string()
    local privkey_e = buf:read_string()

    -- check for multiple keys and extraneous data
    if nkeys > 1 then
        return 'invalid openssh private key: multiple keys'
    end

    if buf.loc ~= #buf.str + 1 then
        return nil, 'invalid openssh private key: extraneous data'
    end

    -- parse public key first before even attempting to decrypt private key
    local pubkey_buf = sshbuf(pubkey_s)
    local pubkey, pubkey_err = decode_public_sshkey(pubkey_buf)
    if not pubkey then
        return nil, pubkey_err
    end

    -- decrypt private key
    local privkey_s = privkey_e
    if ciphername ~= 'none' and kdfname ~= 'none' then
        local cipher, cipher_info
        if ciphername_translation[ciphername] then
            cipher = openssl.cipher.get(ciphername_translation[ciphername])
            cipher_info = cipher:info()
        else
            return nil, 'unknown cipher: ' .. ciphername
        end

        local key -- derived key
        if kdfname ~= 'none' and passphrase == '' then
            return nil, 'passphrase required'
        end

        -- parse necessary kdf options
        local kdf_buf = sshbuf(kdfoptions)
        if kdfname == 'bcrypt' then
            local salt = kdf_buf:read_string()
            local rounds = kdf_buf:read_u32()

            local keylen = cipher_info.key_length + cipher_info.iv_length
            key = bcrypt.pbkdf(passphrase, salt, keylen, rounds)
        end

        -- decrypt private key data
        local dc_key = key:sub(1, cipher_info.key_length)
        local dc_iv = key:sub(cipher_info.key_length + 1)
        privkey_s = cipher:decrypt(privkey_e, dc_key, dc_iv)
    elseif ciphername ~= 'none' or kdfname ~= 'none' then
        return nil, 'invalid openssh private key: ciphername or kdfname is none but not both'
    end

    -- ensure the decrypted private key is valid
    local privkey_buf = sshbuf(privkey_s)
    local check1 = privkey_buf:read_u32()
    local check2 = privkey_buf:read_u32()
    if check1 ~= check2 then
        return nil, 'invalid openssh private key: decryption failed'
    end


    p(privkey_s:sub(offset))
end

local function decode_private_key(data, passphrase)
    if data:sub(1, 35) == '-----BEGIN OPENSSH PRIVATE KEY-----' then
        local last = data:find('-----END OPENSSH PRIVATE KEY-----', 36, true)
        local encoded = data:sub(36, last - 1):gsub('\n', '')
        local decoded = base64.decode(encoded)

        local buf = sshbuf(decoded)
        p(decode_openssh_private_key(buf, passphrase))

        return nil, 'cannot decode openssh private key. use ssh-keygen -p -m pem -f key'
    elseif data:sub(1, 31) == '-----BEGIN RSA PRIVATE KEY-----' then
        return openssl.pkey.read(data, true)
    else
        error('unknown private key format')
    end
end

