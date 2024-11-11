local commit = require('git/object/commit')
local tag = require('git/object/tag')
local tree = require('git/object/tree')

---@alias git.object.kind 'commit'|'tree'|'blob'|'tag'
---@alias git.object.blob string

---@class git.object
---@field kind git.object.kind
---@field commit git.object.commit
---@field tag git.object.tag
---@field tree git.object.tree
---@field blob git.object.blob
---@field raw string
---@field oid git.oid
local object = {}
local object_mt = { __index = object }

---@param kind git.object.kind
---@param raw string
---@param oid git.oid
function object.from_raw(kind, raw, oid)
	return setmetatable({ kind = kind, raw = raw, oid = oid }, object_mt)
end

function object.new_commit(tree_obj, author, committer, message)
	return setmetatable({
		kind = 'commit',
		commit = commit.new(tree_obj, author, committer, message),
	}, object_mt)
end

function object.new_tag(obj, name, tagger, message)
	return setmetatable({
		kind = 'tag',
		tag = tag.new(obj, name, tagger, message),
	}, object_mt)
end

function object.new_tree()
	return setmetatable({
		kind = 'tree',
		tree = tree.new(),
	}, object_mt)
end

function object.new_blob(data)
	return setmetatable({
		kind = 'blob',
		blob = data,
	}, object_mt)
end

---@param repository git.repository
---@return boolean, string|nil
function object:decode(repository)
	if self.commit or self.tree or self.blob or self.tag then
		return true
	end

	if self.kind == 'commit' then
		local decoded, err = commit.decode(repository, self.raw)
		if not decoded then
			return false, err
		end

		self.commit = decoded
	elseif self.kind == 'tree' then
		local decoded, err = tree.decode(repository, self.raw)
		if not decoded then
			return false, err
		end

		self.tree = decoded
	elseif self.kind == 'blob' then
		self.blob = self.raw
	elseif self.kind == 'tag' then
		local decoded, err = tag.decode(repository, self.raw)
		if not decoded then
			return false, err
		end

		self.tag = decoded
	end

	return true
end

---@param repository git.repository
---@return boolean, string|nil
function object:recode(repository)
	if self.kind == 'blob' then
		self.raw = self.blob
	elseif self.kind == 'tree' then
		local new_raw, err = self.tree:recode(repository)
		if not new_raw then
			return false, err
		end

		self.raw = new_raw
	elseif self.kind == 'commit' then
		local new_raw, err = self.commit:recode(repository)
		if not new_raw then
			return false, err
		end

		self.raw = new_raw
	elseif self.kind == 'tag' then
		local new_raw, err = self.tag:recode(repository)
		if not new_raw then
			return false, err
		end

		self.raw = new_raw
	end

	self.oid = repository.oid:digest(self.raw, self.kind)
	return true
end

return object
