local commit = require('git/object/commit')
local tag = require('git/object/tag')
local tree = require('git/object/tree')

local person = require('git/object/person')

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
---@field stored boolean
local object = {}
local object_mt = { __index = object }

---@param kind git.object.kind
---@param raw string
---@param oid git.oid
function object.from_raw(kind, raw, oid)
	return setmetatable({ kind = kind, raw = raw, oid = oid, stored = true }, object_mt)
end

function object.new_commit(tree_obj, author, committer, message)
	assert(getmetatable(tree_obj) == object_mt, 'tree is not an object')
	assert(person.check(author), 'author is not a person')
	assert(person.check(committer), 'committer is not a person')
	assert(type(message) == 'string', 'message is not a string')

	return setmetatable({
		kind = 'commit',
		commit = commit.new(tree_obj, author, committer, message),
		stored = false,
	}, object_mt)
end

function object.new_tag(obj, name, tagger, message)
	assert(getmetatable(obj) == object_mt, 'object is not an object')
	assert(person.check(tagger), 'tagger is not a person')
	assert(type(name) == 'string', 'name is not a string')
	assert(type(message) == 'string', 'message is not a string')

	return setmetatable({
		kind = 'tag',
		tag = tag.new(obj, name, tagger, message),
		stored = false,
	}, object_mt)
end

function object.new_tree()
	return setmetatable({
		kind = 'tree',
		tree = tree.new(),
		stored = false,
	}, object_mt)
end

function object.new_blob(data)
	assert(type(data) == 'string', 'data is not a string')

	return setmetatable({
		kind = 'blob',
		blob = data,
		stored = false,
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
	if self.stored then
		return true
	end

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

--- safe commit-specific methods

---@param tree_obj git.object
function object:commit_set_tree(tree_obj)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'commit', 'object is not a commit')
	assert(getmetatable(tree_obj) == object_mt, 'tree is not an object')

	self.commit.tree = tree_obj
end

---@param parent_obj git.object
function object:commit_add_parent(parent_obj)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'commit', 'object is not a commit')
	assert(getmetatable(parent_obj) == object_mt, 'parent is not an object')
	assert(parent_obj.kind == 'commit', 'parent is not a commit')

	table.insert(self.commit.parents, parent_obj)
end

---@param author git.object.person
function object:commit_set_author(author)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'commit', 'object is not a commit')
	assert(getmetatable(author) == person_mt, 'author is not a person')

	self.commit.author = author
end

---@param committer git.object.person
function object:commit_set_committer(committer)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'commit', 'object is not a commit')
	assert(getmetatable(committer) == person_mt, 'committer is not a person')

	self.commit.committer = committer
end

---@param message string
function object:commit_set_message(message)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'commit', 'object is not a commit')
	assert(type(message) == 'string', 'message is not a string')

	self.commit.message = message
end

---@param repository git.repository
---@param key sshkey.key
---@param namespace string|nil
function object:commit_sign(repository, key, namespace)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'commit', 'object is not a commit')

	return self.commit:sign(repository, key, namespace)
end

--- safe tag-specific methods

---@param obj git.object
function object:tag_set_object(obj)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'tag', 'object is not a tag')
	assert(getmetatable(obj) == object_mt, 'object is not an object')

	self.tag.object = obj
	self.tag.type = obj.kind
end

---@param name string
function object:tag_set_name(name)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'tag', 'object is not a tag')
	assert(type(name) == 'string', 'name is not a string')

	self.tag.name = name
end

---@param tagger git.object.person
function object:tag_set_tagger(tagger)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'tag', 'object is not a tag')
	assert(getmetatable(tagger) == person_mt, 'tagger is not a person')

	self.tag.tagger = tagger
end

---@param message string
function object:tag_set_message(message)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'tag', 'object is not a tag')
	assert(type(message) == 'string', 'message is not a string')

	self.tag.message = message
end

---@param repository git.repository
---@param key sshkey.key
---@param namespace string|nil
function object:tag_sign(repository, key, namespace)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'tag', 'object is not a tag')

	return self.tag:sign(repository, key, namespace)
end

--- safe tree-specific methods

---@param name string
---@param obj git.object
function object:tree_add_file(name, obj)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'tree', 'object is not a tree')
	assert(type(name) == 'string', 'name is not a string')
	assert(getmetatable(obj) == object_mt, 'object is not an object')

	self.tree:add_file(name, obj)
end

---@param name string
function object:tree_remove_file(name)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'tree', 'object is not a tree')
	assert(type(name) == 'string', 'name is not a string')

	self.tree:remove_file(name)
end

---@param name string
---@return git.object|nil
function object:tree_get_file(name)
	assert(self.kind == 'tree', 'object is not a tree')
	assert(type(name) == 'string', 'name is not a string')

	return self.tree:get_file(name)
end

--- safe blob-specific methods

---@param data string
function object:blob_set(data)
	assert(not self.stored, 'object is already stored')
	assert(self.kind == 'blob', 'object is not a blob')
	assert(type(data) == 'string', 'data is not a string')

	self.blob = data
end

---@return string
function object:blob_get()
	assert(self.kind == 'blob', 'object is not a blob')

	return self.blob
end

return object
