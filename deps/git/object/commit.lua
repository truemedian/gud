local sshkey = require('sshkey')

local person = require('git/object/person')

---@class git.object.commit
---@field tree git.object
---@field parents git.object[]
---@field author git.object.person
---@field committer git.object.person
---@field signature string|nil
---@field message string
local commit = {}
local commit_mt = { __index = commit }

---@param tree git.object
---@param author git.object.person
---@param committer git.object.person
---@param message string
function commit.new(tree, author, committer, message)
	return setmetatable({
		tree = tree,
		author = author,
		committer = committer,
		message = message,
		parents = {},
	}, commit_mt)
end

---@param repository git.repository
---@param data string
---@return git.object.commit|nil, string|nil
function commit.decode(repository, data)
	local self = setmetatable({ parents = {} }, commit_mt)
	local stop = data:find('\n\n', 1, true)
	local pos = 1

	while pos <= stop do
		local name, value_start = data:match('^(%S+) ()', pos)
		if not name then
			return nil, 'commit.decode: invalid commit format'
		end

		local value_end = data:match('\n()[%S\n]', value_start)
		if not value_end then
			value_end = stop
		end

		local value = data:sub(value_start, value_end - 2)
		pos = value_end

		if name == 'tree' then
			---@cast value git.oid
			local tree = repository:load(value)
			if not tree then
				return nil, 'commit.decode: failed to load tree object'
			end

			if tree.kind ~= 'tree' then
				return nil, 'commit.decode: invalid tree object'
			end

			self.tree = tree
		elseif name == 'parent' then
			---@cast value git.oid
			local parent = repository:load(value)
			if not parent then
				return nil, 'commit.decode: failed to load parent object'
			end

			if parent.kind ~= 'commit' then
				return nil, 'commit.decode: invalid parent object'
			end

			table.insert(self.parents, parent)
		elseif name == 'author' then
			local author, err = person.decode(value)
			if not author then
				return nil, err
			end

			self.author = author
		elseif name == 'committer' then
			local committer, err = person.decode(value)
			if not committer then
				return nil, err
			end

			self.committer = committer
		elseif name == 'gpgsig' then
			self.signature = value:gsub('\n ', '\n')
		elseif name == 'HG:rename-source' then
			-- ignore
		elseif name == 'mergetag' then
			-- ignore
		elseif name == 'encoding' then
			-- ignore
		else
			return nil, 'commit.decode: unknown commit field: ' .. name
		end
	end

	if not self.tree then
		return nil, 'commit.decode: missing tree field in commit object'
	end

	if not self.author then
		return nil, 'commit.decode: missing author field in commit object'
	end

	if not self.committer then
		return nil, 'commit.decode: missing committer field in commit object'
	end

	self.message = data:sub(stop + 1)
	return self
end

---@param repository git.repository
---@return string|nil, string|nil
function commit:recode(repository)
	local recoded, err = self.tree:recode(repository)
	if not recoded then
		return nil, err
	end

	local parts = {
		'tree ' .. self.tree.oid,
	}

	for _, parent in ipairs(self.parents) do
		recoded, err = parent:recode(repository)
		if not recoded then
			return nil, err
		end

		table.insert(parts, 'parent ' .. parent.oid)
	end

	table.insert(parts, 'author ' .. self.author:encode())
	table.insert(parts, 'committer ' .. self.committer:encode())

	if self.signature then
		table.insert(parts, 'gpgsig ' .. self.signature:gsub('\n', '\n '))
	end

	table.insert(parts, '')
	table.insert(parts, self.message)
	return table.concat(parts, '\n')
end

---@param key sshkey.key
---@param namespace string|nil
---@return boolean, string|nil
function commit:sign(repository, key, namespace)
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

return commit
