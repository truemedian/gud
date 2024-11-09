local openssl = require('openssl')
local asn1 = openssl.asn1

local buffer = require('sshkey/format/buffer')

local function keytype_to_curve(kt)
	if kt == 'ecdsa-sha2-nistp256' then
		return 'nistp256'
	elseif kt == 'ecdsa-sha2-nistp384' then
		return 'nistp384'
	elseif kt == 'ecdsa-sha2-nistp521' then
		return 'nistp521'
	else
		error('unsupported algorithm')
	end
end

local function keytype_to_nid(kt)
	if kt == 'ecdsa-sha2-nistp256' then
		return 'prime256v1'
	elseif kt == 'ecdsa-sha2-nistp384' then
		return 'secp384r1'
	elseif kt == 'ecdsa-sha2-nistp521' then
		return 'secp521r1'
	else
		error('unsupported algorithm')
	end
end

local function keytype_to_hashalgo(kt)
	if kt == 'ecdsa-sha2-nistp256' then
		return 'sha256'
	elseif kt == 'ecdsa-sha2-nistp384' then
		return 'sha384'
	elseif kt == 'ecdsa-sha2-nistp521' then
		return 'sha512'
	else
		error('unsupported algorithm')
	end
end

---@param key sshkey.key.ecdsa
---@return string
local function serialize_public(key)
	local encoder = buffer.write()
	encoder:write_string(key.kt)
	encoder:write_string(keytype_to_curve(key.kt))
	encoder:write_string(key.pk_pt)
	return encoder:encode()
end

---@param key sshkey.key.ecdsa
---@param buf sshkey.read_buffer
---@return boolean|nil, string|nil
local function deserialize_public(key, buf)
	local curve = buf:read_string()
	if curve ~= keytype_to_curve(key.kt) then
		return nil, 'ecdsa.deserialize_public: curve mismatch'
	end

	local ec_name = keytype_to_nid(key.kt)
	if not ec_name then
		return nil, 'ecdsa.deserialize_public: unsupported curve'
	end

	local ec_group = openssl.ec.group(ec_name)

	key.pk_pt = buf:read_string()
	local point = ec_group:oct2point(key.pk_pt)

	local x, y = ec_group:affine_coordinates(point)
	local pk, err = openssl.pkey.new({ alg = 'ec', ec_name = ec_name, x = x, y = y })
	if not pk then
		return nil, 'ecdsa.deserialize_public: ' .. err
	end

	key.pk = pk
	return true
end

---@param key sshkey.key.ecdsa
---@param buf sshkey.read_buffer
---@return boolean|nil, string|nil
local function deserialize_private(key, buf)
	local pk_success, pk_err = deserialize_public(key, buf)
	if not pk_success then
		return nil, pk_err
	end

	local d = openssl.bn.text(buf:read_string())

	local ec_name = keytype_to_nid(key.kt)
	local ec_group = openssl.ec.group(ec_name)
	local point = ec_group:oct2point(key.pk_pt)

	local x, y = ec_group:affine_coordinates(point)

	local sk, err = openssl.pkey.new({ alg = 'ec', ec_name = ec_name, d = d, x = x, y = y })
	if not sk then
		return nil, 'ecdsa.deserialize_private: ' .. err
	end

	key.sk = sk
	return true
end

---@param key sshkey.key.ecdsa
---@param data string
---@return string|nil, string|nil
local function sign_raw(key, data)
	local algo = keytype_to_hashalgo(key.kt)

	local digest = openssl.digest.signInit(algo, key.sk)
	if not digest then
		return nil, 'ecdsa.sign: allocation failed'
	end

	local signed = digest:sign(data)
	local container_tag, _, container_start, container_stop = asn1.get_object(signed)
	if container_tag ~= asn1.SEQUENCE then
		return nil, 'ecdsa.sign: malformed signature'
	end

	local r_tag, _, r_start, r_stop = asn1.get_object(signed, container_start)
	local s_tag, _, s_start, s_stop = asn1.get_object(signed, r_stop + 1)
	if r_tag ~= asn1.INTEGER or s_tag ~= asn1.INTEGER or s_stop ~= container_stop then
		return nil, 'ecdsa.sign: malformed signature'
	end

	local r = signed:sub(r_start, r_stop)
	local s = signed:sub(s_start, s_stop)

	local packed_encoder = buffer.write()
	packed_encoder:write_string(r)
	packed_encoder:write_string(s)
	local encoder = buffer.write()
	encoder:write_string(key.kt)
	encoder:write_string(packed_encoder:encode())
	return encoder:encode()
end

---@param key sshkey.key.ecdsa
---@param signature string
---@param data string
---@return boolean, string|nil
local function verify_raw(key, signature, data)
	local packed_decoder = buffer.read(signature)
	local format = packed_decoder:read_string()

	if format ~= key.kt then
		return false, 'ecdsa.verify: format mismatch'
	end

	local algo = keytype_to_hashalgo(key.kt)
	local digest = openssl.digest.verifyInit(algo, key.pk)
	if not digest then
		return false, 'ecdsa.verify: allocation failed'
	end

	local signature_decoder = buffer.read(packed_decoder:read_string())
	local r = openssl.bn.text(signature_decoder:read_string())
	local s = openssl.bn.text(signature_decoder:read_string())

	r = asn1.new_integer(r)
	s = asn1.new_integer(s)

	local real_signature = asn1.put_object(asn1.SEQUENCE, 0, r:i2d() .. s:i2d(), true)
	local verified, err = digest:verify(real_signature, data)
	if not verified then
		if err then
			return false, 'ecdsa.verify: ' .. err
		else
			return false, 'ecdsa.verify: verification failed for unknown reason'
		end
	end

	return true
end

local ecdsa_nistp256 = {
	name = 'ecdsa-sha2-nistp256',
	serialize_public = serialize_public,
	deserialize_public = deserialize_public,
	deserialize_private = deserialize_private,
	sign_raw = sign_raw,
	verify_raw = verify_raw,
}

local ecdsa_nistp384 = {
	name = 'ecdsa-sha2-nistp384',
	serialize_public = serialize_public,
	deserialize_public = deserialize_public,
	deserialize_private = deserialize_private,
	sign_raw = sign_raw,
	verify_raw = verify_raw,
}

local ecdsa_nistp521 = {
	name = 'ecdsa-sha2-nistp521',
	serialize_public = serialize_public,
	deserialize_public = deserialize_public,
	deserialize_private = deserialize_private,
	sign_raw = sign_raw,
	verify_raw = verify_raw,
}

return { ecdsa_nistp256 = ecdsa_nistp256, ecdsa_nistp384 = ecdsa_nistp384, ecdsa_nistp521 = ecdsa_nistp521 }
