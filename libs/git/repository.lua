---@class git.repository
---@field odb git.odb
---@
local repository = {}

--- Return an object from the repository.
---@param oid git.oid
function repository:load(oid)
	local o = assert(self.odb:read(oid))

	return o
end

--- Determine if an object exists in the repository.
---@param oid git.oid
function repository:has(oid)
	return self.odb:exists(oid)
end

--- Resolve a reference to an object.
---@param ref string
function repository:resolve(ref)


end
