local class = require('class')
local openssl = require('openssl')

local context = require('stream/tls/context')

local reader = require('stream/tls/reader')
local writer = require('stream/tls/writer')

--- @class std.stream.tls
--- @field reader std.stream.tls.reader
--- @field writer std.stream.tls.writer
--- @field enciphered std.stream
--- @field ctx openssl.ssl.ctx
--- @field ssl openssl.ssl
--- @field bin openssl.bio
--- @field bout openssl.bio
local tls = class('std.stream.tls')

--- Perform a TLS handshake on the given stream, returning a new TLS stream on success.
--- @param stream std.stream
--- @param options table
--- @param timeout? integer
--- @return std.stream.tls|nil stream
--- @return string|nil err
function tls.handshake(stream, options, timeout)
	options = options or {}
	options.server = options.server == nil and (options.key ~= nil) or options.server

	local ctx = options.context or context(options)
	local self = tls(stream, ctx, options)

	if not options.server then
		assert(options.servername, 'servername is required for client connections')

		self.ssl:set('hostname', options.servername)
	end

	while true do
		local success, ssl_err = self.ssl:handshake()
		if success then
			break
		end

		-- write any pending data to the underlying stream
		local _, write_err = self.writer:flush(timeout)
		if write_err then
			return nil, write_err
		end

		local flushed, flush_err = self.enciphered.writer:flushAll(timeout)
		if not flushed then
			return nil, flush_err
		end

		if ssl_err == 'want_read' then
			local data, read_err = self.enciphered.reader:readAtLeast(1, timeout)
			if not data or read_err then
				return nil, read_err
			end

			self.bin:write(data)
		elseif ssl_err ~= 'want_write' then
			return nil, 'unexpected SSL handshake error: ' .. ssl_err
		end
	end

	if not (options.insecure or options.server) then
		local success, result = self.ssl:getpeerverification()
		if not success then
			if type(result) ~= 'table' then
				self:close()
				return nil, result or 'peer certificate verification failed'
			end

			for _, verification in ipairs(result) do
				if not verification.preverify_ok then
					self:close()
					return nil, verification.error_string
				end
			end
		end

		local cert = self.ssl:peer()
		if not cert then
			self:close()
			return nil, 'the peer did not provide a certificate'
		end

		if not cert:check_host(options.servername) then
			self:close()
			return nil, 'the server hostname does not match the certificate'
		end
	end

	return self
end

function tls:init(stream, ctx, options)
	local bin, bout = openssl.bio.mem(8192), openssl.bio.mem(8192)
	local ssl = ctx:ssl(bin, bout, options.server)

	self.reader = reader(stream.reader, bin, ssl)
	self.writer = writer(stream.writer, bout, ssl)
	self.enciphered = stream

	self.ctx = ctx
	self.ssl = ssl
	self.bin = bin
	self.bout = bout
end

function tls:getpeername()
	return self.enciphered:getpeername()
end

--- Close the TLS connection, disallowing further reads and writes.
--- @param timeout? integer
function tls:close(timeout)
	self.writer:flushAll(timeout)

	self.reader.eof = true
	self.writer.closed = true
	self.enciphered:close()
end

--- Shutdown the TLS connection, disallowing further writes.
--- @param timeout? integer
function tls:shutdown(timeout)
	self.writer:flushAll(timeout)

	self.writer.closed = true
	self.enciphered:shutdown()
end

--- @class std.stream.tls.server
tls.server = class('std.stream.tls.server')

function tls.server:init(server, options)
	self.enciphered = server

	self.options = options or {}

	options.server = true
	options.context = options.context or context(options)
end

--- Bind the server to a specific host and port.
--- @param host string
--- @param port integer
function tls.server:bind(host, port)
	return self.enciphered:bind(host, port)
end

--- Start listening for incoming connections.
--- @param backlog? integer
--- @param callback fun(client: std.stream.tls)
function tls.server:listen(backlog, callback)
	return self.enciphered:listen(backlog, function(stream)
		local client, err = tls.handshake(stream, self.options, self.options.handshake_timeout)
		if not client or err then
			stream:close()
			return error(err or 'TLS handshake failed')
		end

		return callback(client)
	end)
end

return tls
