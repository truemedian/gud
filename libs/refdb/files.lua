local fs = require('fs')

---@class git.refdb.files 
---@field repository_dir string
local refdb_files = {}
local refdb_files = {__index = refdb_files}

---@param repository_dir string
function refdb_files.load(repository_dir)
    return setmetatable({repository_dir = assert(repository_dir, 'missing repository directory')}, refdb_files)
end

--- Reads an prefixed reference. Must begin with `refs/`.
---@param ref string
function refdb_files:read(ref)
    assert(ref:sub(1, 5) == 'refs/', 'reference must start with refs/')
    assert(ref:find('../', 1, true) == nil, 'reference cannot contain extraneous path components')

    local path = self.repository_dir .. '/' .. ref
    if not fs.accessSync(path) then
    end
end

--- Reads an unprefixed reference. May be either a tag or a branch head.
---@param ref string
function refdb_files:read_any(ref)
    assert(ref:find('../', 1, true) == nil, 'reference cannot contain extraneous path components')

    return self:read('refs/heads/' .. ref) or self:read('refs/tags/' .. ref)
end

return refdb_files
