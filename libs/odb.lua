---@class git.odb
---@field oid_type git.oid_type
---@field backends git.odb.backend[]
---@field cache table<git.oid, git.object>
local odb = {}

function odb.new(oid_type)
    return setmetatable({oid_type = oid_type, backends = {}, cache = {}}, {__index = odb})
end

--- Add a backend to the database.
---@param backend git.odb.backend
function odb:add_backend(backend)
    table.insert(self.backends, backend)
end

--- Read an object from the database.
---@param oid git.oid
---@return git.object|nil, string|nil
function odb:read(oid)
    if self.cache[oid] then
        return self.cache[oid]
    end

    for i = 1, #self.backends do
        local object = self.backends[i]:read(self, oid)
        if object then
            return object
        end
    end

    return nil, 'object ' .. oid .. ' not found in database'
end

--- Read an the header of object from the database.
---@param oid git.oid
---@return git.object.kind|nil, number|string
function odb:read_header(oid)
    if self.cache[oid] then
        local obj = self.cache[oid]
        return obj.kind, #obj.data
    end

    for i = 1, #self.backends do
        local kind, size = self.backends[i]:read_header(self, oid)
        if kind and size then
            return kind, size
        end
    end

    return nil, 'object ' .. oid .. ' not found in database'
end

--- Determine if an object exists in the database.
---@param oid git.oid
---@return boolean
function odb:exists(oid)
    if self.cache[oid] then
        return true
    end

    for i = 1, #self.backends do
        if self.backends[i]:exists(self, oid) then
            return true
        end
    end

    return false
end

--- Refresh any cached indexes stored in the database. This is necessary when
--- the database is being used by more than one process.
function odb:refresh()
    self.cache = {}

    for i = 1, #self.backends do
        self.backends[i]:refresh()
    end
end

--- Write an object to the database. The first backend that successfully writes
--- the object will be used.
---@param data string
---@param kind git.object.kind
---@return git.oid|nil, string|nil
function odb:write(data, kind)
    local oid = self.oid_type:digest(data, kind)

    for i = 1, #self.backends do
        if self.backends[i]:write(oid, data, kind) then
            -- write succeeded, return the oid that was written
            return oid
        end
    end

    return nil, 'could not write object ' .. oid .. ' to database'
end

function odb:_cache_object(oid, object)
    self.cache[oid] = object
end

return odb
