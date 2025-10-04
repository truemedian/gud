local luv = require("luv")

local class = import("class")
local Writable = import("base.lua")
local timer = import("timer")
local utility = import("utility")

local assertresume = utility.assertresume

---@class luvit.writable.Stream : luvit.writable.Base
---@field private stream userdata # a libuv stream (e.g. a tcp or pipe handle)
---@field private write_timeout luvit.Timer # a libuv timer for write timeouts
---
--- A writable stream that writes to a libuv stream.
local StreamWritable = class("writable.Stream", Writable)

---@protected
function StreamWritable:init(stream)
	Writable.init(self)
	self.stream = stream
	self.write_timeout = timer.Timer()
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function StreamWritable:drain(extra, timeout)
	local thread, main = coroutine.running()
	if main then
		-- short path for synchronous writes on the main thread, allowed but not recommended
		local ok, err = luv.write(self.stream, { self.write_buffer:read():tostring(), extra })
		if not ok then
			self.error = err
			return 0
		end
		return #self.write_buffer + #extra
	end

	local req, err = luv.write(self.stream, { self.write_buffer:read():tostring(), extra }, function(err)
		if timeout then
			self.write_timeout:stop()
		end

		if err then
			self.error = err
			return assertresume(thread, 0)
		end

		assertresume(thread, #self.write_buffer + #extra)
	end)

	-- if we couldn't even start the write, return the error
	if not req then
		self.error = err
		return 0
	end

	if timeout then
		self.write_timeout:delayed(timeout, function()
			luv.cancel(req)
			return assertresume(thread, 0, true)
		end)
	end

	return coroutine.yield()
end

--- Finish writing. This will flush any remaining data in the write buffer.
---
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if all data was flushed, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function StreamWritable:finish(timeout)
	local flush_ok, flush_err = Writable.finish(self, timeout)
    if not flush_ok then
        return false, flush_err
    end

	local thread = coroutine.running()
	local req, err = luv.shutdown(self.stream, function(err)
		if err then
			self.error = err
		end

		if timeout then
			assert(luv.timer_stop(self.write_timeout))
		end

		return assertresume(thread, not err, err)
	end)

	if not req then
		self.error = err
		return false, err
	end

	if timeout then
		assert(luv.timer_start(self.write_timeout, timeout, 0, function()
			luv.cancel(req)
			return assertresume(thread, false, "timeout")
		end))
	end

	return coroutine.yield()
end
