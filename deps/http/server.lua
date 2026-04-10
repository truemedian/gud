local server_request = require('http/server/request')
local server_response = require('http/server/response')

local utility = require('utility')

local tcp = require('net/tcp')
local tls = require('net/tls')

--- @class std.http.server
local server = {}

local function send_error_response(response, status, reason, timeout, errf)
	response.headers:set('connection', 'close')
	response.headers:set('content-length', '0')

	local responded, respond_err = response:respond(status, reason, timeout)
	if not responded then
		return errf(respond_err)
	end

	local finished, finish_err = response:finish(timeout)
	if not finished then
		return errf(finish_err)
	end
end

local function handle_connection(stream, callback, options, errf)
	local timeout = options.timeout
	local max_head_size = options.max_head_size or 8192

	local request = server_request(stream)
	local response = server_response(request)

	while true do
		local waited, err = request:wait(max_head_size, timeout)
		if not waited then
			if err == 'end of stream' then
				stream:close()
				return
			end

			if err == 'unsupported expectation' then
				send_error_response(response, 417, 'Expectation Failed', timeout, errf)
			elseif err == 'unsupported version' then
				send_error_response(response, 505, 'HTTP Version Not Supported', timeout, errf)
			elseif err == 'unsupported transfer-encoding' then
				send_error_response(response, 501, 'Not Implemented', timeout, errf)
			else
				send_error_response(response, 400, 'Bad Request', timeout, errf)
			end

			stream:close()
			return errf(err)
		end

		local ok, callback_err = pcall(callback, request, response)
		if not ok then
			stream:close()
			return errf(callback_err)
		end

		if response.state == 'ready' then
			response.headers:set('connection', 'close')
			response.headers:set('content-length', '0')

			local responded, respond_err = response:respond(500, 'Internal Server Error', timeout)
			if not responded then
				stream:close()
				return errf(respond_err)
			end

			local finished, finish_err = response:finish(timeout)
			if not finished then
				stream:close()
				return errf(finish_err)
			end
		elseif response.state == 'started' then
			local finished, finish_err = response:finish(timeout)
			if not finished then
				stream:close()
				return errf(finish_err)
			end
		end

		if not response:isReusable() then
			stream:close()
			return
		end

		request:reset()
		response:reset()
	end
end

--- @param net_server std.net.server
--- @param callback fun(request: std.http.server.request, response: std.http.server.response)
--- @param options? { backlog?: integer, timeout?: integer, max_head_size?: integer }
--- @param errf? fun(err: string)
function server.listen(net_server, callback, options, errf)
	options = options or {}
	errf = errf or error

	net_server:listen(options.backlog or 256, function(stream)
		local thread = coroutine.create(handle_connection)

		local ok, err = coroutine.resume(thread, stream, callback, options, errf)
		if not ok then
			stream:close()

			local traceback = debug.traceback(thread, err)
			return error(traceback)
		end
	end)
end

return server
