local openssl = require('openssl')

local openssh = require('sshkey/openssh')

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
	if data:sub(1, 4) == 'ssh-' then
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
	local blob = string.pack('>c6s4s4s4s4', 'SSHSIG', namespace, '', 'sha512', hashed)

	local signed, err = key.impl.sign_raw(key, blob, 'sha512')
	if not signed then
		return nil, 'signature failed: ' .. err
	end

	local pubkey = key.impl.serialize_public(key)
	local signature = string.pack('>c6I4s4s4s4s4s4', 'SSHSIG', 1, pubkey, namespace, '', 'sha512', signed)

	local encoded = openssl.base64(signature, true, false)
	return '-----BEGIN SSH SIGNATURE-----\n' .. encoded .. '-----END SSH SIGNATURE-----'
end

---Verify a SSH signature with the given key, original data, and namespace.
---@param key sshkey.key
---@param encoded_signature string
---@param data string
---@param namespace string
---@return boolean, string|nil
local function verify_signature(key, encoded_signature, data, namespace)
	local _, encoded_start = encoded_signature:find('-----BEGIN SSH SIGNATURE-----\n', 1, true)
	local encoded_end = encoded_signature:find('\n-----END SSH SIGNATURE-----', encoded_start, true)
	local encoded = encoded_signature:sub(encoded_start + 1, encoded_end - 1)

	local signature = openssl.base64(encoded, false, false)

	local magic, version, pubkey, ns, reserved, algo, signed = string.unpack('>c6I4s4s4s4s4s4', signature)
	if magic ~= 'SSHSIG' or version > 1 then -- malformed
		return false, 'malformed signature'
	end

	if algo ~= 'sha512' and algo ~= 'sha256' then -- invalid algorithm
		return false, 'malformed signature'
	end

	if ns ~= namespace or pubkey ~= key.impl.serialize_public(key) then -- wrong key or namespace
		return false, 'mismatched public key'
	end

	local hashed = openssl.digest.digest(algo, data, true)
	local blob = string.pack('>c6s4s4s4s4', 'SSHSIG', namespace, reserved, algo, hashed)

	local verified, err = key.impl.verify_raw(key, signed, blob)
	if not verified then
		return false, 'verification failed: ' .. err
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
