local luv = require("luv")
local buffer = require("buffer")

local function assertResume(thread, ...)
	local success, err = coroutine.resume(thread, ...)
	if not success then
		error(debug.traceback(thread, err), 0)
	end
end

---@class luvit.stream.writable
---@field protected error string|nil
---@field protected write_buffer luvit.buffer
---@field protected high_water_mark integer
---@field protected corked boolean
local writable = {}

function writable:drain(extra)
	return #self.write_buffer + #extra
end

--- Flush the write buffer to the underlying stream. This will repeatedly call `:drain` until all buffered data is
--- consumed.
---
---@param extra? string
---@return boolean
---@return string|nil
function writable:flush(extra)
	if self.error then
		return false, self.error
	end

	extra = extra or ""
	while true do
		local drained = self:drain(extra)
		if self.error then
			return false, self.error
		end

		if drained == #self.write_buffer + #extra then
			-- all data consumed
			self.write_buffer:reset()
			return true
		elseif drained > #self.write_buffer then
			-- all buffer consumed, some of extra
			self.write_buffer:reset()
			extra = extra:sub(drained - #self.write_buffer + 1)
			return true
		elseif drained > 0 then
			-- some of buffer consumed, none of extra
			self.write_buffer:skip(drained)
		end
	end
end

--- Write data to the stream.
---@param data string
---@return boolean
---@return string|nil
function writable:write(data)
	if self.error then
		return false, self.error
	end

	if self.corked or #self.write_buffer + #data <= self.high_water_mark then
		self.write_buffer:write(data)
		return true
	end

	return self:flush(data)
end

--- Cork the stream. This will prevent writes from being flushed until uncorked.
function writable:cork()
	self.corked = true
end

--- Uncork the stream. This will flush the write buffer if it exceeds the high water mark.
---@return boolean
---@return string|nil
function writable:uncork()
	self.corked = false

	if #self.write_buffer > self.high_water_mark then
		return self:flush("")
	end

	return true
end

--- Finish writing. This will flush any remaining data in the write buffer.
---@return boolean
---@return string|nil
function writable:finish()
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		return self:flush("")
	end

	return true
end

-- #region writable.string

---@class luvit.stream.writable.string: luvit.stream.writable
---@field out_buffer luvit.buffer
---
--- A writable stream that writes to a string buffer.
writable.string = {}
writable.string.__index = writable.string

function writable.string.new()
	local self = setmetatable({
		out_buffer = buffer.new(),
		write_buffer = buffer.new(),
		high_water_mark = 4 * 1024,
		corked = false,
	}, writable.string)
	return self
end

for k, v in pairs(writable) do
	writable.string[k] = v
end

function writable.string:drain(extra)
	self.out_buffer:write(self.write_buffer:read())
	self.out_buffer:write(extra)
	return #self.write_buffer + #extra
end

function writable.string:out()
	return self.out_buffer:read():tostring()
end

-- #endregion
-- #region writable.stream

---@class luvit.stream.writable.stream : luvit.stream.writable
---@field private stream userdata
---
--- A writable stream that writes to a libuv stream.
writable.stream = {}
writable.stream.__index = writable.stream

function writable.stream.new(stream)
	local self = setmetatable({
		stream = stream,
		write_buffer = buffer.new(),
		high_water_mark = 4 * 1024,
		corked = false,
	}, writable.stream)
	return self
end

for k, v in pairs(writable) do
	writable.stream[k] = v
end

function writable.stream:drain(extra)
	local thread = coroutine.running()

	luv.uv_write(self.stream, { self.write_buffer:read():tostring(), extra }, function(err)
		if err then
			self.error = err
			return assertResume(thread, 0)
		end

		assertResume(thread, #self.write_buffer + #extra)
	end)

	return coroutine.yield()
end

function writable.stream:finish()
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		local success, err = self:flush("")
		if not success then
			return false, err
		end
	end

	local thread = coroutine.running()

	luv.uv_shutdown(self.stream, function(err)
		if err then
			self.error = err
			return assertResume(thread, false, err)
		end

		return assertResume(thread, true)
	end)

	return coroutine.yield()
end

-- #endregion
-- #region writable.filter

---@class luvit.stream.writable.filter : luvit.stream.writable
---@field private filter fun(data: string|nil): data: string|nil, err: string|nil
---@field private dest luvit.stream.writable
---
--- A writable stream that writes to another writable stream and applies a filter function to the data.
writable.filter = {}
writable.filter.__index = writable.filter

function writable.filter.new(dest, filter)
	return setmetatable({
		dest = dest,
		filter = filter,
		write_buffer = buffer.new(),
		high_water_mark = 4 * 1024,
		corked = false,
	}, writable.filter)
end

for k, v in pairs(writable) do
	writable.filter[k] = v
end

function writable.filter:drain(extra)
	local buffered = self.write_buffer:read():tostring()

	local filtered, filt_err = self.filter(buffered)
	if not filtered then
		self.error = filt_err or "filter error"
		return 0
	end

	local success, err = self.dest:write(filtered)
	if not success then
		self.error = err
		return 0
	end

	return #self.write_buffer
end

function writable.filter:finish()
	if self.error then
		return false, self.error
	end

	if #self.write_buffer > 0 then
		local success, err = self:flush("")
		if not success then
			return false, err
		end
	end

	local filtered, filt_err = self.filter(nil)
	if not filtered then
		self.error = filt_err
		return not self.error, self.error
	end

	local success, err = self.dest:write(filtered)
	if not success then
		self.error = err
		return false, err
	end

	return self.dest:finish()
end

-- #endregion

return writable
