---@class git.odb.backend
local backend = {}

---@param odb git.odb
---@param oid git.oid
---@return git.object|nil, nil|string
function backend:read(odb, oid)
	return nil, 'object not found in database'
end

---@param odb git.odb
---@param oid git.oid
---@return git.object.kind|nil, number|string
function backend:read_header(odb, oid)
	return nil, 'object not found in database'
end

---@param odb git.odb
---@param oid git.oid
---@return boolean, nil|string
function backend:exists(odb, oid)
	return false
end

function backend:refresh() end

---@param oid git.oid
---@param data string
---@param kind git.object.kind
---@return boolean, nil|string
function backend:write(oid, data, kind)
	return false
end
