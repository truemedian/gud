local bit = require('bit')
local openssl = require('openssl')

local blowfish = require('sshkey/blowfish')

local BCRYPT_WORDS = 8
local BCRYPT_HASHSIZE = BCRYPT_WORDS * 4

local function xor_string(a, b)
	assert(#a == #b, 'length mismatch')

	local result = {}
	for i = 1, #a do
		result[i] = string.char(bit.bxor(a:byte(i), b:byte(i)))
	end
	return table.concat(result)
end

local function bcrypt_hash(sha2pass, sha2salt)
	local a, b, c, d, e, f, g, h = string.unpack('>I4I4I4I4I4I4I4I4', 'OxychromaticBlowfishSwatDynamite')
	local cdata = { a, b, c, d, e, f, g, h }
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

	-- copy out
	return string.pack(
		'<I4I4I4I4I4I4I4I4',
		cdata[1],
		cdata[2],
		cdata[3],
		cdata[4],
		cdata[5],
		cdata[6],
		cdata[7],
		cdata[8]
	)
end

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

	local stride = math.floor((keylen + BCRYPT_HASHSIZE - 1) / BCRYPT_HASHSIZE)
	local amt = math.floor((keylen + stride - 1) / stride)
	local sha2pass = openssl.digest.digest('sha512', password, true)

	local count = 1
	while keylen > 0 do
		local countsalt = salt .. string.pack('>I4', count)
		local sha2salt = openssl.digest.digest('sha512', countsalt, true)

		-- first round, salt is salt
		local tmpout = bcrypt_hash(sha2pass, sha2salt)
		local out = tmpout
		for i = 1, rounds - 1 do
			-- subsequent rounds, salt is the previous output
			sha2salt = openssl.digest.digest('sha512', tmpout, true)
			tmpout = bcrypt_hash(sha2pass, sha2salt)
			out = xor_string(out, tmpout)
		end

		amt = math.min(amt, keylen)
		local final_i = amt
		for i = 1, amt do
			local dest = (i - 1) * stride + count
			if dest > original_keylen then
				final_i = i - 1
				break
			end

			key[dest] = string.sub(out, i, i)
		end

		keylen = keylen - final_i
		count = count + 1
	end

	return table.concat(key)
end

return {
	pbkdf = bcrypt_pbkdf,
}
