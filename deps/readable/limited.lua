local class = import("class")
local Readable = import("base.lua")

---@class luvit.readable.Limited : luvit.readable.Base
---@field protected source luvit.readable.Base # the source stream to read from
---@field protected remaining integer # number of bytes remaining to read
---
--- A readable stream that reads from another readable stream and limits the amount of data read.
local LimitedReadable = class("readable.Limited", Readable)

---@protected
---@param source luvit.readable.Base # the source stream to read from
---@param limit integer # maximum number of bytes to read from the source stream
function LimitedReadable:init(source, limit)
	Readable.init(self)
	self.source = source
	self.remaining = limit
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer # a hint of how many bytes the caller would like to have available
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function LimitedReadable:fill(count, timeout)
	count = math.min(count, self.remaining)

	local chunk, err = self.source:readAtMost(count, timeout)
	if err == "timeout" then
		return 0, true
	elseif err then
		self.error = err
		return 0
	end

	if chunk then
		local n = #chunk
		self.remaining = self.remaining - n
		self.read_buffer:write(chunk)

		if self.remaining == 0 then
			self.ended = true
		end

		return n
	else
		self.ended = true
		return 0
	end
end

return LimitedReadable
