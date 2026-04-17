local class = require('class')

local parser = require('http/parser')
local protocol = require('http/protocol')

--- @type std.reader
local reader = require('reader')

local lower = string.lower
local tonumber = tonumber
local find = string.find

local EMPTY_READER = reader.empty()

--- @class std.http.server.request: std.class<std.http.server.request>
--- @field stream std.net.stream
--- @field method string
--- @field target string
--- @field version string
--- @field headers std.http.headers
--- @field expect_continue boolean
--- @field keep_alive boolean
--- @field close_after_response boolean
--- @field reader std.reader
local server_request = class.new('std.http.server.request')

function server_request:init(stream)
	self.stream = stream
	self.headers = protocol.headers.new()

	self:reset()
end

function server_request:reset()
	self.method = nil
	self.target = nil
	self.version = nil
	self.expect_continue = false
	self.keep_alive = false
	self.close_after_response = false
	self.reader = EMPTY_READER

	table.clear(self.headers.fields)
end

--- @param max_head_size? integer
--- @param timeout? integer
--- @return std.http.server.request|nil request
--- @return string|nil err
function server_request:wait(max_head_size, timeout)
	local head, err = self.stream.reader:readUntil('\r?\n\r?\n', max_head_size or 8192, timeout, 4)
	if not head then
		return nil, err
	end

	local method, target, version, last = parser.parse_request_line(head)
	if not method then
		return nil, 'malformed request line'
	end

	if version ~= '1.0' and version ~= '1.1' then
		return nil, 'unsupported version'
	end

	self.method = method
	self.target = target
	self.version = version

	self.headers.immutable = false
	local req_headers, parse_err = parser.parse_head(self.headers, head, last)
	if not req_headers then
		return nil, parse_err
	end
	self.headers.immutable = true

	local is_chunked = false
	for value in self.headers:list('transfer-encoding') do
		if lower(value) == 'chunked' then
			is_chunked = true
		else
			return nil, 'unsupported transfer-encoding'
		end
	end

	local content_length
	for value in self.headers:list('content-length') do
		local n = tonumber(value)
		if not n or n < 0 or n % 1 ~= 0 then
			return nil, 'invalid content-length header'
		end

		if content_length and content_length ~= n then
			return nil, 'invalid content-length header'
		end

		content_length = n
	end

	for value in self.headers:list('expect') do
		if lower(value) == '100-continue' then
			self.expect_continue = true
		else
			return nil, 'unsupported expectation'
		end
	end

	local has_close = self.headers:hasToken('connection', 'close')
	local has_keep_alive = self.headers:hasToken('connection', 'keep-alive')
	if self.version == '1.0' then
		if is_chunked then
			return nil, 'chunked transfer-encoding not allowed in HTTP/1.0'
		end

		self.keep_alive = has_keep_alive and not has_close
	elseif self.version == '1.1' then
		self.keep_alive = not has_close
	end

	if is_chunked then
		if content_length then
			self.close_after_response = true
		end

		self.reader = protocol.chunked_reader.new(self.stream.reader)
	elseif content_length then
		self.reader = protocol.length_reader.new(self.stream.reader, content_length)
	end

	return self
end

--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function server_request:continue(timeout)
	if not self.expect_continue then
		return true
	end

	local ok, err = self.stream.writer:write('HTTP/1.1 100 Continue\r\n\r\n')
	if not ok then
		return false, err
	end

	self.expect_continue = false
	return self.stream.writer:flushAllRecursive(timeout)
end

return server_request
