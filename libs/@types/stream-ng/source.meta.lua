---@meta

---@class luvit.stream.source
local source = {}
source.__index = source

--- Read an item from the source.
---
---@return string|nil item, string|nil err
function source:read() end

--- End the source, no more items will be read.
---
---@return boolean success, string|nil err
function source:finish() end
