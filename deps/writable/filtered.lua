local class = import("class")
local Writable = import("base.lua")

---@class luvit.writable.Filtered : luvit.writable.Base
---@field private dest luvit.writable.Base # the destination writable stream
---@field private filter fun(data: string|nil): data: string|nil, err: string|nil # the filter function to apply to the data
---
--- A writable stream that writes to another writable stream and applies a filter function to the data.
local FilteredWritable = class("writable.Filtered", Writable)

---@protected
---@param dest luvit.writable.Base the destination writable stream
---@param filter fun(data: string|nil): data: string|nil, err: string|nil the filter function to apply to the data
function FilteredWritable:init(dest, filter)
	Writable.init(self)
	self.dest = dest
	self.filter = filter
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function FilteredWritable:drain(extra, timeout)
	local buffered = self.write_buffer:read():tostring()

	local filtered, filter_err = self.filter(buffered)
	if filter_err then
		self.error = filter_err
		return 0
	end

	if filtered then
		local ok, err = self.dest:write(filtered, timeout)
		if err == "timeout" then
			return 0, true
		elseif not ok then
			self.error = self.dest.error
			return 0
		end
	end

	return #self.write_buffer
end

--- Finish writing. This will flush any remaining data in the write buffer.
---
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if all data was flushed, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function FilteredWritable:finish(timeout)
	local flush_ok, flush_err = Writable.finish(self, timeout)
	if not flush_ok then
		return false, flush_err
	end

	repeat
		-- apply the filter with nil to indicate end of stream until it returns nil
		local filtered, filter_err = self.filter(nil)
		if filter_err then
			self.error = filter_err
			return false, self.error
		end

		if filtered then
			local ok, err = self.dest:write(filtered, timeout)
			if err == "timeout" then
				return false, "timeout"
			elseif not ok then
				self.error = err
				return false, err
			end
		end
	until not filtered

	return self.dest:finish(timeout)
end
