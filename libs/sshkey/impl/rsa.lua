local openssl = require('openssl')

local function complete_crt_parameters(d, p, q)
	local dmp1 = d % (p - 1)
	local dmq1 = d % (q - 1)
	return dmp1, dmq1
end

---@param key sshkey.key
---@return string
local function serialize_public(key)
	local info = assert(key.pk:parse().rsa):parse()
	local e = info.e:totext()
	local n = info.n:totext()

	return string.pack('>s4s4s4', 'ssh-rsa', e, '\x00' .. n)
end

---@param key sshkey.key
---@param buf sshkey.buf
---@return boolean|nil, string|nil
local function deserialize_public(key, buf)
	local e = buf:read_string()
	local n = buf:read_string()

	n = openssl.bn.text(n)
	e = openssl.bn.text(e)

	local pk, err = openssl.pkey.new({ alg = 'rsa', n = n, e = e })
	if not pk then
		return nil, 'parse public key failed: ' .. err
	end

	key.pk = pk
	return true
end

---@param key sshkey.key
---@param buf sshkey.buf
---@return boolean|nil, string|nil
local function deserialize_private(key, buf)
	local n = buf:read_string()
	local e = buf:read_string()
	local d = buf:read_string()
	local iqmp = buf:read_string()
	local p = buf:read_string()
	local q = buf:read_string()
	if #n == 0 or #e == 0 or #d == 0 or #iqmp == 0 or #p == 0 or #q == 0 then
		return nil, 'invalid rsa private key'
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
		return nil, 'parse private key failed: ' .. err
	end

	key.sk = sk
	return true
end

---@param key sshkey.key
---@param data string
---@param algo string
---@return string|nil, string|nil
local function sign_raw(key, data, algo)
	local digest = openssl.digest.signInit(algo, key.sk)
	local signed = digest:sign(data)

	if algo == 'sha256' then
		algo = '256'
	elseif algo == 'sha512' then
		algo = '512'
	else
		return nil, 'unsupported algorithm'
	end

	return string.pack('>s4s4', 'rsa-sha2-' .. algo, signed)
end

---@param key sshkey.key
---@param signature string
---@param data string
---@param algo string
---@return boolean, string|nil
local function verify_raw(key, signature, data, algo)
	local digest = openssl.digest.verifyInit(algo, key.pk)
	local format, raw_signature = string.unpack('>s4s4', signature)

	if algo == 'sha256' then
		algo = '256'
	elseif algo == 'sha512' then
		algo = '512'
	else
		return false
	end

	if format ~= 'rsa-sha2-' .. algo then
		return false
	end

	return digest:verify(raw_signature, data)
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
