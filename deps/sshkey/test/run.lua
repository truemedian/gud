local fs = require('fs')
local sshkey = require('sshkey')

local function try_key(name)
	local data_private = fs.readFileSync('keys/' .. name)
	local data_public = fs.readFileSync('keys/' .. name .. '.pub')
	local data_signature = fs.readFileSync('keys/' .. name .. '.pub.sig')

	local pk, pk_e = sshkey.decode_public_key(data_public)
	if not pk then
		return false, 'decode public key', pk_e
	end

	local sk, sk_e = sshkey.decode_private_key(data_private, 'password')
	if not sk then
		return false, 'decode private key', sk_e
	end

	local fp_sk, fp_pk = sshkey.fingerprint(sk), sshkey.fingerprint(pk)
	if fp_sk ~= fp_pk then
		return false, 'ensure correct public key derivation', 'fingerprint mismatch'
	end

	local sig, sig_e = sshkey.create_signature(sk, data_public, 'something')
	if not sig then
		return false, 'create signature', sig_e
	end

	local v1, v1_e = sshkey.verify_signature(pk, sig, data_public, 'something')
	if not v1 then
		return false, 'validate created sigature', v1_e
	end

	local v2, v2_e = sshkey.verify_signature(pk, data_signature, data_public, 'something')
	if not v2 then
		return false, 'validate existing signature', v2_e
	end

	return true
end

local failed = 0
for file in fs.scandirSync('keys') do
	if file:sub(-4) == '.key' then
		local success, step, error = try_key(file)
		if not success then
			failed = failed + 1
			print('failure: ' .. step .. ' for ' .. file .. ': ' .. error)
		else
			print('success: ' .. file)
		end
	end
end

if failed > 0 then
	print('failed ' .. failed)
	os.exit(1)
end