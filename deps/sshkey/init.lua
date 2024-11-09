local openssl = require('openssl')

local buffer = require('sshkey/format/buffer')
local openssh = require('sshkey/format/openssh')

---Decode a SSH or PKCS private key from the given data and passphrase.
---@param data string
---@param passphrase string|nil
---@return sshkey.key|nil, string|nil
local function decode_private_key(data, passphrase)
	if data:sub(1, 36) == '-----BEGIN OPENSSH PRIVATE KEY-----\n' then
		local last = data:find('\n-----END OPENSSH PRIVATE KEY-----', 37, true)
		local encoded = data:sub(37, last - 1)
		local decoded = openssl.base64(encoded, false, false)

		return openssh.decode_openssh_private_key(decoded, passphrase)
	else
		return openssh.decode_pkcs_private_key(data, passphrase)
	end
end

---Decode a SSH or PKCS public key from the given data.
---@param data string
---@return sshkey.key|nil, string|nil
local function decode_public_key(data)
	if data:sub(1, 4) == 'ssh-' or data:sub(1, 6) == 'ecdsa-' then
		return openssh.decode_openssh_public_key(data)
	else
		return openssh.decode_pkcs_public_key(data)
	end
end

---Sign a piece of data with the given key and namespace.
---@param key sshkey.key
---@param data string
---@param namespace string
---@return string|nil, string|nil
local function create_signature(key, data, namespace)
	local hashed = openssl.digest.digest('sha512', data, true)
	local blob = buffer.write()
	blob:write_bytes('SSHSIG')
	blob:write_string(namespace)
	blob:write_string('')
	blob:write_string('sha512')
	blob:write_string(hashed)

	local signed, err = key.impl.sign_raw(key, blob:encode())
	if not signed then
		return nil, 'signature failed: ' .. err
	end

	local pubkey = key.impl.serialize_public(key)
	local signature = buffer.write()
	signature:write_bytes('SSHSIG')
	signature:write_u32(1)
	signature:write_string(pubkey)
	signature:write_string(namespace)
	signature:write_string('')
	signature:write_string('sha512')
	signature:write_string(signed)

	local encoded = openssl.base64(signature:encode(), true, false)
	return '-----BEGIN SSH SIGNATURE-----\n' .. encoded .. '-----END SSH SIGNATURE-----'
end

---Verify a SSH signature with the given key, original data, and namespace.
---@param key sshkey.key
---@param encoded_signature string
---@param data string
---@param expected_namespace string
---@return boolean, string|nil
local function verify_signature(key, encoded_signature, data, expected_namespace)
	local _, encoded_start = encoded_signature:find('-----BEGIN SSH SIGNATURE-----\n', 1, true)
	local encoded_end = encoded_signature:find('\n-----END SSH SIGNATURE-----', encoded_start, true)
	local encoded = encoded_signature:sub(encoded_start + 1, encoded_end - 1)

	local signature = buffer.read(openssl.base64(encoded, false, false))

	local magic = signature:read_bytes(6)
	local version = signature:read_u32()
	if magic ~= 'SSHSIG' or version > 1 then -- malformed
		return false, 'verify: malformed signature'
	end

	local pubkey = signature:read_string()
	local namespace = signature:read_string()
	local reserved = signature:read_string()
	local hash_algo = signature:read_string()
	local signed = signature:read_string()
	if hash_algo ~= 'sha512' and hash_algo ~= 'sha256' then -- invalid algorithm
		return false, 'verify: malformed signature'
	end

	local pubkey_buf = buffer.read(pubkey)
	local key_type = pubkey_buf:read_string()
	if key_type ~= key.kt then -- wrong key type
		return false, 'verify: mismatched public key type'
	end

	local stored_key = {}
	stored_key.kt = key_type
	stored_key.impl = key.impl
	stored_key.impl.deserialize_public(stored_key, pubkey_buf)

	if key.impl.serialize_public(key) ~= stored_key.impl.serialize_public(key) then -- wrong key
		return false, 'verify: mismatched public key'
	end

	if expected_namespace == nil then
		expected_namespace = namespace
	end

	if namespace ~= expected_namespace then -- wrong key or namespace
		return false, 'verify: mismatched namespace'
	end

	local hashed = openssl.digest.digest(hash_algo, data, true)
	local blob = buffer.write()
	blob:write_bytes('SSHSIG')
	blob:write_string(expected_namespace)
	blob:write_string(reserved)
	blob:write_string(hash_algo)
	blob:write_string(hashed)

	local verified, err = key.impl.verify_raw(key, signed, blob:encode())
	if not verified then
		return false, err
	end

	return true
end

---Generate a fingerprint for the given key.
---@param key sshkey.key
---@return string
local function fingerprint(key)
	local public = key.impl.serialize_public(key)
	local hashed = openssl.digest.digest('sha256', public, true)
	local encoded = openssl.base64(hashed, true, true)

	return 'SHA256:' .. encoded
end

return {
	decode_private_key = decode_private_key,
	decode_public_key = decode_public_key,
	create_signature = create_signature,
	verify_signature = verify_signature,
	fingerprint = fingerprint,
}
