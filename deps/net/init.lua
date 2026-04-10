local luv = require('luv')

local utility = require('utility')

local net = {}

net.tcp = require('net/tcp')
net.udp = require('net/udp')
net.tls = require('net/tls')
net.pool = require('net/pool')
net.services = require('net/services')

--- Resolve one or more endpoints.
--- @param host string|nil
--- @param service string|nil
--- @param hints? uv.getaddrinfo.hints
--- @param protocol? integer
--- @return table[]|nil addresses
--- @return string|nil err
function net.resolve(host, service, hints, protocol)
	assert(host == nil or type(host) == 'string', 'host must be a string or nil')
	assert(service == nil or type(service) == 'string', 'service must be a string or nil')
	assert(hints == nil or type(hints) == 'table', 'hints must be a table or nil')
	assert(protocol == nil or type(protocol) == 'number', 'protocol must be a number or nil')
	assert(host ~= nil or service ~= nil, 'either host or service must be provided')

	if hints then
		hints.protocol = hints.protocol or protocol
	elseif protocol then
		hints = { protocol = protocol }
	end

	local thread = coroutine.running()
	local waiting = false
	local resolve_err, addresses

	local ok, getaddrinfo_err = luv.getaddrinfo(host, service, hints, function(err, addrs)
		if waiting then
			return utility.assertresume(thread, err, addrs)
		end

		resolve_err, addresses = err, addrs
	end)
	if not ok then
		return nil, getaddrinfo_err
	end

	if resolve_err ~= nil or addresses ~= nil then
		if resolve_err then
			return nil, resolve_err
		end

		return addresses
	end

	waiting = true
	resolve_err, addresses = coroutine.yield()
	if resolve_err then
		return nil, resolve_err
	end

	return addresses
end

return net
