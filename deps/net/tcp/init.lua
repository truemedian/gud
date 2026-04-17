local class = require('class')
local luv = require('luv')

local await = require('await')
local net = require('net')

local reader = require('net/tcp/reader')
local writer = require('net/tcp/writer')

--- @class std.net.tcp : std.net.stream, std.class<std.net.tcp>
--- @field reader std.reader
--- @field writer std.writer
--- @field socket uv.uv_tcp_t
local tcp = class.new('std.net.tcp')

--- Resolve one or more TCP endpoints.
--- @param host string|nil
--- @param service string|nil
--- @param hints? uv.getaddrinfo.hints
--- @return table[]|nil addresses
--- @return string|nil err
function tcp.resolve(host, service, hints)
	return net.resolve(host, service, hints, 6)
end

--- Connect to a TCP server at the specified address.
---
--- @param address { addr: string, port: integer }
--- @return std.net.tcp|nil stream
--- @return string|nil err
function tcp.connectTo(address)
	local socket, socket_err = luv.new_tcp()
	if not socket then
		return nil, socket_err
	end

	local awaiter = await.new()
	local connect_ok, connect_err = socket:connect(address.addr, address.port, awaiter:callback())
	if connect_ok then
		local connect_fail = awaiter:wait()
		if not connect_fail then
			return tcp.new(socket)
		end
	end

	socket:close()
	return nil, connect_err
end

--- Connect to a TCP server.
---
--- @param host string|nil
--- @param service string|nil
--- @param hints? uv.getaddrinfo.hints
--- @return std.net.tcp|nil stream
--- @return string|nil err
function tcp.connect(host, service, hints)
	local addresses, resolve_err = tcp.resolve(host, service, hints)
	if resolve_err then
		return nil, resolve_err
	elseif not addresses then
		return nil, 'no addresses found'
	end

	local stream, connect_err
	for _, address in ipairs(addresses) do
		stream, connect_err = tcp.connectTo(address)

		if stream then
			return stream, nil
		end
	end

	return nil, connect_err
end

function tcp:init(socket)
	self.reader = reader.new(socket)
	self.writer = writer.new(socket)
	self.socket = socket
end

--- Performs an implementation specific control operation on the underlying stream.
---
--- The following commands are supported:
--- - 'getpeername': returns the remote address and port as a table with `address` and `port` fields.
--- - 'getsockname': returns the local address and port as a table with `address` and `port` fields.
--- @param command string
--- @param ... any
--- @return any
function tcp:ioctl(command, ...) -- luacheck: no unused args
	if command == 'getpeername' then
		return self.socket:getpeername()
	elseif command == 'getsockname' then
		return self.socket:getsockname()
	end

	error('unsupported ioctl command: ' .. tostring(command))
end

--- Close the TCP connection, disallowing further reads and writes.
--- @param timeout? integer
function tcp:close(timeout)
	self.writer:flushAll(timeout)

	self.reader.closed = true
	self.writer.closed = true

	if not self.socket:is_closing() then
		self.socket:close()
	end
end

--- Shutdown the TCP connection, disallowing further writes.
--- @param timeout? integer
function tcp:shutdown(timeout)
	self.writer:flushAll(timeout)

	self.writer.closed = true
	self.socket:shutdown()
end

--- @class std.net.server.tcp : std.net.server, std.class<std.net.server.tcp>
--- @field socket uv.uv_tcp_t
tcp.server = class.new('std.net.server.tcp')

--- @param family? string|integer
function tcp.server:init(family)
	---@diagnostic disable-next-line: param-type-mismatch
	self.socket = assert(luv.new_tcp(family))
end

--- Bind the server to a specific host and port.
--- @param host string
--- @param port integer
function tcp.server:bind(host, port)
	return assert(self.socket:bind(host, port))
end

--- Start listening for incoming connections.
--- @param backlog? integer
--- @param callback fun(client: std.net.tcp)
function tcp.server:listen(backlog, callback)
	return assert(self.socket:listen(backlog or 256, function(err)
		assert(not err, err)

		local client = assert(luv.new_tcp())
		self.socket:accept(client)

		local stream = tcp.new(client)
		return callback(stream)
	end))
end

return tcp
