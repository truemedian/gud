local luv = require("luv")
local buffer = require("buffer")

local function assertResume(thread, ...)
	local success, err = coroutine.resume(thread, ...)
	if not success then
		error(debug.traceback(thread, err), 0)
	end
end

-- #region readable

---@class luvit.stream.readable
---@field protected error string|nil
---@field protected ended boolean
---@field protected read_buffer luvit.buffer
local readable = {}

--- Request for the stream to fill its internal buffer with at least `count` more bytes. The number of new bytes
--- available in the internal buffer after the fill operation is returned. If the stream has reached the end, the
--- returned value may be less than `count`.
---
---@param count integer
---@return integer count of new bytes available in the internal buffer
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
--- `nil`.
---
---@param bytes integer
---@return string|nil data
---@return string|nil error
function readable:readExact(bytes)
	local available = #self.read_buffer

	if available < bytes then
		local needed = bytes - available

		self:fillAtLeast(needed)
		available = #self.read_buffer

		if self.error or (self.ended and available < needed) then
			return nil, self.error
		end
	end

	return self.read_buffer:read(bytes):tostring()
end

--- Read at least `bytes` bytes from the stream. If the stream ends before `bytes` bytes can be read, the data will be
--- `nil`.
---
---@param bytes integer
---@return string|nil data
---@return string|nil error
function readable:readAtLeast(bytes)
	local available = #self.read_buffer
	if available < bytes then
		local needed = bytes - available

		self:fillAtLeast(needed)
		available = #self.read_buffer

		if self.error or (self.ended and available < needed) then
			return nil, self.error
		end
	end

	return self.read_buffer:read():tostring()
end

--- Read at most `bytes` bytes from the stream. If the stream ends before any bytes can be read, the data will be
--- `nil`.
---
---@param bytes integer
---@return string|nil data
---@return string|nil error
function readable:readAtMost(bytes)
	local available = #self.read_buffer

	if available == 0 then
		self:fillAtLeast(1)
		available = #self.read_buffer

		if self.error or (self.ended and available < 1) then
			return nil, self.error
		end
	end

	local count = math.min(bytes, available)
	return self.read_buffer:read(count):tostring()
end

--- Continuously read from this stream and write to the given writable stream until this stream ends or an error occurs.
--- If `finish` is `true`, the writable stream will be finished when this stream ends.
--- The optional `chunk_size` parameter controls the maximum number of bytes to read from this stream at a time.
---
---@param writable luvit.stream.writable
---@param finish boolean
---@param chunk_size? integer
---@return boolean success
---@return string|nil error
function readable:pump(writable, finish, chunk_size)
	chunk_size = chunk_size or (16 * 1024)

	while true do
		local chunk, err = self:readAtMost(chunk_size)
		if err then
			return false, err
		elseif not chunk then
			break
		end

		local ok, write_err = writable:write(chunk)
		if not ok then
			return false, write_err
		end
	end

	if finish then
		local ok, err = writable:finish()
		if not ok then
			return false, err
		end
	end

	return true
end

--- Read from the stream until "\r\n" or "\n". The line ending can optionally be included in the returned data. If the
--- stream ends or more than `max_size` bytes are available before the line ending is found, the data will be `nil`.
---
---@param max_size? number
---@param include_delimiter? boolean
---@return string|nil data
---@return string|nil error
function readable:readLine(max_size, include_delimiter)
	max_size = max_size or math.huge

	local pos = 1
	while true do
		local avail = self:peek()
		local idx = avail:find("\n", pos)

		if idx then
			if idx > max_size then
				return nil, "line too long"
			end

			if include_delimiter then
				return self.read_buffer:read(idx):tostring()
			else
				local data = self.read_buffer:peek(idx - 1)
				if data:byte(-1) == 10 then
					data = data:sub(1, -2)
				end

				local result = data:tostring()
				self.read_buffer:skip(idx)
				return result
			end
		end

		if self.ended or self.error then
			return nil, self.error
		elseif #avail >= max_size then
			return nil, "line too long"
		end

		pos = #avail + 1
		self:fillAtLeast(1)
	end
end

--- Read from the stream until the given delimiter is found. The delimiter can optionally be included in the returned
--- data. If the stream ends before the delimiter is found, the data will be `nil`.
---
---@param delimiter string
---@param max_size? number
---@param include_delimiter? boolean
---@return string|nil data
---@return string|nil error
function readable:readUntil(delimiter, max_size, include_delimiter)
	max_size = max_size or math.huge

	local pos = 1
	while true do
		local avail = self:peek()
		local idx = avail:find(delimiter, pos)

		if idx then
			if idx > max_size then
				return nil, "delimiter not found"
			end

			if include_delimiter then
				return self.read_buffer:read(idx + #delimiter - 1):tostring()
			else
				local result = self.read_buffer:read(idx - 1):tostring()
				self.read_buffer:skip(#delimiter)
				return result
			end
		end

		if self.ended or self.error then
			return nil, self.error
		elseif #avail >= max_size then
			return nil, "delimiter not found"
		end

		pos = #avail - #delimiter + 2
		self:fillAtLeast(1)
	end
end

local function complement(value, radix)
	return value >= radix / 2 and value - radix or value
end

--- Read a single 8 bit unsigned integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readUInt8()
	local data, err = self:readExact(1)
	if not data then
		return nil, err
	end

	local a = string.byte(data, 1)
	return a
end

--- Read a single 8 bit signed integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readInt8()
	local data, err = self:readUInt8()
	if not data then
		return nil, err
	end

	return complement(data, 0x100)
end

--- Read a single 16 bit unsigned little-endian integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readUInt16LE()
	local data, err = self:readExact(2)
	if not data then
		return nil, err
	end

	local a, b = string.byte(data, 1, 2)
	return b * 0x100 + a
end

--- Read a single 16 bit unsigned big-endian integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readUInt16BE()
	local data, err = self:readExact(2)
	if not data then
		return nil, err
	end

	local a, b = string.byte(data, 1, 2)
	return a * 0x100 + b
end

--- Read a single 16 bit signed little-endian integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readInt16LE()
	local data, err = self:readUInt16LE()
	if not data then
		return nil, err
	end

	return complement(data, 0x10000)
end

--- Read a single 16 bit signed big-endian integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readInt16BE()
	local data, err = self:readUInt16BE()
	if not data then
		return nil, err
	end

	return complement(data, 0x10000)
end

--- Read a single 32 bit unsigned little-endian integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readUInt32LE()
	local data, err = self:readExact(4)
	if not data then
		return nil, err
	end

	local a, b, c, d = string.byte(data, 1, 4)
	return d * 0x1000000 + c * 0x10000 + b * 0x100 + a
end

--- Read a single 32 bit unsigned big-endian integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readUInt32BE()
	local data, err = self:readExact(4)
	if not data then
		return nil, err
	end

	local a, b, c, d = string.byte(data, 1, 4)
	return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

--- Read a single 32 bit signed little-endian integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readInt32LE()
	local data, err = self:readUInt32LE()
	if not data then
		return nil, err
	end

	return complement(data, 0x100000000)
end

--- Read a single 32 bit signed big-endian integer from the stream.
---
---@return integer|nil data
---@return string|nil error
function readable:readInt32BE()
	local data, err = self:readUInt32BE()
	if not data then
		return nil, err
	end

	return complement(data, 0x100000000)
end

-- #endregion
-- #region readable.string

---@class luvit.stream.readable.string : luvit.stream.readable
readable.string = {}
readable.string.__index = readable.string

for k, v in pairs(readable) do
	readable.string[k] = v
end

--- Create a new readable stream for the given string.
---
---@param str string
---@return luvit.stream.readable.string stream
function readable.string.new(str)
	local self = setmetatable({ read_buffer = buffer.new(), ended = true }, readable.string)
	self.read_buffer:set(str)
	return self
end

-- #endregion
-- #region readable.file

---@class luvit.stream.readable.file : luvit.stream.readable
---@field private fd integer
---@field private position integer
---
--- A readable stream that reads from a file descriptor.
readable.file = {}
readable.file.__index = readable.file

for k, v in pairs(readable) do
	readable.file[k] = v
end

--- Create a new readable stream for the given file descriptor.
---
---@param fd integer
---@return luvit.stream.readable.file stream
function readable.file.new(fd)
	return setmetatable({ fd = fd, position = 0, read_buffer = buffer.new(), ended = false }, readable.file)
end

--- Open a file and return a readable stream for it.
---
---@param path string
---@param flags? string
---@param mode? integer
---@return luvit.stream.readable.file|nil stream
---@return string|nil error
function readable.file.open(path, flags, mode)
	local fd, err = luv.fs_open(path, flags or "r", mode or 438)
	if not fd then
		return nil, err
	end

	return (readable.file.new(fd))
end

function readable.file:fill(count)
	local thread = coroutine.running()
	local yielded, nread = false, nil

	count = math.max(count, 4096)

	luv.fs_read(self.fd, count, self.position, function(err, chunk)
		if chunk and #chunk > 0 then
			nread = #chunk
			self.position = self.position + #chunk
			self.read_buffer:write(chunk)
		else
			nread = 0
			self.ended = true
		end

		if err then
			self.error = err
		end

		if yielded then
			return assertResume(thread, nread)
		end
	end)

	if nread then
		return nread
	end

	yielded = true
	return coroutine.yield()
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

--- Create a new readable stream for the given libuv stream.
---
---@param stream userdata
---@return luvit.stream.readable.stream stream
function readable.stream.new(stream)
	return setmetatable({ stream = stream, read_buffer = buffer.new(), ended = false }, readable.stream)
end

function readable.stream:fill(count)
	local thread = coroutine.running()
	local nread = 0

	luv.read_start(self.stream, function(err, chunk)
		if chunk then
			nread = nread + #chunk
			self.read_buffer:write(chunk)
		else
			self.ended = true
		end

		if err then
			self.error = err
			return assertResume(thread, nread)
		elseif nread >= count or chunk == nil then
			luv.read_stop(self.stream)
			return assertResume(thread, nread)
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

for k, v in pairs(readable) do
	readable.filter[k] = v
end

function readable.filter.new(source, filter)
	return setmetatable({
		source = source,
		filter = filter,
		read_buffer = buffer.new(),
		ended = false,
	}, readable.filter)
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

return readable
