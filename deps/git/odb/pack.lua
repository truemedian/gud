local fs = require('fs')

local backend_onepack = require('git/odb/one_pack')

---@class git.odb.backend.pack : git.odb.backend
---@field objects_dir string
---@field packs table<string, git.odb.backend.one_pack>
local backend_pack = {}
local backend_pack_mt = { __index = backend_pack }

---@param odb git.odb
---@param objects_dir string
---@return git.odb.backend.pack
function backend_pack.load(odb, objects_dir)
	local self = setmetatable({ objects_dir = assert(objects_dir, 'missing objects directory') }, backend_pack_mt)

	return self
end

function backend_pack:init()
	if not fs.accessSync(self.objects_dir) then
		assert(fs.mkdirSync(self.objects_dir))
	end

	if not fs.accessSync(self.objects_dir .. '/pack') then
		assert(fs.mkdirSync(self.objects_dir .. '/pack'))
	end
end

---@param odb git.odb
---@param oid git.oid
---@return git.object|nil, nil|string
function backend_pack:read(odb, oid)
	for _, pack in pairs(self.packs) do
		local obj = pack:read(odb, oid)
		if obj then
			return obj
		end
	end

	return nil, 'object not found in database'
end

---@param odb git.odb
---@param oid git.oid
---@return git.object.kind|nil, number|string
function backend_pack:read_header(odb, oid)
	for _, pack in pairs(self.packs) do
		local kind, size = pack:read_header(odb, oid)
		if kind then
			return kind, size
		end
	end

	return nil, 'object not found in database'
end

---@param odb git.odb
---@param oid git.oid
---@return boolean, nil|string
function backend_pack:exists(odb, oid)
	for _, pack in pairs(self.packs) do
		if pack:exists(odb, oid) then
			return true
		end
	end

	return false
end

---@param odb git.odb
function backend_pack:refresh(odb)
	self.packs = {}
	for name, kind in fs.scandirSync(self.objects_dir .. '/pack') do
		local hash = name:match('^pack%-(%x+)%.pack$')
		if hash and kind == 'file' then
			self.packs[hash] = assert(backend_onepack.load(odb, self.objects_dir, hash))
		end
	end
end

---@param obj git.object
---@return boolean, nil|string
function backend_pack:write(obj)
	return false
end

return backend_pack
