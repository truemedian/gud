local openssl = require('openssl')

local buffer = require('sshkey/format/buffer')
local openssh = require('sshkey/format/openssh')

---@class sshkey.key
---@field kt string
---@field pk userdata
---@field sk userdata
---@field impl table

---Decode a SSH or PKCS private key from the given data and passphrase.
---@param data string
---@param passphrase string|nil
---@return sshkey.key|nil, string|nil
local function load_private(data, passphrase)
	assert(type(data) == 'string', 'load_private: data must be a string')
	assert(passphrase == nil or type(passphrase) == 'string', 'load_private: passphrase must be a string or nil')

	if data:sub(1, 36) == '-----BEGIN OPENSSH PRIVATE KEY-----\n' then
		local last = data:find('\n-----END OPENSSH PRIVATE KEY-----', 37, true)
		local encoded = data:sub(37, last - 1)
		local decoded = openssl.base64(encoded, false, false)

		return openssh.load_private_openssh(decoded, passphrase)
	else
		return openssh.load_private_other(data, passphrase)
	end
end

---Decode a SSH or PKCS public key from the given data.
---@param data string
---@return sshkey.key|nil, string|nil
local function load_public(data)
	assert(type(data) == 'string', 'load_public: data must be a string')

	if data:sub(1, 4) == 'ssh-' or data:sub(1, 6) == 'ecdsa-' then
		return openssh.load_public_openssh(data)
	else
		return openssh.load_public_other(data)
	end
end

---Encode a SSH public key from the given key.
---@param key sshkey.key
---@return string
local function save_public(key)
	assert(key.kt and key.pk, 'save_public: not a sshkey')

	return openssh.save_public_openssh(key)
end

---Generate a fingerprint for the given key.
---@param key sshkey.key
---@return string
local function fingerprint(key)
	assert(key.kt and key.pk, 'fingerprint: not a sshkey')

	local public = key.impl.serialize_public(key)
	local hashed = openssl.digest.digest('sha256', public, true)
	local encoded = openssl.base64(hashed, true, true)

	return 'SHA256:' .. encoded
end

---Sign a piece of data with the given key and namespace.
---@param key sshkey.key
---@param data string
---@param namespace string
---@param unarmored boolean|nil
---@return string|nil, string|nil
local function sign(key, data, namespace, unarmored)
	assert(key.kt and key.pk, 'sign: not a sshkey')
	assert(type(data) == 'string', 'sign: data must be a string')
	assert(type(namespace) == 'string', 'sign: namespace must be a string')

	if not key.sk then return nil, 'sign: missing private key' end

	local hashed = openssl.digest.digest('sha512', data, true)
	local blob = buffer.write()
	blob:write_bytes('SSHSIG')
	blob:write_string(namespace)
	blob:write_string('')
	blob:write_string('sha512')
	blob:write_string(hashed)

	local signed, err = key.impl.sign_raw(key, blob:encode())
	if not signed then return nil, err end

	local pubkey = key.impl.serialize_public(key)
	local signature = buffer.write()
	signature:write_bytes('SSHSIG')
	signature:write_u32(1)
	signature:write_string(pubkey)
	signature:write_string(namespace)
	signature:write_string('')
	signature:write_string('sha512')
	signature:write_string(signed)

	if unarmored then return signature:encode() end

	local encoded = openssl.base64(signature:encode(), true, false)
	return '-----BEGIN SSH SIGNATURE-----\n' .. encoded .. '-----END SSH SIGNATURE-----'
end

---Verify an unarmored SSH signature with the given key, original data, and namespace.
---@param key sshkey.key
---@param signature string
---@param data string
---@param namespace string|nil
---@return boolean, string|nil
local function verify_raw(key, signature, data, namespace)
	assert(key.kt and key.pk, 'verify: not a sshkey')
	assert(type(signature) == 'string', 'verify: signature must be a string')
	assert(type(data) == 'string', 'verify: data must be a string')
	assert(namespace == nil or type(namespace) == 'string', 'verify: namespace must be a string')

	local sig_buffer = buffer.read(signature)

	local magic = sig_buffer:read_bytes(6)
	local version = sig_buffer:read_u32()
	if magic ~= 'SSHSIG' or version ~= 1 then -- malformed
		return false, 'verify: malformed signature'
	end

	local their_pubkey = sig_buffer:read_string()
	local their_namespace = sig_buffer:read_string()
	local reserved = sig_buffer:read_string()
	local hash_algo = sig_buffer:read_string()
	local signed = sig_buffer:read_string()
	if hash_algo ~= 'sha512' and hash_algo ~= 'sha256' then -- invalid algorithm
		return false, 'verify: malformed signature'
	end

	local pubkey_buf = buffer.read(their_pubkey)
	local key_type = pubkey_buf:read_string()
	if key_type ~= key.kt then -- wrong key type
		return false, 'verify: mismatched public key type'
	end

	local our_serialized = key.impl.serialize_public(key)
	if their_pubkey ~= our_serialized then
		-- some public keys can be stored in ever so slightly different form (primary rsa bignums may be front-padded with 0x00)
		-- so we need to deserialize the stored key and compare it to the one we have
		local stored_key = {}
		stored_key.kt = key_type
		key.impl.deserialize_public(stored_key, pubkey_buf)
		local their_serialized = key.impl.serialize_public(stored_key)

		if their_serialized ~= our_serialized then -- wrong key
			return false, 'verify: mismatched public key'
		end

		-- if the keys are the same after deserialization we can continue
	end

	if namespace == nil then namespace = their_namespace end

	if their_namespace ~= namespace then -- wrong key or namespace
		return false, 'verify: mismatched namespace'
	end

	local hashed = openssl.digest.digest(hash_algo, data, true)
	local blob = buffer.write()
	blob:write_bytes('SSHSIG')
	blob:write_string(namespace)
	blob:write_string(reserved)
	blob:write_string(hash_algo)
	blob:write_string(hashed)

	local verified, err = key.impl.verify_raw(key, signed, blob:encode())
	if not verified then return false, err end

	return true
end

---Verify a SSH signature with the given key, original data, and namespace.
---@param key sshkey.key
---@param encoded_signature string
---@param data string
---@param namespace string|nil
---@return boolean, string|nil
local function verify(key, encoded_signature, data, namespace)
	local _, encoded_start = encoded_signature:find('-----BEGIN SSH SIGNATURE-----\n', 1, true)
	local encoded_end = encoded_signature:find('\n-----END SSH SIGNATURE-----', encoded_start, true)
	local encoded = encoded_signature:sub(encoded_start + 1, encoded_end - 1)

	return verify_raw(key, encoded, data, namespace)
end

---Validate an unarmored SSH signature with the original data and namespace. Returns the key used to sign the data.
---@param signature string
---@param data string
---@param namespace string|nil
---@return sshkey.key|nil, string|nil
local function validate_raw(signature, data, namespace)
	assert(type(signature) == 'string', 'verify: signature must be a string')
	assert(type(data) == 'string', 'verify: data must be a string')
	assert(namespace == nil or type(namespace) == 'string', 'verify: namespace must be a string')

	local sig_buffer = buffer.read(signature)

	local magic = sig_buffer:read_bytes(6)
	local version = sig_buffer:read_u32()
	if magic ~= 'SSHSIG' or version ~= 1 then -- malformed
		return nil, 'verify: malformed signature'
	end

	local their_pubkey = sig_buffer:read_string()
	local their_namespace = sig_buffer:read_string()
	local reserved = sig_buffer:read_string()
	local hash_algo = sig_buffer:read_string()
	local signed = sig_buffer:read_string()
	if hash_algo ~= 'sha512' and hash_algo ~= 'sha256' then -- invalid algorithm
		return nil, 'verify: malformed signature'
	end

	local key = openssh.deserialize_public_openssh(their_pubkey)
	if not key then return nil, 'verify: malformed public key' end

	if namespace == nil then namespace = their_namespace end

	if their_namespace ~= namespace then -- wrong key or namespace
		return nil, 'verify: mismatched namespace'
	end

	local hashed = openssl.digest.digest(hash_algo, data, true)
	local blob = buffer.write()
	blob:write_bytes('SSHSIG')
	blob:write_string(namespace)
	blob:write_string(reserved)
	blob:write_string(hash_algo)
	blob:write_string(hashed)

	local verified, err = key.impl.verify_raw(key, signed, blob:encode())
	if not verified then return nil, err end

	return key
end

---Validate a SSH signature with the original data and namespace. Returns the key used to sign the data.
---@param encoded_signature string
---@param data string
---@param namespace string|nil
---@return sshkey.key|nil, string|nil
local function validate(encoded_signature, data, namespace)
	local _, encoded_start = encoded_signature:find('-----BEGIN SSH SIGNATURE-----\n', 1, true)
	local encoded_end = encoded_signature:find('\n-----END SSH SIGNATURE-----', encoded_start, true)
	local encoded = encoded_signature:sub(encoded_start + 1, encoded_end - 1)

	return validate_raw(encoded, data, namespace)
end

return {
	load_private = load_private,
	load_public = load_public,
	save_public = save_public,
	fingerprint = fingerprint,
	sign = sign,
	verify_raw = verify_raw,
	verify = verify,
	validate_raw = validate_raw,
	validate = validate,
}
