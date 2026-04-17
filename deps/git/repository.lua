local class = require('class')

local fs = require('fs')
local path = require('path')

local blob = require('git/object/blob')
local commit = require('git/object/commit')
local database = require('git/database')
local oid_type = require('git/oid_type')
local refs = require('git/refs')
local tag = require('git/object/tag')
local tree = require('git/object/tree')

--- @class std.git.repository : std.class<std.git.repository>
--- @field git_dir string
--- @field oid_type table
--- @field database std.git.database
--- @field refs std.git.refs
local repository = class.new('std.git.repository')

--- @param git_dir string
--- @param options? { bare: boolean|nil, oid: 'sha1'|'sha256'|nil }
function repository:init(git_dir, options)
	assert(type(git_dir) == 'string' and #git_dir > 0, 'git_dir must be a non-empty string')

	options = options or {}
	self.git_dir = git_dir
	self.oid_type = oid_type.new(options.oid or 'sha1')
	self.database = database.new(git_dir, self.oid_type)
	self.refs = refs.new(git_dir, self.oid_type)
end

--- @param git_dir string
--- @param options? { bare: boolean|nil, oid: 'sha1'|'sha256'|nil }
--- @return std.git.repository
function repository.open(git_dir, options)
	return repository.new(git_dir, options)
end

--- @return boolean
function repository:exists()
	if not fs.exists(self.git_dir) then
		return false
	end

	return fs.exists(self.database.objects_dir) and fs.exists(self.refs.refs_dir)
end

--- @return boolean|nil
--- @return string|nil err
function repository:initBare()
	local dirs = {
		self.git_dir,
		path.join(self.git_dir, 'objects'),
		path.join(self.git_dir, 'refs'),
		path.join(self.git_dir, 'refs', 'heads'),
		path.join(self.git_dir, 'refs', 'tags'),
		path.join(self.git_dir, 'refs', 'remotes'),
		path.join(self.git_dir, 'hooks'),
		path.join(self.git_dir, 'info'),
	}

	for i = 1, #dirs do
		local ok, err = fs.mkdirp(dirs[i])
		if not ok then
			return nil, err
		end
	end

	local head_path = path.join(self.git_dir, 'HEAD')
	if not fs.exists(head_path) then
		local ok, err = fs.writeFile(head_path, 'ref: refs/heads/main\n')
		if not ok then
			return nil, err
		end
	end

	local config_path = path.join(self.git_dir, 'config')
	if not fs.exists(config_path) then
		local config = '[core]\n\trepositoryformatversion = 0\n\tbare = true\n\tfilemode = true\n'
		local ok, err = fs.writeFile(config_path, config)
		if not ok then
			return nil, err
		end
	end

	return true
end

--- @param kind string
--- @param payload string
--- @return string|nil oid
--- @return string|nil err
--- @return boolean|nil already_exists
function repository:writeObject(kind, payload)
	return self.database:writeLoose(kind, payload)
end

--- @param oid std.git.oid
--- @return string|nil kind
--- @return string|nil payload
--- @return string|nil err
function repository:readObject(oid)
	return self.database:readLoose(oid)
end

--- @param oid std.git.oid
--- @return boolean
function repository:hasObject(oid)
	return self.database:exists(oid)
end

--- @param data string
--- @return std.git.oid|nil oid
--- @return string|nil err
function repository:writeBlob(data)
	return self:writeObject('blob', data)
end

--- @param oid std.git.oid
--- @return std.git.object.blob|nil
--- @return string|nil err
function repository:readBlob(oid)
	local kind, payload, err = self:readObject(oid)
	if not kind then
		return nil, err
	elseif payload == nil then
		return nil, 'missing object payload'
	elseif kind ~= 'blob' then
		return nil, 'object is not a blob'
	end

	return blob.parse(payload), nil
end

--- @param entries std.git.object.tree.entry[]
--- @return std.git.oid|nil oid
--- @return string|nil err
function repository:writeTree(entries)
	local payload, serialize_err = tree.new(entries):serialize(self.oid_type)
	if not payload then
		return nil, serialize_err
	end

	return self:writeObject('tree', payload)
end

--- @param oid std.git.oid
--- @return std.git.object.tree|nil
--- @return string|nil err
function repository:readTree(oid)
	local kind, payload, err = self:readObject(oid)
	if not kind then
		return nil, err
	elseif payload == nil then
		return nil, 'missing object payload'
	elseif kind ~= 'tree' then
		return nil, 'object is not a tree'
	end

	return tree.parse(payload, self.oid_type)
end

--- @param value std.git.object.commit
--- @return std.git.oid|nil oid
--- @return string|nil err
function repository:writeCommit(value)
	local payload, serialize_err = commit.new(value):serialize(self.oid_type)
	if not payload then
		return nil, serialize_err
	end

	return self:writeObject('commit', payload)
end

--- @param oid std.git.oid
--- @return std.git.object.commit|nil
--- @return string|nil err
function repository:readCommit(oid)
	local kind, payload, err = self:readObject(oid)
	if not kind then
		return nil, err
	elseif payload == nil then
		return nil, 'missing object payload'
	elseif kind ~= 'commit' then
		return nil, 'object is not a commit'
	end

	return commit.parse(payload, self.oid_type)
end

--- @param value std.git.object.tag
--- @return std.git.oid|nil oid
--- @return string|nil err
function repository:writeTag(value)
	local payload, serialize_err = tag.new(value):serialize(self.oid_type)
	if not payload then
		return nil, serialize_err
	end

	return self:writeObject('tag', payload)
end

--- @param oid std.git.oid
--- @return std.git.object.tag|nil
--- @return string|nil err
function repository:readTag(oid)
	local kind, payload, err = self:readObject(oid)
	if not kind then
		return nil, err
	elseif payload == nil then
		return nil, 'missing object payload'
	elseif kind ~= 'tag' then
		return nil, 'object is not a tag'
	end

	return tag.parse(payload, self.oid_type)
end

--- @param name string
--- @return std.git.oid|nil oid
--- @return string|nil err
function repository:resolveRef(name)
	return self.refs:resolve(name)
end

--- @param name string
--- @param oid std.git.oid
--- @return boolean success
--- @return string|nil err
function repository:updateRef(name, oid)
	return self.refs:update(name, oid)
end

--- @param name string
--- @param target string
--- @return boolean success
--- @return string|nil err
function repository:updateSymbolicRef(name, target)
	return self.refs:updateSymbolic(name, target)
end

--- @param prefix? string
--- @return table<string, std.git.oid>|nil
--- @return string|nil err
function repository:listRefs(prefix)
	return self.refs:list(prefix)
end

return repository
