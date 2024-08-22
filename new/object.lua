
---@alias git.object.kind 'commit'|'tree'|'blob'|'tag'

---@class git.object
---@field kind git.object.kind
---@field data string
local object = {}