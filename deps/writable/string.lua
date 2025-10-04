local class = import("class")
local buffer = import("buffer")
local Writable = import("base.lua")

---@class luvit.writable.String: luvit.writable.Base
---@field out_buffer luvit.buffer
---
--- A writable stream that writes to a string buffer.
local StringWritable = class("writable.String", Writable)

---@protected
function StringWritable:init()
	Writable.init(self)
	self.out_buffer = buffer.new()
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function StringWritable:drain(extra, timeout)
	self.out_buffer:write(self.write_buffer:read())
	self.out_buffer:write(extra)
	return #self.write_buffer + #extra
end

--- Get the contents of the string buffer and clear it.
---
---@return string # the contents of the string buffer
---@nodiscard
function StringWritable:out()
	return self.out_buffer:read():tostring()
end

return StringWritable
