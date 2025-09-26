---@meta

---@alias luvit.stream.sink.item string|luvit.slice
---@alias luvit.stream.sink.iovec luvit.stream.sink.item[]
---@alias luvit.stream.sink.success fun(success: boolean, err: string|nil)

---@class luvit.stream.sink
local sink = {}
sink.__index = sink

--- Write items to the sink.
---
---@param items luvit.stream.sink.iovec
---@param callback luvit.stream.sink.success
function sink:writev(items, callback) end

--- Write an item to the sink.
---
---@param item luvit.stream.sink.item
---@param callback luvit.stream.sink.success
function sink:write(item, callback) end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@param callback luvit.stream.sink.success
function sink:flush(callback) end

--- End the sink, no more items will be written.
---
---@param callback luvit.stream.sink.success
function sink:finish(callback) end
