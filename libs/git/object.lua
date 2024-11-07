local bit = require('bit')

local sshkey = require('sshkey')

---@alias git.person { name: string, email: string, time: { seconds: number, offset: number } }

local function decode_time(data)
	local seconds, offset_hr, offset_min = string.match(data, '(%d+) ([+-]%d%d)(%d%d)')
	assert(seconds, 'malformed time data')

	local offset = tonumber(offset_hr) * 60 + tonumber(offset_min)
	assert(offset >= -1440 and offset <= 1440, 'malformed time offset (must be between -1440 and 1440)')

	return { seconds = tonumber(seconds), offset = offset }
end

local function encode_time(data)
	assert(type(data.seconds) == 'number', 'malformed time seconds')
	assert(type(data.offset) == 'number', 'malformed time offset')
	assert(data.offset >= -1440 and data.offset <= 1440, 'malformed time offset (must be between -1440 and 1440)')

	local offset_hr = math.floor(data.offset / 60)
	local offset_min = data.offset % 60

	return string.format('%d %+03d%02d', data.seconds, offset_hr, offset_min)
end

local function decode_person(data)
	local name, email, time = string.match(data, '([^<]*) <([^>]*)> (.+)')
	assert(name, 'malformed person data')

	return { name = name, email = email, time = decode_time(time) }
end

local function encode_person(data)
	assert(type(data.name) == 'string' and #data.name > 0, 'malformed person name')
	assert(type(data.email) == 'string' and #data.email > 0, 'malformed person email')
	local time = encode_time(data.time)

	local safe_name = data.name:gsub('[%c<>]', '')
	local safe_email = data.email:gsub('[%c<>]', '')

	return string.format('%s <%s> %s', safe_name, safe_email, time)
end

local function mode_is_tree(mode)
	return mode == 0x4000 -- 0b0100_000_000000000
end

local function mode_is_file(mode)
	return bit.band(mode, 0xF000) == 0x8000 -- 0b1000_000_XXXXXXXXX
end

local function mode_is_symlink(mode)
	return bit.band(mode, 0xF000) == 0xA000 -- 0b1010_000_XXXXXXXXX
end

local function mode_is_gitlink(mode)
	return mode == 0xE000 -- 0b1110_000_000000000
end

local function mode_to_name(mode)
	if mode_is_tree(mode) then
		return 'tree'
	elseif mode_is_file(mode) then
		return 'blob'
	elseif mode_is_symlink(mode) then
		return 'blob'
	elseif mode_is_gitlink(mode) then
		return 'commit'
	end

	return 'unknown'
end

---@alias git.object.kind 'commit'|'tree'|'blob'|'tag'
---@class git.object
---@field kind git.object.kind
---@field data string
---@field oid git.oid
---@field odb git.odb
local object = {}
local object_mt = { __index = object }

---@param odb git.odb
---@param kind git.object.kind
---@param data string
---@param oid git.oid
---@return git.object
function object.create(odb, kind, data, oid)
	assert(odb.oid_type:digest(data, kind) == oid, 'object data does not match oid')

	return setmetatable({ odb = odb, kind = kind, data = data, oid = oid }, object_mt)
end

---@param odb git.odb
---@param data string
---@return git.object
function object.blob(odb, data)
	local oid = odb.oid_type:digest(data, 'blob')
	return object.create(odb, 'blob', data, oid)
end

---@param odb git.odb
---@param files { name: string, mode: number, hash: git.oid }[]
---@return git.object
function object.tree(odb, files)
	local encoded = {}
	for _, file in ipairs(files) do
		assert(type(file.name) == 'string' and #file.name > 0, 'malformed tree name')
		assert(type(file.mode) == 'number' and mode_to_name, 'malformed tree mode')
		assert(type(file.hash) == 'string' and #file.hash == odb.oid_type.hex_length, 'malformed tree hash')

		table.insert(encoded, string.format('%06o %s\0%s', file.mode, file.name, odb.oid_type:hex2bin(file.hash)))
	end

	local data = table.concat(encoded)
	local oid = odb.oid_type:digest(data, 'tree')
	return object.create(odb, 'tree', data, oid)
end

---@param odb git.odb
---@param options { tree: git.object, parents: git.object[]|nil, message: string, author: git.person, committer: git.person }
---@return git.object
function object.commit(odb, options)
	assert(getmetatable(options.tree) == object_mt, 'invalid commit tree')
	assert(type(options.message) == 'string', 'malformed commit message')

	local author = encode_person(options.author)
	local committer = encode_person(options.committer)

	local encoded = { 'tree ' .. options.tree.oid }
	if options.parents then
		for _, parent in ipairs(options.parents) do
			assert(getmetatable(parent) == object_mt, 'invalid commit parent')
			table.insert(encoded, 'parent ' .. parent.oid)
		end
	end

	table.insert(encoded, 'author ' .. author)
	table.insert(encoded, 'committer ' .. committer)

	table.insert(encoded, '')
	table.insert(encoded, options.message)
	local data = table.concat(encoded, '\n')

	local oid = odb.oid_type:digest(data, 'commit')
	return object.create(odb, 'commit', data, oid)
end

---@param odb git.odb
---@param options { object: git.object, tag: string, message: string, tagger: git.person, signing_key: sshkey.key|nil }
---@return git.object
function object.tag(odb, options)
	assert(getmetatable(options.object) == object_mt, 'invalid tag object')
	assert(type(options.tag) == 'string' and #options.tag > 0, 'malformed tag field')
	assert(type(options.message) == 'string', 'malformed tag message')
	local tagger = encode_person(options.tagger)
	local safe_tag = options.tag:gsub('%c', '')
	local typ = options.object.kind

	local encoded = string.format(
		'object %s\ntype %s\ntag %s\ntagger %s\n\n%s',
		options.object.oid,
		typ,
		safe_tag,
		tagger,
		options.message
	)

	if options.signing_key then
		local signature, err = sshkey.create_signature(options.signing_key, encoded, 'git-tag')
		if not signature then
			error('failed to sign tag: ' .. err)
		end

		encoded = encoded .. '\n' .. signature
	end

	local oid = odb.oid_type:digest(encoded, 'tag')
	return object.create(odb, 'tag', encoded, oid)
end

function object:parse()
	if self.kind == 'blob' then
		return self.data
	elseif self.kind == 'tree' then
		return self:parse_tree()
	elseif self.kind == 'commit' then
		return self:parse_commit()
	elseif self.kind == 'tag' then
		return self:parse_tag()
	end
end

function object:parse_tree()
	assert(self.kind == 'tree', 'object is not a tree')

	local tree = {}
	local pos = 1

	local pattern = '^([0-7]+) ([^%z]+)%z(' .. string.rep('.', self.odb.oid_type.bin_length) .. ')()'
	while pos <= #self.data do
		local mode, name, oid, after = self.data:match(pattern, pos)
		assert(mode, 'invalid tree format')

		mode = tonumber(mode, 8)
		table.insert(tree, {
			mode = mode,
			name = name,
			hash = self.odb.oid_type:bin2hex(oid),
			kind = mode_to_name(mode),
		})

		pos = after
	end

	assert(pos == #self.data + 1, 'malformed tree object')
	return tree
end

function object:parse_commit()
	assert(self.kind == 'commit', 'object is not a commit')

	local commit = { parents = {} }
	local pos = 1
	local stop = self.data:find('\n\n', pos, true)

	while pos <= stop do
		local name, value_start = self.data:match('^(%S+) ()', pos)
		assert(value_start, 'invalid commit format')

		local value_end = self.data:match('\n()[%S\n]', value_start)
		if not value_end then
			value_end = stop
		end

		local value = self.data:sub(value_start, value_end - 2)
		pos = value_end

		if name == 'tree' then
			commit.tree = value
		elseif name == 'parent' then
			table.insert(commit.parents, value)
		elseif name == 'author' then
			commit.author = decode_person(value)
		elseif name == 'committer' then
			commit.committer = decode_person(value)
		elseif name == 'gpgsig' then
			commit.gpgsig = value:gsub('\n ', '\n')
		elseif name == 'HG:rename-source' then
			-- ignore
		elseif name == 'mergetag' then
			-- ignore
		elseif name == 'encoding' then
			-- ignore
		else
			error('unknown commit field: ' .. name)
		end
	end

	assert(commit.tree, 'missing tree field in commit object')
	assert(commit.author, 'missing author field in commit object')
	assert(commit.committer, 'missing committer field in commit object')

	commit.message = self.data:sub(stop + 1)
	return commit
end

function object:parse_tag()
	assert(self.kind == 'tag', 'object is not a tag')

	local tag = {}
	local pos = 1
	local _, stop = self.data:find('\n\n', pos, true)

	while pos < stop do
		local name, value_start = self.data:match('^(%w+) ()', pos)
		assert(value_start, 'invalid tag format')

		local value_end = self.data:match('\n()%w', value_start)
		if not value_end then
			value_end = stop
		end

		local value = self.data:sub(value_start, value_end - 2)
		pos = value_end

		if name == 'object' then
			tag.object = value
		elseif name == 'type' then
			tag.type = value
		elseif name == 'tag' then
			tag.tag = value
		elseif name == 'tagger' then
			tag.tagger = decode_person(value)
		else
			error('unknown tag field: ' .. name)
		end
	end

	assert(tag.object, 'missing object field in tag object')
	assert(tag.type, 'missing type field in tag object')
	assert(tag.tagger, 'missing tagger field in tag object')
	assert(tag.tag, 'missing tag field in tag object')

	tag.message = self.data:sub(stop + 1)
	return tag
end

return object
