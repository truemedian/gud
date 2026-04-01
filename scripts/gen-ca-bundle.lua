package.path = package.path .. ';../deps/?.lua;../deps/?/init.lua'

local fs = require('fs')
local base64 = require('base64')

local bundle = assert(fs.readFile('ca-bundle.crt'))

local certs = {}
for cert in bundle:gmatch('-----BEGIN CERTIFICATE-----\r?\n([0-9A-Za-z+/=\n\r]-)\r?\n-----END CERTIFICATE-----') do
    certs[#certs + 1] = base64.decode(cert)
end

local out = table.concat(certs)
assert(fs.writeFile('ca-bundle.bin', out))