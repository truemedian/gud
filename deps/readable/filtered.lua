local class = import("class")
local Readable = import("base.lua")

---@alias luvit.readable.Filtered.fn fun(data: string|nil): data: string|nil, err: string|nil

---@class luvit.readable.Filtered : luvit.readable.Base
---@field protected source luvit.readable.Base # the source stream to read from
---@field protected filter luvit.readable.Filtered.fn # the filter function to apply to the data
---
--- A readable stream that reads from another readable stream and applies a filter function to the data.
local FilteredReadable = class("readable.Filtered", Readable)

---@protected
---@param source luvit.readable.Base # the source stream to read from
---@param filter luvit.readable.Filtered.fn # the filter function to apply to the data
function FilteredReadable:init(source, filter)
	Readable.init(self)
	self.source = source
	self.filter = filter
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer # a hint of how many bytes the caller would like to have available
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function FilteredReadable:fill(count, timeout)
	-- read in a chunk, we ignore the count hint here because we don't know the expansion ratio of the filter function
	local chunk, read_err = self.source:readAtMost(Readable.chunk_size, timeout)
	if read_err == "timeout" then
		return 0, true
	elseif read_err then
		self.error = read_err
		return 0
	end

	-- apply the filter, we don't check if chunk is nil because that indicates eof to the filter
	local filtered, filter_err = self.filter(chunk)
	if filter_err then
		self.error = filter_err
		return 0
	end

	if filtered then
		self.read_buffer:write(filtered)
		return #filtered
	else
		-- only end the stream when the filter indicates eof
		self.ended = true
		return 0
	end
end

return FilteredReadable