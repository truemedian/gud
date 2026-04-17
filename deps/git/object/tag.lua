local class = require('class')

local identity = require('git/object/identity')
local object = require('git/object')

--- @class std.git.object.tag : std.git.object, std.class<std.git.object.tag>
--- @field object string
--- @field type string
--- @field name string
--- @field tagger std.git.identity
--- @field message string
local tag = class.new('std.git.object.tag', object)
tag.kind = 'tag'

--- @param info table
function tag:init(info)
	self.object = info.object
	self.type = info.type
	self.name = info.name
	self.tagger = info.tagger
	self.message = info.message or ''
end

--- @param data string
--- @param oid_type std.git.oid_type
--- @return std.git.object.tag|nil
--- @return string|nil err
function tag.parse(data, oid_type)
	local headers, message_start = object.parse_header(data)
	if not message_start then
		return nil, 'invalid tag'
	end

	local info = {
		object = nil,
		type = nil,
		name = nil,
		tagger = nil,
		message = data:sub(message_start),
	}

	for _, h in ipairs(headers) do
		if h[1] == 'object' then
			if info.object then
				return nil, 'tag cannot have multiple objects'
			end

			if not oid_type:check_hex(h[2]) then
				return nil, 'invalid tag object oid'
			end

			info.object = h[2]
		elseif h[1] == 'type' then
			if info.type then
				return nil, 'tag cannot have multiple types'
			end

			if type(h[2]) ~= 'string' or #h[2] == 0 then
				return nil, 'invalid tag type'
			end

			info.type = h[2]
		elseif h[1] == 'tag' then
			if info.name then
				return nil, 'tag cannot have multiple names'
			end

			if type(h[2]) ~= 'string' or #h[2] == 0 then
				return nil, 'invalid tag name'
			end

			info.name = h[2]
		elseif h[1] == 'tagger' then
			if info.tagger then
				return nil, 'tag cannot have multiple taggers'
			end

			local parsed, parse_err = identity.parse(h[2])
			if not parsed then
				return nil, 'invalid tag tagger: ' .. parse_err
			end

			info.tagger = parsed
		else
			return nil, 'unsupported tag header: ' .. h[1]
		end
	end

	if not info.object then
		return nil, 'tag object oid is required'
	elseif not info.type then
		return nil, 'tag type is required'
	elseif not info.name then
		return nil, 'tag name is required'
	end

	return tag.new(info)
end

--- @param oid_type std.git.oid_type
--- @return string|nil payload
--- @return string|nil err
function tag:serialize(oid_type)
	if not self.object or not oid_type:check_hex(self.object) then
		return nil, 'tag object oid is not valid'
	elseif type(self.type) ~= 'string' or #self.type == 0 then
		return nil, 'tag type is missing'
	elseif type(self.name) ~= 'string' or #self.name == 0 then
		return nil, 'tag name is missing'
	elseif type(self.message) ~= 'string' then
		return nil, 'tag message is missing'
	end

	local lines, n = {}, 0
	n = n + 1
	lines[n] = 'object ' .. self.object
	n = n + 1
	lines[n] = 'type ' .. self.type
	n = n + 1
	lines[n] = 'tag ' .. self.name

	local tagger_line, tagger_err = identity.format(self.tagger)
	if not tagger_line then
		return nil, tagger_err
	end

	n = n + 1
	lines[n] = 'tagger ' .. tagger_line
	n = n + 1
	lines[n] = ''
	n = n + 1
	lines[n] = self.message

	return table.concat(lines, '\n', 1, n)
end

return tag
