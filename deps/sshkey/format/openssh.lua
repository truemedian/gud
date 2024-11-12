local openssl = require('openssl')

local bcrypt = require('sshkey/bcrypt/bcrypt')
local buffer = require('sshkey/format/buffer')

local ciphername_translation = {
	['3des-ctr'] = 'des-ede3-cbc',
	['aes128-cbc'] = 'aes-128-cbc',
	['aes192-cbc'] = 'aes-192-cbc',
	['aes256-cbc'] = 'aes-256-cbc',
	['aes128-ctr'] = 'aes-128-ctr',
	['aes192-ctr'] = 'aes-192-ctr',
	['aes256-ctr'] = 'aes-256-ctr',
	['aes128-gcm@openssh.com'] = 'aes-128-gcm',
	['aes256-gcm@openssh.com'] = 'aes-256-gcm',
}

local impls = {
	require('sshkey/pkey/ed25519').ed25519,
	require('sshkey/pkey/rsa').rsa,
	require('sshkey/pkey/ecdsa').ecdsa_nistp256,
	require('sshkey/pkey/ecdsa').ecdsa_nistp384,
	require('sshkey/pkey/ecdsa').ecdsa_nistp521,
}

local function get_keytype_impl(kt)
	for _, impl in ipairs(impls) do
		if impl.name == kt then
			return impl
		end
	end

	return nil, 'unknown key type: ' .. kt
end

---Decrypt the encrypted private key portion of an OpenSSH private key. Passphrase can only be `nil` if this data is
---not encrypted, in which case it is returned as-is.
---@param ciphername string
---@param kdfname string
---@param kdfoptions string
---@param data string
---@param passphrase string|nil
---@return string|nil, string|nil
local function decrypt_section(ciphername, kdfname, kdfoptions, data, passphrase)
	if ciphername == 'none' and kdfname == 'none' then
		return data
	end

	if not passphrase or passphrase == '' then
		return nil, 'decrypt_section: passphrase required'
	end

	local cipher, cipher_info, key
	if ciphername_translation[ciphername] then
		cipher = openssl.cipher.get(ciphername_translation[ciphername])
		cipher_info = cipher:info()
	else
		return nil, 'decrypt_section: unknown cipher: ' .. ciphername
	end

	-- parse necessary kdf options
	local kdf_buf = buffer.read(kdfoptions)
	if kdfname == 'bcrypt' then
		local salt = kdf_buf:read_string()
		local rounds = kdf_buf:read_u32()

		local keylen = cipher_info.key_length + cipher_info.iv_length
		key = bcrypt.pbkdf(passphrase, salt, keylen, rounds)
	else
		return nil, 'decrypt_section: unknown kdf: ' .. kdfname
	end

	if #data % cipher_info.block_size ~= 0 then
		return nil, 'decrypt_section: invalid data length'
	end

	-- decrypt private key data
	local dc_key = key:sub(1, cipher_info.key_length)
	local dc_iv = key:sub(cipher_info.key_length + 1)
	local decrypted, err = cipher:decrypt(data, dc_key, dc_iv, false)
	if not decrypted then
		if err then
			return nil, 'decrypt_section: ' .. err
		else
			return nil, 'decrypt_section: decryption failed for unknown reason'
		end
	end

	return decrypted
end

---Decode an OpenSSH private key from the given data and passphrase.
---@param data string
---@param passphrase string|nil
---@return sshkey.key|nil, string|nil
local function load_private_openssh(data, passphrase)
	local buf = buffer.read(data)
	if buf:read_bytes(15) ~= 'openssh-key-v1\x00' then
		return nil, 'load_private_openssh: bad magic'
	end

	local ciphername = buf:read_string()
	local kdfname = buf:read_string()
	local kdfoptions = buf:read_string()
	local nkeys = buf:read_u32()

	local public_key_data = buf:read_string()
	local private_key_encrypted = buf:read_string()

	-- check for multiple keys and extraneous data
	if nkeys > 1 then
		return nil, 'load_private_openssh: multiple keys'
	end

	if buf.loc ~= #buf.str + 1 then
		return nil, 'load_private_openssh: extraneous data'
	end

	local key = {}
	-- parse public key first before even attempting to decrypt private key
	local pubkey_buf = buffer.read(public_key_data)
	key.kt = pubkey_buf:read_string()
	key.impl = get_keytype_impl(key.kt)
	if not key.impl then
		return nil, 'load_private_openssh: unknown key type: ' .. key.kt
	end

	local pk_success, err
	pk_success, err = key.impl.deserialize_public(key, pubkey_buf)
	if not pk_success then
		return nil, err
	end

	-- decrypt private key
	local private_key_data
	private_key_data, err = decrypt_section(ciphername, kdfname, kdfoptions, private_key_encrypted, passphrase)
	if not private_key_data then
		return nil, err
	end

	-- ensure the decrypted private key is valid
	local private_key_buf = buffer.read(private_key_data)
	local check1 = private_key_buf:read_u32()
	local check2 = private_key_buf:read_u32()
	if check1 ~= check2 then
		return nil, 'load_private_openssh: incorrect passphrase'
	end

	-- todo: handle certificates
	local privkey_keytype = private_key_buf:read_string()
	if privkey_keytype ~= key.kt then
		return nil, 'load_private_openssh: public and private key types do not match'
	end

	local sk_success
	sk_success, err = key.impl.deserialize_private(key, private_key_buf)
	if not sk_success then
		return nil, err
	end

	-- read comment and ensure padding is correct
	key.comment = private_key_buf:read_string()
	local padding = private_key_buf:left()
	for i = 1, #padding do
		if padding:byte(i) ~= i then
			return nil, 'load_private_openssh: invalid padding'
		end
	end

	do -- checksum to ensure private key and public key match
		local digest = openssl.digest.signInit(nil, key.sk)
		if not digest then
			return nil, 'load_private_openssh: allocation failed'
		end

		local signature, sig_err = digest:sign('signature-check')
		if not signature then
			return nil, 'load_private_openssh: ' .. sig_err
		end

		digest = openssl.digest.verifyInit(nil, key.pk)
		if not digest then
			return nil, 'load_private_openssh: allocation failed'
		end

		if not digest:verify(signature, 'signature-check') then
			return nil, 'load_private_openssh: public and private key do not match'
		end
	end

	return key
end

---Decode a non-OpenSSH private key from the given data and passphrase.
---@param data string
---@param passphrase string|nil
---@return sshkey.key|nil, string|nil
local function load_private_other(data, passphrase)
	local sk, sk_err = openssl.pkey.read(data, true, nil, passphrase)
	if not sk then
		if sk_err == 'bad decrypt' then
			return nil, 'load_private_other: incorrect passphrase'
		elseif not sk_err then
			return nil, 'load_private_other: failed to parse private key for unknown reason'
		else
			return nil, 'load_private_other: ' .. sk_err
		end
	end

	local pk = sk:get_public()
	if not pk then
		return nil, 'load_private_other: failed to extract public key'
	end

	local info = sk:parse()
	if not info then
		return nil, 'load_private_other: parse failed'
	end

	local key = { sk = sk, pk = pk }
	if info.type == 'RSA' then
		key.kt = 'ssh-rsa'
	elseif info.type == 'EC' then
		key.kt = 'ecdsa-sha2-nistp' .. info.bits

		local ec = info.ec:parse()
		key.pk_pt = ec.group:point2oct(ec.pub_key)
	else
		return nil, 'load_private_other: unsupported key type: ' .. info.type
	end

	key.impl = get_keytype_impl(key.kt)
	return key
end

---Decode an OpenSSH public key from the given data.
---@param data string
---@return sshkey.key|nil, string|nil
local function load_public_openssh(data)
	local prefix, encoded, comment = data:match('^(%S+) (%S+)%s*(.*)$')
	local decoded = openssl.base64(encoded, false, true)

	local buf = buffer.read(decoded)
	local kt = buf:read_string()
	if kt ~= prefix then
		return nil, 'load_public_openssh: key type mismatch'
	end

	local impl = get_keytype_impl(kt)
	if not impl then
		return nil, 'load_public_openssh: unknown key type: ' .. kt
	end

	local key = { kt = kt, impl = impl, comment = comment }
	local pk_success, pk_err = impl.deserialize_public(key, buf)
	if not pk_success then
		return nil, 'load_public_openssh: ' .. pk_err
	end

	return key
end

---Decode a non-OpenSSH public key from the given data.
---@param data string
---@return sshkey.key|nil, string|nil
local function load_public_other(data)
	local pk, pk_err = openssl.pkey.read(data, false)
	if not pk then
		return nil, 'load_public_other: ' .. pk_err
	end

	local info = pk:parse()
	if not info then
		return nil, 'load_public_other: parse failed'
	end

	local key = { sk = pk, pk = pk }
	if info.type == 'RSA' then
		key.kt = 'ssh-rsa'
	elseif info.type == 'EC' then
		key.kt = 'ecdsa-sha2-nistp' .. info.bits

		local ec = info.ec:parse()
		key.pk_pt = ec.group:point2oct(ec.pub_key)
	else
		return nil, 'load_public_other: unsupported key type: ' .. info.type
	end

	key.impl = get_keytype_impl(key.kt)
	return key
end

---Encode an OpenSSH public key from the given key.
---@param key sshkey.key
---@return string
local function save_public_openssh(key, comment)
	local encoded = key.impl.serialize_public(key)
	local prefix = key.kt
	if comment or key.comment then
		return prefix .. ' ' .. openssl.base64(encoded, true, true) .. ' ' .. ((comment or key.comment or ''):match('^%s*(.*)%s*$'))
	else
		return prefix .. ' ' .. openssl.base64(encoded, true, true)
	end
end

return {
	load_private_openssh = load_private_openssh,
	load_private_other = load_private_other,
	load_public_openssh = load_public_openssh,
	load_public_other = load_public_other,
	save_public_openssh = save_public_openssh,
}
