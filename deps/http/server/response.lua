local class = require('class')
--- @type std.writer
local writer = require('writer')

local protocol = require('http/protocol')

local format = string.format
local lower = string.lower
local tonumber = tonumber
local concat = table.concat

local EMPTY_WRITER = writer.empty()

local function append_header(lines, name, value)
	lines[#lines + 1] = name
	lines[#lines + 1] = ': '
	lines[#lines + 1] = value
	lines[#lines + 1] = '\r\n'
end

local function response_has_body(response)
	if response.request.method == 'HEAD' then
		return false
	elseif response.request.method == 'CONNECT' and response.status >= 200 and response.status < 300 then
		return false
	elseif response.status >= 100 and response.status < 200 then
		return false
	elseif response.status == 204 or response.status == 304 then
		return false
	end

	return true
end

--- @class std.http.server.response
--- @field request std.http.server.request
--- @field stream std.net.stream
--- @field status integer
--- @field reason string
--- @field headers std.http.headers
--- @field writer std.http.writer.length|std.http.writer.chunked|std.writer
local server_response = class('std.http.server.response')

function server_response:init(request)
	self.request = request
	self.stream = request.stream
	self.state = 'finished'

	self.headers = protocol.headers()

	self:reset()
end

function server_response:reset()
	assert(self.state == 'finished', 'response not finished')

	self.state = 'ready'
	self.status = 500
	self.reason = 'Internal Server Error'
	self.writer = EMPTY_WRITER

	table.clear(self.headers.fields)
	self.headers.immutable = false
end

--- @param status integer
--- @param reason? string
--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function server_response:respond(status, reason, timeout)
	assert(self.state == 'ready', 'response already started')

	self.status = status
	self.reason = reason or protocol.status_reasons[status] or ''

	local transfer_encoding = self.headers:get('transfer-encoding')
	local content_length = self.headers:get('content-length')
	local transfer_encoding_lower = transfer_encoding and lower(transfer_encoding)
	local content_length_number = nil
	local has_body = response_has_body(self)

	if transfer_encoding_lower and transfer_encoding_lower ~= 'chunked' then
		return false, 'unsupported transfer-encoding'
	elseif transfer_encoding and content_length then
		return false, 'content-length not allowed with transfer-encoding'
	elseif transfer_encoding_lower == 'chunked' and self.request.version == '1.0' then
		return false, 'chunked transfer-encoding not allowed in HTTP/1.0'
	elseif transfer_encoding and not has_body then
		return false, 'transfer-encoding not allowed for this response'
	elseif content_length then
		local n = tonumber(content_length)

		if not n or n < 0 or n % 1 ~= 0 then
			return false, 'invalid content-length'
		end

		content_length_number = n
	end

	self.state = 'started'
	self.headers.immutable = true

	local lines = { format('HTTP/%s %d %s\r\n', self.request.version, self.status, self.reason) }
	for name, value in pairs(self.headers.fields) do
		if type(value) == 'table' then
			for _, v in ipairs(value) do
				append_header(lines, name, v)
			end
		else
			append_header(lines, name, value)
		end
	end

	lines[#lines + 1] = '\r\n'

	local ok, err = self.stream.writer:write(concat(lines), timeout)
	if not ok then
		return false, err
	end

	if has_body then
		if transfer_encoding_lower == 'chunked' then
			self.writer = protocol.chunked_writer(self.stream.writer)
		elseif content_length then
			self.writer = protocol.length_writer(self.stream.writer, content_length_number)
		else
			self.writer = self.stream.writer
		end
	end

	return true
end

--- @param timeout? integer
--- @return boolean success
--- @return string|nil err
function server_response:finish(timeout)
	assert(self.state == 'started', 'response has not started, call :respond() first')

	if self.writer.finish then
		local ok, err = self.writer:finish(timeout)
		if not ok then
			return false, err
		end
	else
		local ok, err = self.writer:flushAllRecursive(timeout)
		if not ok then
			return false, err
		end
	end

	self.state = 'finished'
	return true
end

--- @return boolean
function server_response:isReusable()
	if self.state ~= 'finished' then
		return false
	elseif self.headers:hasToken('connection', 'close') then
		return false
	elseif self.request.close_after_response then
		return false
	elseif not self.request.reader.closed then
		return false
	elseif not self.writer.closed then
		return false
	end

	return self.request.keep_alive
end

return server_response
