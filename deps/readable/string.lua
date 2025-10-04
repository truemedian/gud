local class = import("class")
local Readable = import("base.lua")

---@class luvit.readable.String : luvit.readable.Base
---
--- A readable stream that reads from a string.
local StringReadable = class("readable.String", Readable)

---@protected
---@param str string # the string to read from
function StringReadable:init(str)
	Readable.init(self, 0)
	self.read_buffer:set(str)
	self.read_eof = true
end

return StringReadable
