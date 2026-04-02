local class = require('class')
local luv = require('luv')

local await = require('await')

local reader = require('stream/tcp/reader')
local writer = require('stream/tcp/writer')

--- @class std.stream.tcp : std.stream
--- @field reader std.stream.tcp.reader
--- @field writer std.stream.tcp.writer
local tcp = class('std.stream.tcp')

local default_hints = { protocol = 6 }

--- Connect to a TCP server.
---
--- @param host string|nil
--- @param service string|nil
--- @param hints? uv.aliases.getaddrinfo_hint
--- @return std.stream.tcp|nil stream
--- @return string|nil err
function tcp.connect(host, service, hints)
	assert(host == nil or type(host) == 'string', 'host must be a string or nil')
	assert(service == nil or type(service) == 'string', 'service must be a string or nil')
	assert(hints == nil or type(hints) == 'table', 'hints must be a table or nil')
	assert(host ~= nil or service ~= nil, 'either host or service must be provided')

	if hints then
		---@diagnostic disable-next-line: assign-type-mismatch
		hints.protocol = hints.protocol or 6
	else
		hints = default_hints
	end

	local awaiter = await()
	local addr_ok, getaddrinfo_err = luv.getaddrinfo(host, service, hints, awaiter:callback())
	if not addr_ok then
		return nil, getaddrinfo_err
	end

	local resolve_err, addresses = awaiter:wait()
	if resolve_err then
		return nil, resolve_err
	end

	local connect_ok, connect_err
	for _, address in ipairs(addresses) do
		local socket, socket_err = luv.new_tcp()
		if not socket then
			return nil, socket_err
		end

		connect_ok, connect_err = socket:connect(address.addr, address.port, awaiter:callback())
		if connect_ok then
			local err5 = awaiter:wait()
			if not err5 then
				return tcp(socket)
			end
		end

		socket:close()
	end

	return nil, connect_err
end

function tcp:init(socket)
	self.reader = reader(socket)
	self.writer = writer(socket)
	self.socket = socket
end

--- Performs an implementation specific control operation on the underlying stream.
---
--- The following commands are supported:
--- - 'getpeername': returns the remote address and port as a table with `address` and `port` fields.
--- @param command string
--- @param ... any
--- @return any
function tcp:ioctl(command, ...) -- luacheck: no unused args
	if command == 'getpeername' then
		return self.socket:getpeername()
	end

	error('unsupported ioctl command: ' .. tostring(command))
end

--- Close the TCP connection, disallowing further reads and writes.
--- @param timeout? integer
function tcp:close(timeout)
	self.writer:flushAll(timeout)

	self.reader.eof = true
	self.writer.closed = true
	self.socket:close()
end

--- Shutdown the TCP connection, disallowing further writes.
--- @param timeout? integer
function tcp:shutdown(timeout)
	self.writer:flushAll(timeout)

	self.writer.closed = true
	self.socket:shutdown()
end

--- @class std.stream.tcp.server : std.stream.server
--- @field socket uv_tcp_t
tcp.server = class('std.stream.tcp.server')

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
--- @param callback fun(client: std.stream.tcp)
function tcp.server:listen(backlog, callback)
	return assert(self.socket:listen(backlog or 256, function(err)
		assert(not err, err)

		local client = assert(luv.new_tcp())
		self.socket:accept(client)

		local stream = tcp(client)
		return callback(stream)
	end))
end

return tcp
