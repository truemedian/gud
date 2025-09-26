---@meta

---@alias luvit.stream.source.item string
---@alias luvit.stream.source.response fun(item: luvit.stream.source.item|nil, err: string|nil)
---@alias luvit.stream.source.success fun(success: boolean, err: string|nil)

---@class luvit.stream.source
local source = {}
source.__index = source

--- Read an item from the source.
---
---@param max_size number The maximum size of the item to read. If `0`, the source may return an item of any size.
---@param callback luvit.stream.source.response
function source:read(max_size, callback) end

--- End the source, no more items will be read.
---
---@param callback luvit.stream.source.success
function source:finish(callback) end
