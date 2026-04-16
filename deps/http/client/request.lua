local class = require('class')

local protocol = require('http/protocol')

local concat = table.concat
local format = string.format
local lower = string.lower
local tonumber = tonumber
local upper = string.upper

local function append_header(lines, name, value)
	lines[#lines + 1] = name
	lines[#lines + 1] = ': '
	lines[#lines + 1] = value
	lines[#lines + 1] = '\r\n'
end

--- @class std.http.client.request
--- @field stream std.net.stream
--- @field state 'ready'|'started'|'finished'
--- @field method string|nil
--- @field target string|nil
--- @field version string|nil
--- @field headers std.http.headers
--- @field writer std.writer|std.http.writer.chunked|std.http.writer.length|nil
local client_request = class('std.http.client.request')

function client_request:init(stream)
	self.stream = stream
	self.headers = protocol.headers()
	self.state = 'ready'
	self.method = nil
	self.target = nil
	self.version = nil
	self.writer = nil
end

function client_request:reset()
	assert(self.state ~= 'started', 'request body has not been fully written')

	self.state = 'ready'
	self.method = nil
	self.target = nil
	self.version = nil
	self.writer = nil

	for name in pairs(self.headers.fields) do
		self.headers.fields[name] = nil
	end
	self.headers.immutable = false
end

--- @param method string
--- @param target string
--- @param version? string
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function client_request:start(method, target, version, timeout)
	assert(self.state == 'ready', 'request already started')
	assert(type(method) == 'string' and #method > 0, 'method must be a non-empty string')
	assert(type(target) == 'string' and #target > 0, 'target must be a non-empty string')

	version = version or '1.1'
	if version ~= '1.0' and version ~= '1.1' then
		return false, 'unsupported version'
	end

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

	if is_chunked and content_length then
		return false, 'content-length and transfer-encoding are mutually-exclusive'
	end

	self.state = 'started'
	self.method = upper(method)
	self.target = target
	self.version = version
	self.headers.immutable = true

	local lines = { format('%s %s HTTP/%s\r\n', method, target, version) }
	for name, value in self.headers:all() do
		append_header(lines, name, value)
	end
	lines[#lines + 1] = '\r\n'

	local ok, err = self.stream.writer:write(concat(lines), timeout)
	if not ok then
		return false, err
	end

	if is_chunked then
		self.writer = protocol.chunked_writer(self.stream.writer)
	elseif content_length then
		self.writer = protocol.length_writer(self.stream.writer, content_length)
	else
		self.writer = self.stream.writer
	end

	return self.stream.writer:flushAll(timeout)
end

--- @param data string
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function client_request:write(data, timeout)
	assert(self.state == 'started', 'no pending request, call :request() first')

	if #data == 0 then
		return true
	end

	return self.writer:write(data, timeout)
end

--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function client_request:finish(timeout)
	if self.state == 'finished' then
		return true
	end

	assert(self.state == 'started', 'no pending request, call :request() first')

	local ok, err
	if not self.writer then
		return false, 'request writer is not initialized'
	elseif self.writer.finish then
		ok, err = self.writer:finish(timeout)
	else
		ok, err = self.writer:flushAllRecursive(timeout)
	end

	if not ok then
		return false, err
	end

	self.state = 'finished'
	return true
end

return client_request
