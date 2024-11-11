local sshkey = require('sshkey')

local person = require('git/object/person')

---@class git.object.tag
---@field object git.object
---@field type git.object.kind
---@field name string
---@field tagger git.object.person
---@field message string
---@field signature string|nil
local tag = {}
local tag_mt = { __index = tag }

---@param object git.object
---@param name string
---@param tagger git.object.person
---@param message string
function tag.new(object, name, tagger, message)
	return setmetatable({
		object = object,
		type = object.kind,
		name = name,
		tagger = tagger,
		message = message,
	}, tag_mt)
end

---@param repository git.repository
---@param data string
---@return git.object.tag|nil, string|nil
function tag.decode(repository, data)
	local self = setmetatable({}, tag_mt)
	local stop = data:find('\n\n', 1, true)
	local pos = 1

	while pos < stop do
		local name, value_start = data:match('^(%w+) ()', pos)
		assert(value_start, 'invalid tag format')

		local value_end = data:match('\n()%w', value_start)
		if not value_end then
			value_end = stop
		end

		local value = data:sub(value_start, value_end - 2)
		pos = value_end

		if name == 'object' then
			---@cast value git.oid
			local object = repository:load(value)
			if not object then
				return nil, 'commit.decode: failed to load tree object'
			end

			if object.kind ~= 'tree' then
				return nil, 'commit.decode: invalid tree object'
			end

			self.object = object
		elseif name == 'type' then
			self.type = value
		elseif name == 'tag' then
			self.name = value
		elseif name == 'tagger' then
			local tagger, err = person.decode(value)
			if not tagger then
				return nil, err
			end

			self.tagger = tagger
		else
			error('unknown tag field: ' .. name)
		end
	end

	if not self.object then
		return nil, 'tag.decode: missing object field in tag object'
	end

	if not self.type then
		return nil, 'tag.decode: missing type field in tag object'
	end

	if self.type ~= self.object.kind then
		return nil, 'tag.decode: type field does not match object kind'
	end

	if not self.tagger then
		return nil, 'tag.decode: missing tagger field in tag object'
	end

	if not self.name then
		return nil, 'tag.decode: missing tag field in tag object'
	end

	self.message = data:sub(stop + 1)
	return self
end

---@param repository git.repository
---@return string|nil, string|nil
function tag:recode(repository)
	local recoded, err = self.object:recode(repository)
	if not recoded then
		return nil, err
	end

	local safe_name = self.name:gsub('%c', '')

	return string.format(
		'object %s\ntype %s\ntag %s\ntagger %s\n\n%s\n%s',
		self.object.oid,
		self.type,
		safe_name,
		self.tagger:encode(),
		self.message:match('^%s*(.-)%s*$'),
		self.signature or ''
	)
end

---@param repository git.repository
---@param key sshkey.key
---@param namespace string|nil
---@return boolean, string|nil
function tag:sign(repository, key, namespace)
	local encoded, err = self:recode(repository)
	if not encoded then
		return false, err
	end

	local signature
	signature, err = sshkey.sign(key, encoded, namespace or 'git-commit')
	if not signature then
		return false, err
	end

	self.signature = signature
	return true
end

return tag
