local fs = require('fs')
local miniz = require('miniz')

local common = require('git/common')
local object = require('git/object')

---@class git.odb.backend.loose : git.odb.backend
---@field objects_dir string
local backend_loose = {}
local backend_loose_mt = { __index = backend_loose }

---@param objects_dir string
---@param oid git.oid
local function oid_path(objects_dir, oid)
	return objects_dir .. '/' .. oid:sub(1, 2) .. '/' .. oid:sub(3)
end

---@param odb git.odb
---@param objects_dir string
function backend_loose.load(odb, objects_dir)
	return setmetatable({ objects_dir = assert(objects_dir, 'missing objects directory') }, backend_loose_mt)
end

function backend_loose:init()
	if not fs.accessSync(self.objects_dir) then
		fs.mkdirSync(self.objects_dir)
	end
end

---@param odb git.odb
---@param oid git.oid
---@return git.object|nil, nil|string
function backend_loose:read(odb, oid)
	local path = oid_path(self.objects_dir, oid)
	if not fs.accessSync(path) then
		-- fail early if the object doesn't exist
		return nil, 'object not found in database'
	end

	local deflated, read_err = common.read_file(path)
	if not deflated then
		if read_err and read_err:sub(1, 7) == 'ENOENT:' then
			return nil, 'object not found in database'
		else
			return nil, read_err
		end
	end

	local inflated = miniz.inflate(deflated, 1)
	local kind, size, after = inflated:match('^(%w+) (%d+)%z()')
	if not kind then
		return nil, 'invalid object header'
	end

	local data = inflated:sub(after)
	assert(#data == tonumber(size), 'invalid object size')

	local obj = object.from_raw(kind, data, oid)
	odb:_cache_object(oid, obj)
	return obj
end

---@param odb git.odb
---@param oid git.oid
---@return git.object.kind|nil, number|string
function backend_loose:read_header(odb, oid)
	local obj = self:read(odb, oid)
	if not obj then
		return nil, 'object not found in database'
	end

	return obj.kind, #obj.data
end

---@param odb git.odb
---@param oid git.oid
---@return boolean, nil|string
function backend_loose:exists(odb, oid)
	local path = oid_path(self.objects_dir, oid)
	return fs.accessSync(path)
end

---@param odb git.odb
function backend_loose:refresh(odb) end

---@param obj git.object
---@return boolean, nil|string
function backend_loose:write(obj)
	local path = oid_path(self.objects_dir, obj.oid)
	local tmp = path .. '.tmp'
	local deflated = miniz.deflate(obj.kind .. ' ' .. #obj.raw .. '\0' .. obj.raw, 0x1000 + 4095)

	local success, err = common.write_file(tmp, deflated)
	if not success then
		fs.unlinkSync(tmp)
		return false, err
	end

	success, err = fs.renameSync(tmp, path)
	if not success then
		fs.unlinkSync(tmp)
		return false, err
	end

	return true
end

return backend_loose
