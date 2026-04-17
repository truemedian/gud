local class = require('class')

--- @class std.git.object
--- @field kind string
local object = class.new('std.git.object')

--- Build the canonical git object representation: "<type> <size>\0<payload>".
--- @param kind string
--- @param payload string
--- @return string
function object.encode(kind, payload)
	assert(type(kind) == 'string' and #kind > 0, 'kind must be a non-empty string')
	assert(type(payload) == 'string', 'payload must be a string')
	return kind .. ' ' .. tostring(#payload) .. '\0' .. payload
end

--- Parse a canonical git object representation into kind and payload.
--- @param raw string
--- @return string|nil kind
--- @return string|nil payload
--- @return string|nil err
function object.decode(raw)
	local nul = raw:find('\0', 1, true)
	if not nul then
		return nil, nil, 'invalid object: missing header terminator'
	end

	local header = raw:sub(1, nul - 1)
	local kind, size_text = header:match('^([a-z]+) (%d+)$')
	if not kind then
		return nil, nil, 'invalid object header'
	end

	local payload = raw:sub(nul + 1)
	if #payload ~= tonumber(size_text) then
		return nil, nil, 'object size mismatch'
	end

	return kind, payload, nil
end

--- Parse the text header of a git object payload into a table of {key, value} pairs.
--- @param payload string
--- @return table headers
--- @return number|nil payload_start
function object.parse_header(payload)
	local headers, n = {}, 0

	local name, value
	local last
	for line, _, j in string.split(payload, '\n', true) do
		if line == '' then
			last = j
			break
		elseif line:sub(1, 1) == ' ' then
			value = value .. '\n' .. line:sub(2)
		else
			if name then
				n = n + 1
				headers[n] = { name, value }
			end

			name, value = line:match('^([a-z]+) (.*)$')
		end
	end

	if name then
		n = n + 1
		headers[n] = { name, value }
	end

	return headers, last
end

--- @param oid_type std.git.oid_type
--- @return string|nil str
--- @return string|nil err
function object:serialize(oid_type)
	return nil, 'serialize not implemented for ' .. tostring(self.kind)
end

--- Compute the OID of this object using the given OID type.
--- @param oid_type std.git.oid_type
--- @param hex boolean
--- @return string oid
function object:oid(oid_type, hex)
	local payload, err = self:serialize(oid_type)
	if not payload then
		error('failed to serialize ' .. tostring(self.kind) .. ': ' .. tostring(err))
	end

	return oid_type:oid(payload, self.kind, hex)
end

return object
