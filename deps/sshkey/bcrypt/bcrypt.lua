local openssl = require('openssl')

local bit = require('sshkey/bcrypt/bit-compat')
local blowfish = require('sshkey/bcrypt/blowfish')
local buffer = require('sshkey/format/buffer')

local bxor, band, rshift = bit.bxor, bit.band, bit.rshift

---Adapted from <https://github.com/openssh/openssh-portable/blob/master/openbsd-compat/bcrypt_pbkdf.c#L73>
---@param cdata number[]
---@param sha2pass string
---@param sha2salt string
local function bcrypt_hash(cdata, sha2pass, sha2salt)
	cdata[1] = 0x4f787963
	cdata[2] = 0x68726f6d
	cdata[3] = 0x61746963
	cdata[4] = 0x426c6f77
	cdata[5] = 0x66697368
	cdata[6] = 0x53776174
	cdata[7] = 0x44796e61
	cdata[8] = 0x6d697465
	local state = blowfish.init_state()

	-- key expansion
	blowfish.expand(state, sha2salt, sha2pass)
	for i = 1, 64 do
		blowfish.expand0(state, sha2salt)
		blowfish.expand0(state, sha2pass)
	end

	-- encryption
	for i = 1, 64 do
		blowfish.encrypt(state, cdata)
	end
end

local function write_u32le(out, i, n)
	local a = band(n, 0xff)
	local b = band(rshift(n, 8), 0xff)
	local c = band(rshift(n, 16), 0xff)
	local d = band(rshift(n, 24), 0xff)

	out[i] = string.char(a, b, c, d)
end

---Collapse the u32 cdata array as little-endian into a string
---@param cdata number[]
---@return string
local function collapse_little(cdata)
	local out = {}

	write_u32le(out, 1, cdata[1])
	write_u32le(out, 2, cdata[2])
	write_u32le(out, 3, cdata[3])
	write_u32le(out, 4, cdata[4])
	write_u32le(out, 5, cdata[5])
	write_u32le(out, 6, cdata[6])
	write_u32le(out, 7, cdata[7])
	write_u32le(out, 8, cdata[8])

	return table.concat(out)
end

---bcrypt_hash-based PBKDF function based off of PKCS#5 PKKDF2, this is the key derivation function used by OpenSSH
---to derive the decryption key used for encrypting private keys. The implementation deviates from the PKCS#5 standard
---to shuffle the resulting output bytes to prevent an attacker from doing less work to obtain the same key.
---
---Adapted from <https://github.com/openssh/openssh-portable/blob/master/openbsd-compat/bcrypt_pbkdf.c#L114>
local function bcrypt_pbkdf(password, salt, keylen, rounds)
	assert(rounds > 0, 'invalid bcrypt parameter')
	assert(#salt <= 2 ^ 20, 'invalid bcrypt parameter')
	assert(#password > 0, 'invalid bcrypt parameter')
	assert(#salt > 0, 'invalid bcrypt parameter')
	assert(keylen > 0, 'invalid bcrypt parameter')

	local original_keylen = keylen
	local key = {}
	for i = 1, keylen do
		key[i] = '\0'
	end

	local stride = math.ceil(keylen / 32)
	local amt = math.ceil(keylen / stride)
	local sha2pass = openssl.digest.digest('sha512', password, true)

	local count = 1
	while keylen > 0 do
		local countsalt = buffer.write()
		countsalt:write_bytes(salt)
		countsalt:write_u32(count)
		local sha2salt = openssl.digest.digest('sha512', countsalt:encode(), true)

		-- first round, salt is salt
		local tmpout, out = {}, {}
		bcrypt_hash(tmpout, sha2pass, sha2salt)
		for i = 1, 8 do
			out[i] = tmpout[i] -- prime the output with the first round
		end
		for i = 1, rounds - 1 do
			-- subsequent rounds, salt is the previous output
			sha2salt = openssl.digest.digest('sha512', collapse_little(tmpout), true)
			bcrypt_hash(tmpout, sha2pass, sha2salt)
			for j = 1, 8 do
				out[j] = bxor(out[j], tmpout[j])
			end
		end

		amt = math.min(amt, keylen)
		local final_i = amt
		for i = 0, amt - 1 do
			local dest = i * stride + count
			if dest > original_keylen then
				final_i = i
				break
			end

			local offset = math.floor(i / 4)
			local shift = (i % 4) * 8
			local byte = band(rshift(out[offset + 1], shift), 0xff)

			key[dest] = string.char(byte)
		end

		keylen = keylen - final_i
		count = count + 1
	end

	return table.concat(key)
end

return {
	pbkdf = bcrypt_pbkdf,
}
