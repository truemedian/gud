local luv = require('luv')

local await = require('await')
local class = require('class')

local tcp = require('net/tcp')
local tls = require('net/tls')

--- @class std.net.pool
--- @field max_idle number
--- @field connections std.net.stream[]
local pool = class('std.net.pool')

local function is_stream_reusable(stream)
	if stream.reader.eof then
		return false
	elseif stream.writer.closed then
		return false
	end

	return true
end

--- @param stream std.net.stream
--- @return string
local function stream_key(stream)
	if class.isinstanceof(stream, tcp) then
		--- @cast stream std.net.tcp
		return 'tcp|' .. stream.address.addr .. '|' .. stream.address.port
	elseif class.isinstanceof(stream, tls) then
		--- @cast stream std.net.tls
		return 'tls|' .. stream_key(stream.underlying)
	end

	error('unsupported stream type: ' .. tostring(stream))
end

function pool:init(max_idle)
	self.max_idle = max_idle or 3
	self.connections = {}
end

function pool:lookup(host, service, hints)
	local awaiter = await()
	local addr_ok, getaddrinfo_err = luv.getaddrinfo(host, service, hints, awaiter:callback())
	if not addr_ok then
		return nil, getaddrinfo_err
	end

	local resolve_err, addresses = awaiter:wait()
	if resolve_err then
		return nil, resolve_err
	end

	return addresses
end

--- @param host string
--- @param service string
--- @param options table|nil
--- @param hints table|nil
--- @return std.net.stream|nil stream
--- @return string|boolean|nil err_or_reused
function pool:acquire(host, service, options, hints)
	local addresses, lookup_err = self:lookup(host, service, hints)
	if not addresses then
		return nil, lookup_err
	end

	local tls_prefix = options and options.tls and 'tcp|' or ''
	for _, address in ipairs(addresses) do
		local key = tls_prefix .. address.protocol .. '|' .. address.addr .. '|' .. address.port

		local i = 1
		while i <= #self.connections do
			local conn = self.connections[i]
			if stream_key(conn) == key then
				table.remove(self.connections, i)
				self.connections[key] = (self.connections[key] or 1) - 1

				if self.connections[key] <= 0 then
					self.connections[key] = nil
				end

				if is_stream_reusable(conn) then
					return conn, true
				end

				conn:close()
			else
				i = i + 1
			end
		end
	end

	local stream, connect_err
	for _, address in ipairs(addresses) do
		if address.protocol == 'tcp' then
			stream, connect_err = tcp.connectTo(address)
			if stream then
				break
			end
		end
	end

	if not stream then
		return nil, connect_err
	end

	if options and options.tls then
		local tls_options = {
			servername = options.servername or host,
			insecure = options.insecure,
			context = options.context,
			cert = options.cert,
			key = options.key,
			ca = options.ca,
		}

		stream, connect_err = tls.handshake(stream, tls_options, options.timeout)
		if not stream then
			return nil, connect_err
		end
	end

	return stream, false
end

function pool:release(conn)
	if not is_stream_reusable(conn) then
		conn:close()
		return
	end

	table.insert(self.connections, conn)

	local key = stream_key(conn)
	local new_idle = (self.connections[key] or 0) + 1
	if new_idle > self.max_idle then
		-- remove the least recently used connection with the same key

		for i, c in ipairs(self.connections) do
			if stream_key(c) == key then
				table.remove(self.connections, i)
				c:close()
				break
			end
		end

		return
	end

	self.connections[key] = new_idle
end

function pool:close()
	for i = 1, #self.connections do
		self.connections[i]:close()
	end

	self.connections = {}
end

return pool
