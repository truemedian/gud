local bit = require('bit')
local openssl = require('openssl')

local root_chain = require('net/tls/root_chain')

local disable_bad_tls = bit.bor(openssl.ssl.no_sslv2, openssl.ssl.no_sslv3, openssl.ssl.no_compression)

local function returnOne()
	return 1
end

local bad_x509_error = 'certificate must be an openssl.x509 or string'
local bad_x509_chain_error = 'certificate chain must be a openssl.x509, string, openssl.x509[], string[]'
local bad_x509_store_error = 'certificate store must be a openssl.x509.store, string, openssl.x509[], string[]'
local bad_pkey_error = 'private key must be an openssl.pkey, PEM string, or DER string'

--- @param key string|openssl.pkey
--- @return openssl.pkey
local function parsePKEY(key)
	if type(key) == 'string' then
		return assert(openssl.pkey.read(key, true))
	elseif type(key) == 'userdata' then
		assert(key.class == 'openssl.pkey', bad_pkey_error)

		return key
	end

	error(bad_pkey_error)
end

--- @param cert string|openssl.x509
--- @return openssl.x509[]
local function parseOneX509(cert)
	if type(cert) == 'userdata' then
		assert(cert.class == 'openssl.x509', bad_x509_error)
		return cert
	elseif type(cert) == 'string' then
		return assert(openssl.x509.read(cert))
	end

	error(bad_x509_error)
end

--- @param cert string|string[]|openssl.x509|openssl.x509[]
--- @return openssl.x509[]
local function parseX509(cert)
	if type(cert) == 'table' then
		for i = 1, #cert do
			cert[i] = parseOneX509(cert[i])
		end

		return cert
	elseif type(cert) == 'string' then
		if string.byte(cert) == 0x30 then
			return { assert(openssl.x509.read(cert)) }
		end

		local chain = {}

		for block in cert:gmatch('-----BEGIN CERTIFICATE-----\r?\n[0-9A-Za-z+/=\r\n]+\r?\n-----END CERTIFICATE-----') do
			chain[#chain + 1] = assert(openssl.x509.read(block))
		end

		return chain
	elseif type(cert) == 'userdata' then
		assert(cert.class == 'openssl.x509', bad_x509_chain_error)

		return { cert }
	end

	error(bad_x509_chain_error)
end

--- @param store openssl.x509.store|string|string[]|openssl.x509|openssl.x509[]
--- @return openssl.x509.store
local function parseX509Store(store)
	if type(store) == 'string' or type(store) == 'table' then
		local x509s = parseX509(store)
		local cert_store = openssl.x509.store:new()
		for i = 1, #x509s do
			cert_store:add(x509s[i])
		end
		return cert_store
	elseif type(store) == 'userdata' then
		assert(store.class == 'openssl.x509.store', bad_x509_store_error)
		return store
	end

	error(bad_x509_store_error)
end

--- @return openssl.ssl.ctx
return function(options)
	local ctx = openssl.ssl.ctx_new(options.protocol or 'TLS')

	assert((options.key == nil) == (options.cert == nil), 'both key and cert must be provided together')
	if options.key and options.cert then
		local key = parsePKEY(options.key)
		local cert = parseX509(options.cert)

		local first = table.remove(cert, 1)

		assert(ctx:use(key, first))

		if #cert > 0 then
			local root = table.remove(cert)
			assert(ctx:add(root, cert))
		end
	end

	if options.ca then
		local cert_store = parseX509Store(options.ca)
		ctx:cert_store(cert_store)
	else
		ctx:cert_store(root_chain.store)
	end

	if not (options.insecure or options.server) then
		ctx:verify_mode(openssl.ssl.peer, returnOne)
	end

	ctx:options(disable_bad_tls)

	return ctx
end
