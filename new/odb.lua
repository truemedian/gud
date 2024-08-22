---@class git.odb
---@field oid_type git.oid_type
---@field backends git.odb.backend[]
local odb = {}

--- Read an object from the database.
---@param oid git.oid
---@return git.object|nil, string|nil
function odb:read(oid)
    for i = 1, #self.backends do
        local object = self.backends[i]:read(oid)
        if object then return object end
    end

    return nil, 'object not found in database'
end

--- Read an the header of object from the database.
---@param oid git.oid
---@return git.object.kind|nil, number|string
function odb:read_header(oid)
    for i = 1, #self.backends do
        local kind, size = self.backends[i]:read_header(oid)
        if kind and size then return kind, size end
    end

    return nil, 'object not found in database'
end

--- Determine if an object exists in the database.
---@param oid git.oid
---@return boolean
function odb:exists(oid)
    for i = 1, #self.backends do if self.backends[i]:exists(oid) then return true end end

    return false
end

--- Refresh any cached indexes stored in the database. This is necessary when
--- the database is being used by more than one process.
function odb:refresh() for i = 1, #self.backends do self.backends[i]:refresh() end end

--- Write an object to the database. The first backend that successfully writes
--- the object will be used.
---@param data string
---@param kind git.object.kind
function odb:write(data, kind)
    local oid = self.oid_type:digest(data, kind)
    for i = 1, #self.backends do
        if self.backends[i]:write(oid, data, kind) then
            return oid -- write succeeded, return the oid that was written
        end
    end

    return nil, 'could not write object to database'
end
