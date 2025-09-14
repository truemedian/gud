---@meta

---@class luvit.stream.sink
local sink = {}
sink.__index = sink

--- Write items to the sink.
---
---@param ... string
---@return boolean success, string|nil err
function sink:write(...) end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@return boolean success, string|nil err
function sink:flush() end

--- End the sink, no more items will be written.
---
---@return boolean success, string|nil err
function sink:finish() end
