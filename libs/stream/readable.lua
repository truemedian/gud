local luv = require("luv")
local buffer = require("buffer")

local function assertResume(thread, ...)
	local success, err = coroutine.resume(thread, ...)
	if not success then
		error(debug.traceback(thread, err), 0)
	end
end

---@class luvit.stream.readable
---@field protected error string|nil
---@field protected ended boolean
---@field protected read_buffer luvit.buffer
local readable = {}

--- Request for the stream to fill its internal buffer with at least `count` more bytes. The number of new bytes
--- available in the internal buffer after the fill operation is returned. If the stream has reached the end, the
--- returned value may be less than `count`.
---@param count integer
---@return integer
function readable:fill(count)
	return 0
end

--- Peek at the contents of the internal buffer without consuming any data.
---
---@return luvit.slice
function readable:peek()
	return self.read_buffer:peek()
end

function readable:fillAtLeast(count)
	if self.ended or self.error then
		return
	end

	local written = 0
	repeat
		written = written + self:fill(count - written)
	until written >= count or self.ended or self.error
end

--- Read exactly `bytes` bytes from the stream. If the stream ends before `bytes` bytes can be read, the data will be
--- `nil` and an error message will be the second return value.
---
---@param bytes integer
---@return string|nil, string|nil
function readable:readExact(bytes)
	local available = #self.read_buffer

	if available < bytes then
		local needed = bytes - available

		self:fillAtLeast(needed)
		if self.ended or self.error then
			return nil, self.error
		end
	end

	return self.read_buffer:read(bytes):tostring()
end

--- Read at least `bytes` bytes from the stream. If the stream ends before `bytes` bytes can be read, the data will be
--- `nil` and an error message will be the second return value.
---
---@param bytes integer
---@return string|nil, string|nil
function readable:readAtLeast(bytes)
	local available = #self.read_buffer
	if available < bytes then
		local needed = bytes - available

		self:fillAtLeast(needed)
		if self.ended or self.error then
			return nil, self.error
		end
	end

	return self.read_buffer:read():tostring()
end

--- Read at most `bytes` bytes from the stream. If the stream ends before any bytes can be read, the data will be
--- `nil` and an error message will be the second return value.
---
---@param bytes integer
---@return string|nil, string|nil
function readable:readAtMost(bytes)
	local available = #self.read_buffer

	if available == 0 then
		self:fillAtLeast(1)

		if self.ended or self.error then
			return nil, self.error
		end
	end

	local count = math.min(bytes, available)
	return self.read_buffer:read(count):tostring()
end

-- #region readable.string

---@class luvit.stream.readable.string : luvit.stream.readable
readable.string = {}
readable.string.__index = readable.string

for k, v in pairs(readable) do
	readable.string[k] = v
end

function readable.string.new(str)
	local self = setmetatable({ read_buffer = buffer.new(), ended = true }, readable.string)
	self.read_buffer:set(str)
	return self
end

-- #endregion
-- #region readable.stream

---@class luvit.stream.readable.stream : luvit.stream.readable
---@field private stream userdata
---
--- A readable stream that reads from a libuv stream.

readable.stream = {}
readable.stream.__index = readable.stream

for k, v in pairs(readable) do
	readable.stream[k] = v
end

function readable.stream.new(stream)
	return setmetatable({ stream = stream, read_buffer = buffer.new(), ended = false }, readable.stream)
end

function readable.stream:fill(count)
	local thread = coroutine.running()
	local written = 0

	luv.uv_read_start(self.stream, function(err, chunk)
		if chunk then
			written = written + #chunk
			self.read_buffer:write(chunk)
		else
			self.ended = true
		end

		if err then
			self.error = err
			return assertResume(thread, written)
		elseif written >= count or chunk == nil then
			luv.uv_read_stop(self.stream)
			return assertResume(thread, written)
		end
	end)

	return coroutine.yield()
end

-- #endregion
-- #region readable.filter

---@class luvit.stream.readable.filter : luvit.stream.readable
---@field private filter fun(data: string|nil): data: string|nil, err: string|nil
---@field private source luvit.stream.readable
---
--- A readable stream that reads from another readable stream and applies a filter function to the data.
readable.filter = {}
readable.filter.__index = readable.filter

function readable.filter.new(source, filter)
	return setmetatable({
		source = source,
		filter = filter,
		read_buffer = buffer.new(),
		ended = false,
	}, readable.filter)
end

for k, v in pairs(readable) do
	readable.filter[k] = v
end

function readable.filter:fill(count)
	local chunk, read_err = self.source:readAtMost(4 * 1024)
	if read_err then
		self.error = read_err
		return 0
	end

	local filtered, filter_err = self.filter(chunk)
	if filter_err then
		self.error = filter_err
		return 0
	end

	if filtered then
		self.read_buffer:write(filtered)
		return #filtered
	else
		self.ended = true
		return 0
	end
end

-- #endregion
-- #region readable.

return readable
