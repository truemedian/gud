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

local luv = require('luv')
local tls = require('tls-ng')

local function resume(thread, ...)
	local success, err = coroutine.resume(thread, ...)
	if not success then error(debug.traceback(thread, err)) end
end

local function wait(timeout)
	local thread = coroutine.running()
	local timer, done
	if timeout then
		timer = luv.new_timer()
		timer:start(timeout, 0, function()
			if done then return end

			done = true
			timer:close()
			return resume(thread, nil, 'timeout')
		end)
	end

	return function(...)
		if timer then timer:close() end
		if done then return end
		done = true
		return resume(thread, ...)
	end
end

local function yield()
	local thread = coroutine.running()

	return function(...) return resume(thread, ...) end
end

--- Wrap a libuv socket in a coroutine-friendly interface
---
--- socket.write **MUST** return any uv_req_t object it creates
--- socket.write **MUST** return true if it succeeds synchronously
--- socket.write **MUST** return any other value if it fails
---@param socket userdata
---@return fun(): string|nil, string|nil
---@return fun(data: string|nil): boolean, string|nil
---@return userdata
local function wrap(socket)
	local queue = {}
	local index = 1
	local thread
	local read_err

	local function onRead(err, chunk)
		if thread then
			local thrd = thread
			thread = nil
			return resume(thrd, chunk, err)
		end

		read_err = err
		queue[index] = chunk
		index = index + 1

		socket:read_stop()
	end

	local function read()
		assert(not thread, 'another thread is already reading from this socket')

		if index > 1 then
			local chunk = table.remove(queue, 1)
			index = index - 1
			return chunk, read_err
		end

		thread = coroutine.running()
		socket:read_start(onRead)

		return coroutine.yield()
	end

	local function write(chunk)
		if chunk == nil then
			local success, err = socket:shutdown(yield())
			if not success then return false, err end

			err = coroutine.yield()
			return not err, err
		end

		local success, err = socket:write(chunk, yield())
		if not success then return false, err end

		if success == true then return true end

		err = coroutine.yield()
		return not err, err
	end

	return read, write, socket
end

local function normalize(options, server)
	if options.host or options.port then
		assert(type(options.host) == 'string' and options.host, 'options.host is required and must be a string')
		assert(type(options.port) == 'number' and options.port, 'options.port is required and must be a number')
	elseif options.path then
		assert(type(options.path) == 'string' and options.path, 'options.path is required and must be a string')
	else
		error('must set either options.host and options.port or options.path')
	end

	if options.tls then
		if options.tls == true then options.tls = {} end

		if server then
			options.tls.server = true
			assert(options.tls.cert, 'TLS server requires options.tls.cert')
			assert(options.tls.key, 'TLS server requires options.tls.key')
		else
			options.tls.server = false
			options.tls.servername = options.tls.servername or options.host
		end

		options.tls.timeout = options.tls.timeout or options.timeout
	end

	return options
end

--- Create a new TCP or pipe client
---@param options table
---@return nil|fun(): string|nil, string|nil
---@return string|fun(data: string|nil): boolean, string|nil
---@return nil|userdata
local function connect(options)
	options = normalize(options, false)

	local client
	if options.host or options.port then
		local success, err = luv.getaddrinfo(options.host, options.port, {
			family = options.family,
			socktype = options.socktype,
			protocol = options.protocol,
		}, wait(options.timeout))
		if not success then return nil, err end

		local res
		err, res = coroutine.yield()
		if not res then return nil, err end

		client = assert(luv.new_tcp())
		assert(client:connect(res[1].addr, res[1].port, wait(options.timeout)))

		err = coroutine.yield()
		if err then return nil, err end
	elseif options.path then
		client = assert(luv.new_pipe(false))
		assert(client:connect(options.path, wait(options.timeout)))

		local err = coroutine.yield()
		if err then return nil, err end
	end

	local socket = client
	if options.tls then
		local ctx = tls.context(options.tls)

		tls.wrap(ctx, client, false, options.tls.servername, wait(options.tls.timeout))

		socket, err = coroutine.yield()
		if not socket then
			client:close()
			return nil, err
		end
	end

	return wrap(socket)
end

--- Create a new TCP or pipe server
---@param options table
---@param handleConnection fun(read: fun(): string|nil, string|nil, write: fun(data: string|nil): boolean, string|nil, socket: userdata)
---@return userdata
local function listen(options, handleConnection)
	options = normalize(options, true)

	local server
	local is_tcp = false

	if options.host or options.port then
		server = assert(luv.new_tcp())
		assert(server:bind(options.host, options.port))

		is_tcp = true
	elseif options.path then
		server = assert(luv.new_pipe(false))
		assert(server:bind(options.path))

		is_tcp = false
	end

	local backlog = options.backlog or 256
	assert(server:listen(backlog, function(err)
		local thread = coroutine.create(function()
			assert(not err, err)

			local client = is_tcp and assert(luv.new_tcp()) or assert(luv.new_pipe(false))
			assert(client:accept(server))

			local socket = client
			if options.tls then
				local ctx = tls.context(options.tls)

				assert(tls.wrap(ctx, client, true, options.tls.servername, wait(options.tls.timeout)))

				socket, err = coroutine.yield()
				if not socket then return client:close() end
			end

			return handleConnection(wrap(socket))
		end)

		local success, thread_err = coroutine.resume(thread)
		if not success then io.stderr:write(debug.traceback(thread, thread_err)) end
	end))

	return server
end

return {
	connect = connect,
	listen = listen,
}
