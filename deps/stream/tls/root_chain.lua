local openssl = require('openssl')

local root_chain = {}
root_chain.store = openssl.x509.store:new()

do
	local content = module:load('ca-bundle.bin') -- luacheck: ignore

	local i = 1
	while i <= #content do
		local ok, _, _, j = openssl.asn1.get_object(content, i)
		assert(ok, 'malformed certificate bundle')

		local cert_data = content:sub(i, j)
		i = j + 1

		local x509 = assert(openssl.x509.read(cert_data))
		assert(x509, 'malformed certificate in bundle')

		root_chain.store:add(x509)
	end

	assert(i == #content + 1, 'trailing data in certificate bundle')
end

function root_chain.add_path(path)
	root_chain.store:load(path)
end

function root_chain.add_string(cert)
	local x509 = openssl.x509.read(cert)

	if x509 then
		root_chain.store:add(x509)
	end
end

return root_chain
