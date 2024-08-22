---@class git.odb.backend
local backend = {}

---@param oid git.oid
---@return git.object|nil, string|nil
function backend:read(oid)
    return nil, 'object not found in database'
end

---@param oid git.oid
---@return git.object.kind|nil, number|string
function backend:read_header(oid)
    return nil, 'object not found in database'
end

---@param oid git.oid
---@return boolean, string|nil
function backend:exists(oid)
    return false
end

function backend:refresh() end

---@param oid git.oid
---@param data string
---@param kind git.object.kind
---@return boolean, string|nil
function backend:write(oid, data, kind)
    return false
end
