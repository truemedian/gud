local luv = require("luv")

local class = import("class")
local Readable = import("base.lua")
local timer = import("timer")
local utility = import("utility")

local assertresume = utility.assertresume

---@class luvit.readable.Stream : luvit.readable.Base
---@field private stream userdata # a libuv stream (e.g. a tcp or pipe handle)
---@field private read_timeout luvit.Timer # a libuv timer for read timeouts
---
--- A readable stream that reads from a libuv stream.
local StreamReadable = class("readable.Stream", Readable)

---@protected
---@param stream userdata # a libuv stream (e.g. a tcp or pipe handle)
function StreamReadable:init(stream)
	Readable.init(self)
	self.stream = stream
	self.read_timeout = timer.Timer()
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer # a hint of how many bytes the caller would like to have available
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function StreamReadable:fill(count, timeout)
	local thread, main = coroutine.running()
	assert(not main, "readable.Stream cannot be used from the main thread")
	local amt_read = 0

	local ok, err = luv.read_start(self.stream, function(err, chunk)
		if chunk then
			amt_read = amt_read + #chunk
			self.read_buffer:write(chunk)
		else
			self.ended = true
		end

		if err then
			self.error = err
		end

		if err or amt_read >= count or chunk == nil then
			luv.read_stop(self.stream)
			if timeout then
				self.read_timeout:stop()
			end

			return assertresume(thread, amt_read)
		end
	end)

	if not ok then
		self.error = err
		return 0
	end

	if timeout then
		self.read_timeout:delayed(timeout, function()
			luv.read_stop(self.stream)
			return assertresume(thread, amt_read, true)
		end)
	end

	return coroutine.yield()
end

return StreamReadable