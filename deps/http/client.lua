local class = require('class')
local protocol = require('http/protocol')

local request = require('http/client/request')
local response = require('http/client/response')

local pool = require('net/pool')
local services = require('net/services')

local uri = require('uri')

local tostring = tostring
local upper = string.upper

local redirect_status = {
	[301] = true,
	[302] = true,
	[303] = true,
	[307] = true,
	[308] = true,
}

--- @class std.http.client
local client = {}

local function parse_absolute_url(url)
	local parsed = uri.decode(url)
	if not parsed then
		return nil, 'invalid url'
	elseif parsed.scheme ~= 'http' and parsed.scheme ~= 'https' then
		return nil, 'url scheme must be http or https'
	elseif not parsed.hostname or #parsed.hostname == 0 then
		return nil, 'url must include a hostname'
	elseif parsed.userinfo then
		return nil, 'url must not include userinfo'
	end

	return parsed
end

local function request_target(parsed)
	local path = parsed.path
	if path == '' then
		path = '/'
	end

	if parsed.query then
		return path .. '?' .. parsed.query
	end

	return path
end

local function host_header(parsed)
	local host = parsed.hostname
	if host:find(':', 1, true) and host:sub(1, 1) ~= '[' then
		host = '[' .. host .. ']'
	end

	local default_port = services[parsed.scheme]
	if parsed.port and parsed.port ~= default_port then
		return host .. ':' .. parsed.port
	end

	return host
end

local function next_redirect_url(current, location)
	local parsed_location = uri.decode(location)
	if not parsed_location then
		return nil, 'invalid redirect location'
	end

	parsed_location.fragment = parsed_location.fragment or current.fragment
	local resolved = uri.resolve(current, parsed_location)
	if not resolved.scheme or not resolved.hostname then
		return nil, 'redirect location must resolve to an absolute URL'
	end

	return uri.encode(resolved)
end

local function send_once(method, url, headers, payload, options)
	local parsed, parse_err = parse_absolute_url(url)
	if not parsed then
		return nil, parse_err
	end

	local service = parsed.port or services[parsed.scheme]
	if not service then
		return nil, 'missing service port for scheme'
	end

	local stream, acquire_err = (options.pool or pool.global):acquire(parsed.hostname, tostring(service), {
		tls = parsed.scheme == 'https',
		servername = parsed.hostname,
		insecure = options.insecure,
		context = options.context,
		cert = options.cert,
		key = options.key,
		ca = options.ca,
		timeout = options.timeout,
	})
	if not stream then
		if type(acquire_err) == 'string' then
			return nil, acquire_err
		end

		return nil, 'failed to acquire connection'
	end

	local req, res = client.request(stream)
	for name, value in headers:all() do
		req.headers:add(name, value)
	end

	if not headers:has('host') then
		req.headers:set('host', host_header(parsed))
	end

	if payload ~= nil and not headers:has('content-length') and not headers:has('transfer-encoding') then
		req.headers:set('content-length', tostring(#payload))
	end

	local ok, err = req:start(method, request_target(parsed), '1.1', options.timeout)
	if not ok then
		stream:close(options.timeout)
		return nil, err
	end

	if payload and #payload > 0 then
		ok, err = req:write(payload, options.timeout)
		if not ok then
			stream:close(options.timeout)
			return nil, err
		end
	end

	ok, err = req:finish(options.timeout)
	if not ok then
		stream:close(options.timeout)
		return nil, err
	end

	ok, err = res:wait(options.max_head_size, options.timeout)
	if not ok then
		stream:close(options.timeout)
		return nil, err
	end

	local body
	body, err = res:readBody(options.max_body_size, options.timeout)
	if not body then
		stream:close(options.timeout)
		return nil, err
	end

	local result = {
		url = url,
		method = method,
		version = res.version,
		status = res.status,
		reason = res.reason,
		headers = res.headers,
		body = body,
	}

	if res:isReusable() and not stream.reader.closed and not stream.writer.closed then
		(options.pool or pool.global):release(stream)
	else
		stream:close(options.timeout)
	end

	return result
end

--- @param stream std.net.stream
--- @return std.http.client.request req
--- @return std.http.client.response res
function client.request(stream)
	local req = request(stream)
	local res = response(stream, req)
	return req, res
end

--- @param method string
--- @param url string
--- @param headers? std.http.headers
--- @param payload? string
--- @param options? { max_redirects?: integer, max_head_size?: integer, max_body_size?: integer, timeout?: integer, pool?: std.net.pool, insecure?: boolean, context?: any, cert?: string, key?: string, ca?: string[]|string }
--- @return table|nil response
--- @return string|nil err
function client.fetch(method, url, headers, payload, options)
	if type(method) ~= 'string' or #method == 0 then
		return nil, 'method must be a non-empty string'
	elseif type(url) ~= 'string' or #url == 0 then
		return nil, 'url must be a non-empty string'
	elseif headers ~= nil and not class.isinstanceof(headers, protocol.headers) then
		return nil, 'headers must be std.http.headers or nil'
	elseif payload ~= nil and type(payload) ~= 'string' then
		return nil, 'payload must be a string or nil'
	elseif options ~= nil and type(options) ~= 'table' then
		return nil, 'options must be a table or nil'
	end

	options = options or {}
	method = upper(method)
	headers = headers or protocol.headers()

	local max_redirects = options.max_redirects or 10
	for redirects = 0, max_redirects do
		local result, err = send_once(method, url, headers, payload, options)
		if not result then
			return nil, err
		elseif not redirect_status[result.status] then
			result.redirects = redirects
			return result
		end

		local location = result.headers:get('location')
		if not location then
			result.redirects = redirects
			return result
		elseif redirects == max_redirects then
			return nil, 'too many redirects'
		end

		local current_parsed, parse_err = parse_absolute_url(url)
		if not current_parsed then
			return nil, parse_err
		end

		local next_url, redirect_err = next_redirect_url(current_parsed, location)
		if not next_url then
			return nil, redirect_err
		end

		url = next_url
		if result.status == 303 or ((result.status == 301 or result.status == 302) and method == 'POST') then
			method = 'GET'
			payload = nil

			headers = headers:clone()
			headers:remove('content-length')
			headers:remove('transfer-encoding')
			headers:remove('content-type')
		end
	end

	return nil, 'too many redirects'
end

return client
