local class = require('class')

--- @type std.reader
local reader = require('reader')

--- @type std.writer
local writer = require('writer')

local format = string.format
local find = string.find
local lower = string.lower
local match = string.match
local min = math.min
local sub = string.sub
local tonumber = tonumber

local function trim(value)
	return match(value, '^[ \t]*(.-)[ \t]*$')
end

--- @class std.http.headers
--- @field immutable boolean
--- @field fields { [string]: string|string[] }
local headers = class('std.http.headers')

function headers:init()
	self.fields = {}
	self.immutable = false
end

function headers:add(name, new_value)
	assert(not self.immutable, 'headers are immutable')

	name = lower(name)

	local value = self.fields[name]
	if type(value) == 'string' then
		self.fields[name] = { value, new_value }
	elseif type(value) == 'table' then
		value[#value + 1] = new_value
	else
		self.fields[name] = new_value
	end
end

function headers:count(name)
	local value = self.fields[name]

	if not value then
		return 0
	elseif type(value) == 'string' then
		return 1
	elseif type(value) == 'table' then
		return #value
	end
end

function headers:set(name, value)
	assert(not self.immutable, 'headers are immutable')

	self.fields[lower(name)] = value
end

function headers:remove(name)
	assert(not self.immutable, 'headers are immutable')

	self.fields[lower(name)] = nil
end

function headers:get(name)
	local value = self.fields[lower(name)]
	if type(value) == 'string' then
		return value
	elseif type(value) == 'table' then
		return value[#value]
	end
end

--- Returns all field-line values in received order.
--- @param name string
--- @return string[] values
function headers:getAll(name)
	local value = self.fields[lower(name)]
	if type(value) == 'string' then
		return { value }
	elseif type(value) == 'table' then
		local result = {}
		for i = 1, #value do
			result[i] = value[i]
		end

		return result
	end

	return {}
end

--- Returns the field value as a comma+SP combined value, as defined by HTTP field combination rules.
--- @param name string
--- @return string|nil value
function headers:getCombined(name)
	local values = self:getAll(name)
	if #values == 0 then
		return nil
	end

	return table.concat(values, ', ')
end

--- Returns the field value split as a comma-separated list across duplicate field lines.
---
--- Empty list members are ignored.
--- @param name string
--- @return fun(): string|nil iter
function headers:list(name)
	local source = self.fields[lower(name)]
	if not source then
		return function()
			return nil
		end
	end

	local i = 1

	--- @type string|nil
	local value = type(source) == 'string' and source or source[1]
	local offset = 1

	return function()
		while value do
			local comma = find(value, ',', offset, true)
			local item
			if comma then
				item = sub(value, offset, comma - 1)
				offset = comma + 1
			else
				item = sub(value, offset)
				if type(source) == 'table' then
					i = i + 1
					value = source[i]
					offset = 1
				else
					value = nil
				end
			end

			item = trim(item)
			if #item > 0 then
				return item
			end
		end

		return nil
	end
end

--- Returns an iterator over all fields
function headers:all()
	local name, value
	local i = 0

	return function()
		if type(value) == 'table' then
			i = i + 1
			if value[i] then
				return name, value[i]
			end

			name, value = next(self.fields, name)
			i = 0
		else
			name, value = next(self.fields, name)
		end

		if type(value) == 'table' then
			return name, value[1]
		else
			return name, value
		end
	end
end

--- Checks for token membership in a comma-separated list field (case-insensitive).
--- @param name string
--- @param token string
--- @return boolean
function headers:hasToken(name, token)
	token = lower(token)
	for value in self:list(name) do
		if lower(value) == token then
			return true
		end
	end

	return false
end

function headers:has(name)
	return self.fields[lower(name)] ~= nil
end

--- @return std.http.headers clone
function headers:clone()
	local clone = headers()

	for name, value in pairs(self.fields) do
		if type(value) == 'table' then
			local copied = {}
			for i = 1, #value do
				copied[i] = value[i]
			end

			clone.fields[name] = copied
		else
			clone.fields[name] = value
		end
	end

	clone.immutable = self.immutable
	return clone
end

--- @class std.http.reader.chunked : std.reader
--- @field underlying std.reader
--- @field chunk_left integer
local chunked_reader = class('std.http.reader.chunked', reader)

function chunked_reader:init(underlying)
	reader.init(self)
	self.underlying = underlying
	self.chunk_left = 0
end

function chunked_reader:fill(n, timeout)
	if self.closed then
		return 0
	end

	if self.chunk_left == 0 then
		local line, err = self.underlying:readUntil('\r?\n', 256, timeout, 2)
		if not line then
			return 0, err
		end

		local chunk_size = tonumber(match(line, '^([0-9a-fA-F]+)'), 16)
		if not chunk_size then
			return 0, 'invalid chunk size'
		end

		if chunk_size == 0 then
			local trailers, trailer_err = self.underlying:readUntil('\r?\n\r?\n', 1024, timeout, 4)
			if not trailers then
				return 0, trailer_err
			end

			return 0
		end

		self.chunk_left = chunk_size
	end

	local requested = min(n or math.huge, self.chunk_left)
	local chunk, err = self.underlying:readAtMost(requested, timeout)
	if not chunk then
		return 0, err
	end

	self.buffer:write(chunk)
	self.chunk_left = self.chunk_left - #chunk

	if self.chunk_left == 0 then
		local crlf, crlf_err = self.underlying:readUntil('\r?\n', 2, timeout, 2)
		if not crlf then
			return 0, crlf_err
		end
	end

	return #chunk
end

--- @class std.http.reader.length : std.reader
--- @field underlying std.reader
--- @field length_left integer
local length_reader = class('std.http.reader.length', reader)

function length_reader:init(underlying, length)
	reader.init(self)
	self.underlying = underlying
	self.length_left = length
	self.closed = length == 0
end

function length_reader:fill(n, timeout)
	if self.length_left == 0 then
		self.closed = true
		return 0
	end

	local requested = min(n or math.huge, self.length_left)
	local data, err = self.underlying:readAtMost(requested, timeout)
	if not data then
		return 0, err
	end

	self.length_left = self.length_left - #data
	if self.length_left == 0 then
		self.closed = true
	end

	self.buffer:write(data)
	return #data, err
end

--- @class std.http.writer.chunked : std.writer
--- @field underlying std.writer
--- @field finished boolean
local chunked_writer = class('std.http.writer.chunked', writer)

function chunked_writer:init(underlying)
	writer.init(self)
	self.underlying = underlying
	self.finished = false
end

function chunked_writer:flush(timeout)
	if self.finished then
		return 0, 'closed'
	end

	local parts = self.buffer:parts()
	local total_length = 0

	for i = 1, #parts do
		local part = parts[i]

		local ok, err = self.underlying:write(format('%X\r\n', #part), timeout)
		if not ok then
			return total_length, err
		end

		ok, err = self.underlying:write(part, timeout)
		if not ok then
			return total_length, err
		end

		ok, err = self.underlying:write('\r\n', timeout)
		if not ok then
			return total_length, err
		end

		total_length = total_length + #part
	end

	return total_length
end

function chunked_writer:finish(timeout)
	local ok, err = writer.flushAll(self, timeout)
	if not ok then
		return false, err
	end

	ok, err = self.underlying:write('0\r\n\r\n', timeout)
	if not ok then
		return false, err
	end

	self.closed = true
	return self.underlying:flushAllRecursive(timeout)
end

--- @class std.http.writer.length : std.writer
--- @field underlying std.writer
--- @field length_left integer
local length_writer = class('std.http.writer.length', writer)

function length_writer:init(underlying, length)
	writer.init(self)
	self.underlying = underlying
	self.length_left = length
end

function length_writer:flush(timeout)
	local parts = self.buffer:parts()
	if #parts == 0 then
		return 0
	end

	local total_length = 0
	for i = 1, #parts do
		local part = parts[i]
		if #part > self.length_left then
			return total_length, 'content-length exceeded'
		end

		local ok, err = self.underlying:write(part, timeout)
		if not ok then
			return total_length, err
		end

		self.length_left = self.length_left - #part
		total_length = total_length + #part
	end

	self.closed = self.length_left == 0
	return total_length
end

function length_writer:finish(timeout)
	local ok, err = writer.flushAll(self, timeout)
	if not ok then
		return false, err
	elseif self.length_left ~= 0 then
		return false, 'content-length incomplete'
	end

	self.closed = true
	return self.underlying:flushAllRecursive(timeout)
end

local status_reasons = {
	[100] = 'Continue',
	[101] = 'Switching Protocols',
	[102] = 'Processing',
	[103] = 'Early Hints',
	[200] = 'OK',
	[201] = 'Created',
	[202] = 'Accepted',
	[203] = 'Non-Authoritative Information',
	[204] = 'No Content',
	[205] = 'Reset Content',
	[206] = 'Partial Content',
	[207] = 'Multi-Status',
	[208] = 'Already Reported',
	[226] = 'IM Used',
	[300] = 'Multiple Choices',
	[301] = 'Moved Permanently',
	[302] = 'Found',
	[303] = 'See Other',
	[304] = 'Not Modified',
	[305] = 'Use Proxy',
	[307] = 'Temporary Redirect',
	[308] = 'Permanent Redirect',
	[400] = 'Bad Request',
	[401] = 'Unauthorized',
	[402] = 'Payment Required',
	[403] = 'Forbidden',
	[404] = 'Not Found',
	[405] = 'Method Not Allowed',
	[406] = 'Not Acceptable',
	[407] = 'Proxy Authentication Required',
	[408] = 'Request Timeout',
	[409] = 'Conflict',
	[410] = 'Gone',
	[411] = 'Length Required',
	[412] = 'Precondition Failed',
	[413] = 'Content Too Large',
	[414] = 'URI Too Long',
	[415] = 'Unsupported Media Type',
	[416] = 'Range Not Satisfiable',
	[417] = 'Expectation Failed',
	[421] = 'Misdirected Request',
	[422] = 'Unprocessable Content',
	[423] = 'Locked',
	[424] = 'Failed Dependency',
	[425] = 'Too Early',
	[426] = 'Upgrade Required',
	[428] = 'Precondition Required',
	[429] = 'Too Many Requests',
	[431] = 'Request Header Fields Too Large',
	[451] = 'Unavailable For Legal Reasons',
	[500] = 'Internal Server Error',
	[501] = 'Not Implemented',
	[502] = 'Bad Gateway',
	[503] = 'Service Unavailable',
	[504] = 'Gateway Timeout',
	[505] = 'HTTP Version Not Supported',
	[506] = 'Variant Also Negotiates',
	[507] = 'Insufficient Storage',
	[508] = 'Loop Detected',
	[510] = 'Not Extended',
	[511] = 'Network Authentication Required',
}

return {
	headers = headers,
	chunked_reader = chunked_reader,
	length_reader = length_reader,
	chunked_writer = chunked_writer,
	length_writer = length_writer,
	status_reasons = status_reasons,
}
