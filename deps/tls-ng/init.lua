--[[

Copyright 2024 truemedian <github.com/truemedian>. All rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

]]

local openssl = require('openssl')

local function check_openssl(obj, class)
	local meta = getmetatable(obj)
	if type(meta) ~= 'table' then return false end

	return meta.__name == class
end

---@return userdata
local function context(options)
	local ctx = openssl.ssl.ctx_new()

	if options.key and options.key then
		assert(check_openssl(options.key, 'openssl.evp_pkey'), 'context: options.key must be an openssl.evp_pkey')
		assert(check_openssl(options.cert, 'openssl.x509'), 'context: options.cert must be an openssl.x509')

		assert(ctx:use(options.key, options.cert))
	end

	if options.ca then
		assert(check_openssl(options.ca, 'openssl.x509.store'), 'context: options.ca must be an openssl.x509.store')

		assert(ctx:cert_store(options.ca))
	end

	if options.insecure then ctx:verify_mode(openssl.ssl.none, nil) end

	ctx:options(bit.bor(openssl.ssl.no_sslv2, openssl.ssl.no_sslv3))

	return ctx
end

---@param ctx userdata
---@param handle userdata
---@param server_mode boolean
---@param hostname string
---@param handshakeComplete fun(socket: table|nil, err: string|nil)
local function wrap(ctx, handle, server_mode, hostname, handshakeComplete)
	local bin, bout = openssl.bio.mem(8192), openssl.bio.mem(8192)
	local ssl = ctx:ssl(bin, bout, server_mode)

	if not server_mode and hostname then ssl:set('hostname', hostname) end

	local function flush(callback)
		local parts = {}
		local i = 1

		while bout:pending() > 0 do
			parts[i] = bout:read()
			i = i + 1
		end

		if i ~= 1 then return handle:write(parts, callback) end
		if callback then return true, callback() end
	end

	local onPlain
	local socket = {}
	local function onCipher(err, data)
		if err or not data then return onPlain(err, data) end
		bin:write(data)
		while true do
			local plain = ssl:read()
			if not plain then break end
			onPlain(nil, plain)
		end
	end

	function socket:read_start(onRead)
		onPlain = onRead
		return handle:read_start(onCipher)
	end

	function socket:write(plain, callback)
		ssl:write(plain)
		return flush(callback)
	end

	function socket:shutdown(...) return handle:shutdown(...) end
	function socket:read_stop(...) return handle:read_stop(...) end
	function socket:is_closing(...) return handle:is_closing(...) end
	function socket:close(...) return handle:close(...) end
	function socket:unref(...) return handle:unref(...) end
	function socket:ref(...) return handle:ref(...) end

	local function handshake()
		if ssl:handshake() then
			local success, result = ssl:getpeerverification()
			handle:read_stop()

			if not success and result then
				for i = 1, #result do
					if not result[i].preverify_ok then
						handle:close()

						return handshakeComplete(nil, 'Error verifying peer: ' .. result[i].error_string)
					end
				end
			end

			local cert = ssl:peer()
			if not cert then
				handle:close()

				return handshakeComplete(nil, 'The peer did not provide a certificate')
			end

			if not cert:check_host(hostname) then
				handle:close()

				return handshakeComplete(nil, "The server hostname does not match the certificate's domain")
			end

			return handshakeComplete(socket)
		end
		return flush()
	end

	local function onCipherHandshake(err, data)
		if err or not data then return handshakeComplete(nil, err or 'Peer aborted the SSL handshake') end
		bin:write(data)
		return handshake()
	end

	handshake()
	handle:read_start(onCipherHandshake)
end

return {
	context = context,
	wrap = wrap,
}
