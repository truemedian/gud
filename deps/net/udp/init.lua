local luv = require('luv')

local class = require('class')
local net = require('net')
local timer = require('timer')

--- @class std.net.udp : std.net.socket, std.class<std.net.udp>
--- @field socket uv.uv_udp_t
--- @field timeout std.timer
--- @field waiting thread|nil
local udp = class.new('std.net.udp')

function udp.create()
	local socket, err = luv.new_udp()
	if not socket then
		return nil, err
	end

	return udp.new(socket)
end

--- Resolve one or more UDP endpoints.
--- @param host string|nil
--- @param service string|nil
--- @param hints? uv.getaddrinfo.hints
--- @return table[]|nil addresses
--- @return string|nil err
function udp.resolve(host, service, hints)
	return net.resolve(host, service, hints, 17)
end

function udp:init(socket)
	self.socket = socket
	self.timeout = timer.new()
	self.waiting = nil

	local function finish(data, addr, flags)
		local thread = assert(self.waiting)

		self.waiting = nil
		self.timeout:stop()
		self.socket:recv_stop()

		return coroutine.assertresume(thread, data, addr, flags)
	end

	function self._onread(err, data, addr, flags)
		if err then
			return finish(nil, err)
		end

		if not data then
			return
		end

		return finish(data, addr, flags)
	end

	function self._ontimeout()
		return finish(nil, 'timeout')
	end
end

--- Bind this UDP socket to a local host and port.
--- @param host string
--- @param port integer
--- @param flags? any
--- @return any
--- @return string|nil
function udp:bind(host, port, flags)
	assert(type(host) == 'string', 'host must be a string')
	assert(type(port) == 'number', 'port must be a number')

	return self.socket:bind(host, port, flags)
end

--- Send a UDP datagram.
--- @param data string
--- @param host string
--- @param port integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function udp:send(data, host, port, timeout)
	assert(type(data) == 'string', 'data must be a string')
	assert(type(host) == 'string', 'host must be a string')
	assert(type(port) == 'number', 'port must be a number')
	assert(self.waiting == nil, 'already waiting')

	local thread = coroutine.running()
	local waiting = false
	local success, err

	self.waiting = thread

	local function finish(result, result_err)
		if self.waiting == nil then
			return
		end

		self.waiting = nil
		self.timeout:stop()

		if waiting then
			return coroutine.assertresume(thread, result, result_err)
		end

		success, err = result, result_err
	end

	local req, send_err = self.socket:send(data, host, port, function(err)
		if err then
			return finish(false, err)
		end

		return finish(true)
	end)

	if not req then
		self.waiting = nil
		return false, send_err
	elseif success ~= nil then
		return success, err
	end

	if timeout then
		self.timeout:delayed(timeout, function()
			return finish(false, 'timeout')
		end)
	end

	waiting = true
	return coroutine.yield()
end

--- Receive a single UDP datagram.
--- @param timeout? integer
--- @return string|nil data
--- @return table|string|nil addr_or_err
--- @return integer|nil flags
function udp:receive(timeout)
	if self.waiting then
		return nil, 'already waiting'
	end

	local thread = coroutine.running()

	local ok, recv_err = self.socket:recv_start(self._onread)

	if not ok then
		self.waiting = nil
		return nil, recv_err
	end

	if timeout then
		self.timeout:delayed(timeout, self._ontimeout)
	end

	self.waiting = thread
	return coroutine.yield()
end

--- Performs an implementation specific control operation on the underlying socket.
---
--- The following commands are supported:
--- - 'getsockname': returns local address details.
--- - 'getpeername': returns peer address details for connected UDP sockets.
--- @param command string
--- @param ... any
--- @return any
--- @return string|nil
function udp:ioctl(command, ...) -- luacheck: no unused args
	if command == 'getsockname' then
		return self.socket:getsockname()
	elseif command == 'getpeername' then
		local method = self.socket.getpeername
		if not method then
			return nil, 'getpeername not supported'
		end

		return method(self.socket)
	end

	error('unsupported ioctl command: ' .. tostring(command))
end

--- Close the UDP socket.
function udp:close()
	self.timeout:stop()
	self.socket:recv_stop()

	if not self.socket:is_closing() then
		self.socket:close()
	end
end

return udp
