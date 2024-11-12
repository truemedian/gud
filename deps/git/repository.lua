local fs = require('fs')

local object = require('git/object')
local odb = require('git/odb')
local oid = require('git/oid')
local refdb = require('git/refdb/files')

local odb_loose = require('git/odb/loose')
local odb_pack = require('git/odb/pack')

local common = require('git/common')

---@class git.repository
---@field oid git.oid_type
---@field odb git.odb
---@field refdb git.refdb.files
---@field repository_dir string
local repository = {}
local repository_mt = { __index = repository }

function repository.new(repository_dir)
	local my_oid = oid.new('sha1')
	local my_odb = odb.new(my_oid)

	local my_refdb = refdb.new(repository_dir)

	return setmetatable({
		repository_dir = assert(repository_dir, 'missing repository directory'),
		oid = my_oid,
		odb = my_odb,
		refdb = my_refdb,
	}, repository_mt)
end

local default_config = [[
[core]
  repositoryformatversion = 1
  filemode = true
  bare = true]]

function repository:init()
	if not fs.accessSync(self.repository_dir) then
		assert(fs.mkdirSync(self.repository_dir))
	end

	if not fs.accessSync(self.repository_dir .. '/HEAD') then
		assert(common.write_file(self.repository_dir .. '/HEAD', 'ref: refs/heads/master'))
	end

	if not fs.accessSync(self.repository_dir .. '/config') then
		assert(common.write_file(self.repository_dir .. '/config', default_config))
	end

	self.refdb:init()
end

function repository:init_loose()
	local objects_dir = self.repository_dir .. '/objects'
	local my_loose = odb_loose.load(self.odb, objects_dir)

	my_loose:init()
	my_loose:refresh(self.odb)
	self.odb:add_backend(my_loose)
end

function repository:init_packed()
	local objects_dir = self.repository_dir .. '/objects'
	local my_packed = odb_pack.load(self.odb, objects_dir)

	my_packed:init()
	my_packed:refresh(self.odb)
	self.odb:add_backend(my_packed)
end

--- Return an object from the repository.
---@param oid_hash git.oid
---@return git.object|nil, string|nil
function repository:load(oid_hash)
	local obj, err = self.odb:read(oid_hash)
	if not obj then
		return nil, err
	end

	local decoded
	decoded, err = obj:decode(self)
	if not decoded then
		return nil, err
	end

	return obj
end

--- Determine if an object exists in the repository.
---@param oid_hash git.oid
---@return boolean
function repository:has(oid_hash)
	return self.odb:exists(oid_hash)
end

--- Resolve a reference to an object.
---@param ref string
---@return git.object|nil, string|nil
function repository:fetch_reference(ref)
	local oid_hash
	if ref:sub(1, 5) == 'refs/' then
		oid_hash = self.refdb:read(ref)
	else
		oid_hash = self.refdb:read_any(ref)
	end

	if oid_hash then
		return self:load(oid_hash)
	end

	return nil, 'reference ' .. ref .. ' not found in repository'
end

--- Update a reference to an object.
---@param ref string
---@param obj git.object
function repository:update_reference(ref, obj)
	local recoded, err = obj:recode(self)
	if not recoded then
		return false, err
	end

	return self.refdb:write(ref, obj.oid)
end

--- Update a reference to an object.
---@param ref string
---@return boolean, string|nil
function repository:remove_reference(ref)
	return self.refdb:delete(ref)
end

--- Add an object to the repository. If the object already exists, it will not be added again.
---@param obj git.object
---@return git.oid|nil, string|nil
function repository:store(obj)
	local recoded, err = obj:recode(self)
	if not recoded then
		return nil, err
	end

	if self:has(obj.oid) then
		obj.stored = true
		return obj.oid
	end

	if obj.kind == 'commit' then
		if not obj.commit.tree.stored then
			return nil, 'commit object has unstored tree'
		end

		for _, parent in ipairs(obj.commit.parents) do
			if not parent.stored then
				return nil, 'commit object has unstored parent'
			end
		end
	elseif obj.kind == 'tag' then
		if not obj.tag.object.stored then
			return nil, 'tag object has unstored object'
		end
	elseif obj.kind == 'tree' then
		for _, entry in ipairs(obj.tree.files) do
			if not entry.object.stored then
				return nil, 'tree object has unstored object'
			end
		end
	end

	local new_oid, write_err = self.odb:write(obj)
	if not new_oid then
		return nil, write_err
	end

	obj.stored = true
	return new_oid
end

--- Add multiple objects to the repository.
---@param ... git.object
---@return boolean, string|nil
function repository:store_all(...)
	for i = 1, select('#', ...) do
		local obj = select(i, ...)
		local success, err = self:store(obj)
		if not success then
			return false, err
		end
	end

	return true
end

return repository
