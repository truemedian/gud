
---@alias git.object.kind 'commit'|'tree'|'blob'|'tag'

---@class git.object
---@field kind git.object.kind
---@field data string.buffer
local object = {}
local object_mt = {__index = object}

function object.create(o)
    return setmetatable(o, object_mt)
end

return object