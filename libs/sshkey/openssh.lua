local openssl = require('openssl')

local bcrypt = require('sshkey/bcrypt')
local buffer = require('sshkey/buffer')

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
	require('sshkey/impl/ed25519').ed25519,
	require('sshkey/impl/rsa').rsa,
	require('sshkey/impl/ecdsa').ecdsa_nistp256,
	require('sshkey/impl/ecdsa').ecdsa_nistp384,
	require('sshkey/impl/ecdsa').ecdsa_nistp521,
}

local function get_keytype_impl(kt)
	for _, impl in ipairs(impls) do
		if impl.name == kt then
			return impl
		end
	end

	return nil, 'unknown key type: ' .. kt
end

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
		return nil, 'passphrase required'
	end

	local cipher, cipher_info, key
	if ciphername_translation[ciphername] then
		cipher = openssl.cipher.get(ciphername_translation[ciphername])
		cipher_info = cipher:info()
	else
		return nil, 'unknown cipher: ' .. ciphername
	end

	-- parse necessary kdf options
	local kdf_buf = buffer(kdfoptions)
	if kdfname == 'bcrypt' then
		local salt = kdf_buf:read_string()
		local rounds = kdf_buf:read_u32()

		local keylen = cipher_info.key_length + cipher_info.iv_length
		key = bcrypt.pbkdf(passphrase, salt, keylen, rounds)
	else
		return nil, 'unknown kdf: ' .. kdfname
	end

	-- decrypt private key data
	local dc_key = key:sub(1, cipher_info.key_length)
	local dc_iv = key:sub(cipher_info.key_length + 1)
	return cipher:decrypt(data, dc_key, dc_iv)
end

---Decode an OpenSSH private key from the given data and passphrase.
---@param data string
---@param passphrase string|nil
---@return sshkey.key|nil, string|nil
local function decode_openssh_private_key(data, passphrase)
	local buf = buffer(data)
	if buf:read_bytes(15) ~= 'openssh-key-v1\x00' then
		return nil, 'invalid openssh private key: bad magic'
	end

	local ciphername = buf:read_string()
	local kdfname = buf:read_string()
	local kdfoptions = buf:read_string()
	local nkeys = buf:read_u32()

	local public_key_data = buf:read_string()
	local private_key_encrypted = buf:read_string()

	-- check for multiple keys and extraneous data
	if nkeys > 1 then
		return nil, 'invalid openssh private key: multiple keys'
	end

	if buf.loc ~= #buf.str + 1 then
		return nil, 'invalid openssh private key: extraneous data'
	end

	local key = {}
	-- parse public key first before even attempting to decrypt private key
	local pubkey_buf = buffer(public_key_data)
	key.kt = pubkey_buf:read_string()
	key.impl = get_keytype_impl(key.kt)
	if not key.impl then
		return nil, 'unknown key type: ' .. key.kt
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
	local private_key_buf = buffer(private_key_encrypted)
	local check1 = private_key_buf:read_u32()
	local check2 = private_key_buf:read_u32()
	if check1 ~= check2 then
		return nil, 'invalid openssh private key: decryption failed'
	end

	-- todo: handle certificates
	local privkey_keytype = private_key_buf:read_string()
	if privkey_keytype ~= key.kt then
		return nil, 'invalid openssh private key: public and private key types do not match'
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
			return nil, 'invalid openssh private key: invalid padding'
		end
	end

	do -- checksum to ensure private key and public key match
		local digest = openssl.digest.signInit(nil, key.sk)
		if not digest then
			return nil, 'allocation failed'
		end

		local signature, sig_err = digest:sign('signature-check')
		if not signature then
			return nil, 'invalid openssh private key: ' .. sig_err
		end

		digest = openssl.digest.verifyInit(nil, key.pk)
		if not digest then
			return nil, 'allocation failed'
		end

		if not digest:verify(signature, 'signature-check') then
			return nil, 'invalid openssh private key: public and private key do not match'
		end
	end

	return key
end

---Decode a PKCS private key from the given data and passphrase.
---@param data string
---@param passphrase string|nil
---@return sshkey.key|nil, string|nil
local function decode_pkcs_private_key(data, passphrase)
	local sk, sk_err = openssl.pkey.read(data, true, passphrase)
	if not sk then
		return nil, 'parse private key failed: ' .. sk_err
	end

	local pk = sk:get_public()
	if not pk then
		return nil, 'extract public key failed'
	end

	local info = sk:parse()
	if not info then
		return nil, 'parse private key failed'
	end

	local key = { sk = sk, pk = pk }
	if info.type == 'rsa' then
		key.kt = 'ssh-rsa'
	else
		return nil, 'unsupported key type: ' .. info.type
	end

	key.impl = get_keytype_impl(key.kt)
	return key
end

---Decode an OpenSSH public key from the given data.
---@param data string
---@return sshkey.key|nil, string|nil
local function decode_openssh_public_key(data)
	local prefix, encoded, comment = data:match('^(%S+) (%S+)%s*(.*)$')
	local decoded = openssl.base64(encoded, false, true)

	local buf = buffer(decoded)
	local kt = buf:read_string()
	if kt ~= prefix then
		return nil, 'invalid openssh public key: key type mismatch'
	end

	local impl = get_keytype_impl(kt)
	if not impl then
		return nil, 'unknown key type: ' .. kt
	end

	local key = { kt = kt, impl = impl, comment = comment }
	local pk_success, pk_err = impl.deserialize_public(key, buf)
	if not pk_success then
		return nil, pk_err
	end

	return key
end

---Decode a PKCS#1 public key from the given data.
---@param data string
---@return sshkey.key|nil, string|nil
local function decode_pkcs_public_key(data)
	local pk, pk_err = openssl.pkey.read(data, false)
	if not pk then
		return nil, 'parse public key failed: ' .. pk_err
	end

	local info = pk:parse()
	if not info then
		return nil, 'parse public key failed'
	end

	local key = { sk = pk, pk = pk }
	if info.type == 'rsa' then
		key.kt = 'ssh-rsa'
	else
		return nil, 'unsupported key type: ' .. info.type
	end

	key.impl = get_keytype_impl(key.kt)
	return key
end

return {
	decode_openssh_private_key = decode_openssh_private_key,
	decode_pkcs_private_key = decode_pkcs_private_key,
	decode_openssh_public_key = decode_openssh_public_key,
	decode_pkcs_public_key = decode_pkcs_public_key,
}
