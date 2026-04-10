local class = require('class')

local parser = require('http/parser')
local protocol = require('http/protocol')

--- @type std.reader
local reader = require('reader')

local lower = string.lower
local tonumber = tonumber

local EMPTY_READER = reader.empty()

local function response_has_body(method, status)
	if method == 'HEAD' then
		return false
	elseif method == 'CONNECT' and status >= 200 and status < 300 then
		return false
	elseif status >= 100 and status < 200 then
		return false
	elseif status == 204 or status == 304 then
		return false
	end

	return true
end

--- @class std.http.client.response
--- @field request std.http.client.request
--- @field stream std.net.stream
--- @field state 'ready'|'started'|'finished'
--- @field version string|nil
--- @field status integer|nil
--- @field reason string|nil
--- @field headers std.http.headers
--- @field keep_alive boolean
--- @field close_after_response boolean
--- @field reader std.reader
local client_response = class('std.http.client.response')

function client_response:init(request)
	self.request = request
	self.stream = request.stream
	self.headers = protocol.headers()
	self.state = 'ready'
	self.version = nil
	self.status = nil
	self.reason = nil
	self.keep_alive = false
	self.close_after_response = false
	self.reader = EMPTY_READER
end

function client_response:reset()
	assert(self.state ~= 'started', 'response body has not been fully read')

	self.state = 'ready'
	self.version = nil
	self.status = nil
	self.reason = nil
	self.keep_alive = false
	self.close_after_response = false
	self.reader = EMPTY_READER

	for name in pairs(self.headers.fields) do
		self.headers.fields[name] = nil
	end
	self.headers.immutable = false
end

--- @param max_head_size? integer
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function client_response:wait(max_head_size, timeout)
	assert(self.state == 'ready', 'response already started')
	assert(self.request.state == 'finished', 'request body has not been fully written')

	local head, err = self.stream.reader:readUntil('\r?\n\r?\n', max_head_size or 8192, timeout, 4)
	if not head then
		return false, err
	end

	local version, status, reason, last = parser.parse_response_line(head)
	if not version then
		return false, 'malformed response line'
	end

	if version ~= '1.0' and version ~= '1.1' then
		return false, 'unsupported version'
	end

	self.version = version
	self.status = status
	self.reason = reason

	self.headers.immutable = false
	local response_headers, parse_err = parser.parse_head(self.headers, head, last)
	if not response_headers then
		return false, parse_err
	end
	self.headers.immutable = true

	local is_chunked = false
	for value in self.headers:list('transfer-encoding') do
		if lower(value) == 'chunked' then
			is_chunked = true
		else
			return false, 'unsupported transfer-encoding'
		end
	end

	local content_length
	for value in self.headers:list('content-length') do
		local n = tonumber(value)
		if not n or n < 0 or n % 1 ~= 0 then
			return false, 'invalid content-length header'
		end

		if content_length and content_length ~= n then
			return false, 'invalid content-length header'
		end

		content_length = n
	end

	local has_close = self.headers:hasToken('connection', 'close')
	local has_keep_alive = self.headers:hasToken('connection', 'keep-alive')

	if version == '1.0' then
		if is_chunked then
			return false, 'chunked transfer-encoding not allowed in HTTP/1.0'
		end

		self.keep_alive = has_keep_alive and not has_close
	else
		self.keep_alive = not has_close and is_chunked
			or content_length ~= nil
			or not response_has_body(self.request.method, self.status)
	end

	if is_chunked then
		if content_length then
			self.close_after_response = true
		end

		self.reader = protocol.chunked_reader(self.stream.reader)
	elseif content_length then
		self.reader = protocol.length_reader(self.stream.reader, content_length)
	elseif response_has_body(self.request.method, status) then
		if self.keep_alive then
			return false, 'missing content-length or transfer-encoding header with keep-alive connection'
		end

		self.reader = self.stream.reader
	else
		self.reader = EMPTY_READER
	end

	self.state = 'started'
	return true
end

--- @param max_size? integer
--- @param timeout? integer
--- @return string|nil body
--- @return string|nil err
function client_response:readBody(max_size, timeout)
	if self.state == 'finished' then
		return ''
	end

	assert(self.state == 'started', 'no response headers available, call :wait() first')

	local body, err = self.reader:readAll(max_size, timeout)
	if not body then
		return nil, err
	end

	self.state = 'finished'
	return body
end

--- @return boolean
function client_response:isReusable()
	if self.state ~= 'finished' then
		return false
	elseif self.headers:hasToken('connection', 'close') then
		return false
	elseif self.close_after_response then
		return false
	elseif not self.reader.closed then
		return false
	end

	return self.keep_alive
end

return client_response
