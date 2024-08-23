local miniz = require('miniz')
local fs = require('fs')

local object = require('../object.lua')

---@class git.odb.backend.loose : git.odb.backend
---@field objects_dir string
local backend_loose = {}
local backend_loose_mt = {__index = backend_loose}

---@param objects_dir string
---@param oid git.oid
local function oid_path(objects_dir, oid) return objects_dir .. '/' .. oid:sub(1, 2) .. '/' .. oid:sub(3) end

---@param objects_dir string
function backend_loose.load(objects_dir)
    return setmetatable({
        objects_dir = assert(objects_dir, 'missing objects directory'),
    }, backend_loose_mt)
end

---@param oid git.oid
---@return git.object|nil, string|nil
function backend_loose:read(oid)
    local path = oid_path(self.objects_dir, oid)
    if not fs.accessSync(path) then
        -- fail early if the object doesn't exist
        return nil, 'object not found in database'
    end

    local deflated, err = fs.readFileSync(path)
    if err then return nil, err end

    local inflated = miniz.inflate(deflated, 1)
    local kind, size, after = inflated:match('^(%w+) (%d+)%z()')
    if not kind then return nil, 'invalid object header' end

    local data = inflated:sub(after)
    assert(#data == tonumber(size), 'invalid object size')
    local obj = object.create {kind = kind, data = data}

    return obj
end

---@param oid git.oid
---@return git.object.kind|nil, number|string
function backend_loose:read_header(oid)
    local obj = self:read(oid)
    if not obj then return nil, 'object not found in database' end

    return obj.kind, #obj.data
end

---@param oid git.oid
---@return boolean, string|nil
function backend_loose:exists(oid)
    local path = oid_path(self.objects_dir, oid)
    return fs.accessSync(path)
end

function backend_loose:refresh() end

---@param oid git.oid
---@param data string
---@param kind git.object.kind
---@return boolean, string|nil
function backend_loose:write(oid, data, kind)
    local path = oid_path(self.objects_dir, oid)
    local tmp = path .. '.tmp'
    local deflated = miniz.deflate(kind .. ' ' .. #data .. '\0' .. data, 0x1000 + 4095)

    local success, err = fs.writeFileSync(tmp, deflated)
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
