local class = require('class')

local identity = require('git/object/identity')
local object = require('git/object')

--- @class std.git.object.commit : std.git.object, std.class<std.git.object.commit>
--- @field tree string
--- @field parents string[]
--- @field author std.git.identity
--- @field committer std.git.identity
--- @field message string
local commit = class.new('std.git.object.commit', object)
commit.kind = 'commit'

--- @param info table
function commit:init(info)
	self.tree = info.tree
	self.parents = info.parents or {}
	self.author = info.author
	self.committer = info.committer
	self.message = info.message or ''
end

--- @param data string
--- @param oid_type std.git.oid_type
--- @return std.git.object.commit|nil
--- @return string|nil err
function commit.parse(data, oid_type)
	local headers, message_start = object.parse_header(data)
	if not message_start then
		return nil, 'invalid commit'
	end

	local info = {
		tree = nil,
		parents = {},
		author = nil,
		committer = nil,
		message = data:sub(message_start),
	}

	for _, h in ipairs(headers) do
		if h[1] == 'tree' then
			if info.tree then
				return nil, 'commit cannot have multiple trees'
			end

			if not oid_type:check_hex(h[2]) then
				return nil, 'invalid commit tree oid'
			end

			info.tree = h[2]
		elseif h[1] == 'parent' then
			if not oid_type:check_hex(h[2]) then
				return nil, 'invalid commit parent oid'
			end

			table.insert(info.parents, h[2])
		elseif h[1] == 'author' then
			if info.author then
				return nil, 'commit cannot have multiple authors'
			end

			local parsed, parse_err = identity.parse(h[2])
			if not parsed then
				return nil, 'invalid commit author: ' .. parse_err
			end

			info.author = parsed
		elseif h[1] == 'committer' then
			if info.committer then
				return nil, 'commit cannot have multiple committers'
			end

			local parsed, parse_err = identity.parse(h[2])
			if not parsed then
				return nil, 'invalid commit committer: ' .. parse_err
			end

			info.committer = parsed
		else
			return nil, 'unsupported commit header: ' .. h[1]
		end
	end

	if not info.tree then
		return nil, 'commit tree is required'
	elseif not info.author then
		return nil, 'commit author is required'
	elseif not info.committer then
		return nil, 'commit committer is required'
	end

	return commit.new(info)
end

--- @param oid_type std.git.oid_type
--- @return string|nil payload
--- @return string|nil err
function commit:serialize(oid_type)
	if not self.tree or not oid_type:check_hex(self.tree) then
		return nil, 'commit tree oid is not valid'
	elseif not self.author then
		return nil, 'commit author is required'
	elseif not self.committer then
		return nil, 'commit committer is required'
	elseif type(self.message) ~= 'string' then
		return nil, 'commit message is missing'
	end

	local author_line, author_err = identity.format(self.author)
	if not author_line then
		return nil, author_err
	end

	local committer_line, committer_err = identity.format(self.committer)
	if not committer_line then
		return nil, committer_err
	end

	local lines, n = {}, 0

	n = n + 1
	lines[n] = 'tree ' .. self.tree

	for i = 1, #self.parents do
		local parent = self.parents[i]
		if not oid_type:check_hex(parent) then
			return nil, 'commit parent oid is not valid'
		end

		n = n + 1
		lines[n] = 'parent ' .. parent
	end

	n = n + 1
	lines[n] = 'author ' .. author_line
	n = n + 1
	lines[n] = 'committer ' .. committer_line

	n = n + 1
	lines[n] = ''
	n = n + 1
	lines[n] = self.message

	return table.concat(lines, '\n', 1, n)
end

return commit
