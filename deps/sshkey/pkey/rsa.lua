local openssl = require('openssl')

local buffer = require('sshkey/format/buffer')

local function complete_crt_parameters(d, p, q)
	local dmp1 = d % (p - 1)
	local dmq1 = d % (q - 1)
	return dmp1, dmq1
end

---@param key sshkey.key.rsa
---@return string
local function serialize_public(key)
	local info = assert(key.pk:parse().rsa):parse()
	local e = info.e:totext()
	local n = info.n:totext()

	local encoder = buffer.write()
	encoder:write_string(key.kt)
	encoder:write_string(e)
	encoder:write_string(n)
	return encoder:encode()
end

---@param key sshkey.key.rsa
---@param buf sshkey.read_buffer
---@return boolean|nil, string|nil
local function deserialize_public(key, buf)
	local e = buf:read_string()
	local n = buf:read_string()

	n = openssl.bn.text(n)
	e = openssl.bn.text(e)

	local pk, err = openssl.pkey.new({ alg = 'rsa', n = n, e = e })
	if not pk then
		return nil, 'rsa.deserialize_public: ' .. err
	end

	key.pk = pk
	return true
end

---@param key sshkey.key.rsa
---@param buf sshkey.read_buffer
---@return boolean|nil, string|nil
local function deserialize_private(key, buf)
	local n = buf:read_string()
	local e = buf:read_string()
	local d = buf:read_string()
	local iqmp = buf:read_string()
	local p = buf:read_string()
	local q = buf:read_string()
	if #n == 0 or #e == 0 or #d == 0 or #iqmp == 0 or #p == 0 or #q == 0 then
		return nil, 'rsa.deserialize_private: invalid parameters'
	end

	n = openssl.bn.text(n)
	e = openssl.bn.text(e)
	d = openssl.bn.text(d)
	iqmp = openssl.bn.text(iqmp)
	p = openssl.bn.text(p)
	q = openssl.bn.text(q)
	local dmp1, dmq1 = complete_crt_parameters(d, p, q)

	local sk, err = openssl.pkey.new({
		alg = 'rsa',
		n = n,
		e = e,
		d = d,
		p = p,
		q = q,
		iqmp = iqmp,
		dmp1 = dmp1,
		dmq1 = dmq1,
	})
	if not sk then
		return nil, 'rsa.deserialize_private: ' .. err
	end

	key.sk = sk
	return true
end

---@param key sshkey.key.rsa
---@param data string
---@return string|nil, string|nil
local function sign_raw(key, data)
	local digest = openssl.digest.signInit('sha512', key.sk)
	if not digest then
		return nil, 'rsa.sign: allocation failed'
	end

	local signed = digest:sign(data)
	if not signed then
		return nil, 'rsa.sign: signing failed'
	end

	local encoder = buffer.write()
	encoder:write_string('rsa-sha2-512')
	encoder:write_string(signed)
	return encoder:encode()
end

---@param key sshkey.key.rsa
---@param signature string
---@param data string
---@return boolean, string|nil
local function verify_raw(key, signature, data)
	local signature_decoder = buffer.read(signature)
	local format = signature_decoder:read_string()

	local hash_algo
	if format == 'rsa-sha2-512' then
		hash_algo = 'sha512'
	elseif format == 'rsa-sha2-256' then
		hash_algo = 'sha256'
	else
		return false, 'rsa.verify: invalid signature format'
	end

	local digest = openssl.digest.verifyInit(hash_algo, key.pk)
	if not digest then
		return false, 'rsa.verify: allocation failed'
	end

	local verified, err = digest:verify(signature_decoder:read_string(), data)
	if not verified then
		if err then
			return false, 'rsa.verify: ' .. err
		else
			return false, 'rsa.verify: verification failed for unknown reason'
		end
	end

	return true
end

local rsa_impl = {
	name = 'ssh-rsa',
	serialize_public = serialize_public,
	deserialize_public = deserialize_public,
	deserialize_private = deserialize_private,
	sign_raw = sign_raw,
	verify_raw = verify_raw,
}

return { rsa = rsa_impl }
