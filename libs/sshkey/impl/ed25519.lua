local openssl = require('openssl')
local asn1 = openssl.asn1

local oid = asn1.new_object('1.3.101.112')
local algo_id = asn1.put_object(asn1.SEQUENCE, 0, oid:i2d(), true)
local pki_version = asn1.new_integer(0):i2d()

local function encode_publickey_der(pk)
	local pk0 = asn1.new_string(pk, asn1.BIT_STRING)
	return asn1.put_object(asn1.SEQUENCE, 0, algo_id .. pk0:i2d(), true)
end

local function encode_privatekey_der(sk)
	local sk0 = asn1.new_string(sk, asn1.OCTET_STRING):i2d()
	local sk1 = asn1.new_string(sk0, asn1.OCTET_STRING)
	return asn1.put_object(asn1.SEQUENCE, 0, pki_version .. algo_id .. sk1:i2d(), true)
end

---@param key sshkey.key.ed25519
---@return string
local function serialize_public(key)
	return string.pack('>s4s4', 'ed25519', key.pk_s)
end

---@param key sshkey.key.ed25519
---@param buf sshkey.buffer
---@return boolean|nil, string|nil
local function deserialize_public(key, buf)
	local pk_s = buf:read_string()
	if #pk_s ~= 32 then
		return nil, 'ed25519.deserialize_public: malformed key'
	end

	-- lua-openssl does not support directly creating ed25519 keys, so we must
	-- load it into DER form and then ask it to parse it.
	local encoded_key = encode_publickey_der(pk_s)

	local pk, err = openssl.pkey.read(encoded_key, false)
	if not pk then
		return nil, 'ed25519.deserialize_public: ' .. err
	end

	key.pk = pk
	key.pk_s = pk_s
	return true
end

---@param key sshkey.key.ed25519
---@param buf sshkey.buffer
---@return boolean|nil, string|nil
local function deserialize_private(key, buf)
	local pk_s = buf:read_string()
	local sk_s = buf:read_string()
	if #pk_s ~= 32 or #sk_s ~= 64 or sk_s:sub(33) ~= pk_s then
		return nil, 'ed25519.deserialize_private: malformed keypair'
	end

	-- lua-openssl does not support directly creating ed25519 keys, so we must
	-- load it into DER form and then ask it to parse it.
	--
	-- the private key is the first 32 bytes of the keypair bytes
	local encoded_key = encode_privatekey_der(sk_s:sub(1, 32))

	local sk, err = openssl.pkey.read(encoded_key, true)
	if not sk then
		return nil, 'ed25519.deserialize_private: ' .. err
	end

	key.sk = sk
	return true
end

---@param key sshkey.key.ed25519
---@param data string
---@return string|nil, string|nil
local function sign_raw(key, data)
	local digest = openssl.digest.signInit(nil, key.sk)
	if not digest then
		return nil, 'ed25519.sign: allocation failed'
	end

	local signed = digest:sign(data)
	return string.pack('>s4s4', 'ssh-ed25519', signed)
end

---@param key sshkey.key.ed25519
---@param signature string
---@param data string
---@return boolean, string|nil
local function verify_raw(key, signature, data)
	local format, raw_signature = string.unpack('>s4s4', signature)
	if format ~= 'ssh-ed25519' then
		return false
	end

	local digest = openssl.digest.verifyInit(nil, key.pk)
	if not digest then
		return false, 'ed25519.sign: allocation failed'
	end

	return digest:verify(raw_signature, data)
end

local ed25519_impl = {
	name = 'ssh-ed25519',
	serialize_public = serialize_public,
	deserialize_public = deserialize_public,
	deserialize_private = deserialize_private,
	sign_raw = sign_raw,
	verify_raw = verify_raw,
}

return { ed25519 = ed25519_impl }
