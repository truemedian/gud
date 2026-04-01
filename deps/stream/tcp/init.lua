local class = require('class')
local luv = require('luv')

local await = require('await')

local reader = require('stream/tcp/reader')
local writer = require('stream/tcp/writer')

--- @class std.stream.tcp
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
end

function tcp:getpeername()
	return self.reader.socket:getpeername()
end

function tcp:close()
	self.reader.eof = true
	self.writer.closed = true
	self.reader.socket:close()
end

function tcp:shutdown()
	self.writer.closed = true
	self.reader.socket:shutdown()
end

return tcp
