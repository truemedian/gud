local luv = require("luv")
local buffer = import("buffer")
local class = import("class")

local utility = import("utility")
local assertresume = utility.assertresume

-- #region readable

---@class luvit.stream.readable : luvit.class
---@field protected error string|nil
---@field protected read_eof boolean
---@field protected read_buffer luvit.buffer
local readable = class("readable")
readable.chunk_size = 16384

---@protected
---@param size? integer # initial size of the internal buffer
function readable:init(size)
	self.error = nil
	self.read_eof = false
	self.read_buffer = buffer.new(size)
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer # a hint of how many bytes the caller would like to have available
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function readable:fill(count, timeout)
	return 0
end

--- Peek at the contents of the internal buffer without consuming any data.
---
---@return luvit.slice # the contents of the internal buffer
---@nodiscard
function readable:peek()
	return self.read_buffer:peek()
end

--- Fills the internal buffer with at least `count` more bytes, unless the stream ends or an error occurs.
---
---@param count integer # the minimum number of new bytes to fill
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@nodiscard
function readable:fillAtLeast(count, timeout)
	if self.read_eof or self.error then
		return 0
	end

	local written = 0
	repeat
		local new, timed_out = self:fill(count - written, timeout)
		written = written + new
	until written >= count or self.read_eof or self.error or timed_out

	return written
end

--- Read exactly `bytes` bytes from the stream. Will return `nil` if the stream ends before `bytes` bytes can be read.
---
---@param bytes integer # the exact number of bytes to read
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return string|nil data # either `nil` (if not enough data is available), or a string with exactly `bytes` bytes
---@return string|nil error # if an error occurred, or "timeout" if the timeout was reached
---@nodiscard
function readable:readExact(bytes, timeout)
	local available = #self.read_buffer

	if available < bytes then
		local needed = bytes - available
		local new = self:fillAtLeast(needed, timeout)

		if self.error or (self.read_eof and new < needed) then
			return nil, self.error or (not self.read_eof and "timeout" or nil)
		end
	end

	return self.read_buffer:read(bytes):tostring()
end

--- Read at least `bytes` bytes from the stream. Will return `nil` if the stream ends before `bytes` bytes can be read.
---
---@param bytes integer # the minimum number of bytes to read
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return string|nil data # either `nil` (if not enough data is available), or a string with at least `bytes` bytes
---@return string|nil error # if an error occurred, or "timeout" if the timeout was reached
---@nodiscard
function readable:readAtLeast(bytes, timeout)
	local available = #self.read_buffer
	if available < bytes then
		local needed = bytes - available
		local new = self:fillAtLeast(needed, timeout)

		if self.error or (self.read_eof and new < needed) then
			return nil, self.error or (not self.read_eof and "timeout" or nil)
		end
	end

	return self.read_buffer:read():tostring()
end

--- Read at most `bytes` bytes from the stream. Will return `nil` if the stream has ended and no more data is available.
---
---@param bytes integer # the maximum number of bytes to read
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return string|nil data # either `nil` (if no data is available), or a string with at most `bytes` bytes
---@return string|nil error # if an error occurred, or "timeout" if the timeout was reached
---@nodiscard
function readable:readAtMost(bytes, timeout)
	local available = #self.read_buffer

	if available == 0 then
		local new = self:fillAtLeast(1, timeout)
		available = #self.read_buffer

		if self.error or (self.read_eof and new < 1) then
			return nil, self.error or (not self.read_eof and "timeout" or nil)
		end
	end

	local count = math.min(bytes, available)
	return self.read_buffer:read(count):tostring()
end

--- Continuously read from this stream and write to the given writable stream until this stream ends or an error occurs.
---
---@param writable luvit.stream.writable # a writable stream to pump data into
---@param finish boolean # if `true`, the writable stream will be finished after the pump is done
---@param timeout integer|nil # a timeout for individual read and write operations in milliseconds
---@param chunk_size? integer # maximum number of bytes to read from this stream at a time
---@return boolean success # `true` if the pump completed successfully
---@return string|nil error # if an error occurred
---@nodiscard
function readable:pump(writable, finish, timeout, chunk_size)
	chunk_size = chunk_size or readable.chunk_size

	while true do
		local chunk, err = self:readAtMost(chunk_size, timeout)
		if err then
			return false, err
		elseif not chunk then
			break
		end

		local ok
		ok, err = writable:write(chunk, timeout)
		if not ok then
			return false, err
		end
	end

	if finish then
		local ok, err = writable:finish(timeout)
		if not ok then
			return false, err
		end
	end

	return true
end

--- Read from the stream until "\r\n" or "\n".
---
---@param max_size? number # maximum number of bytes to read, defaults to infinity
---@param include_delimiter? boolean # whether or not the line ending should be included in the returned data
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return luvit.slice|nil data # the line that was read, or `nil` if the stream ended before a line ending was found
---@return string|nil error # if an error occurred, or "line too long" if the line exceeded `max_size`
---@nodiscard
function readable:readLine(max_size, include_delimiter, timeout)
	max_size = max_size or math.huge

	local pos = 1
	while true do
		local idx = self.read_buffer:peek():find("\n", pos)

		if idx then
			if idx > max_size then
				return nil, "line too long"
			end

			if include_delimiter then
				return self.read_buffer:read(idx)
			else
				local data = self.read_buffer:peek(idx - 1)
				if data:byte(-1) == 13 then
					data = data:sub(1, -2)
				end

				self.read_buffer:skip(idx)
				return data
			end
		elseif #self.read_buffer >= max_size then
			return nil, "line too long"
		end

		pos = #self.read_buffer + 1
		local new = self:fillAtLeast(1, timeout)

		if self.read_eof or self.error then
			return nil, self.error
		elseif new < 1 then
			-- no error but nothing was read, must be timeout
			return nil, "timeout"
		end
	end
end

--- Read from the stream until the given delimiter is found.
---
---@param delimiter string # the delimiter to read until
---@param max_size? number # maximum number of bytes to read, defaults to infinity
---@param include_delimiter? boolean # whether or not the delimiter should be included in the returned data
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return luvit.slice|nil data # the data that was read, or `nil` if the stream ended before the delimiter was found
---@return string|nil error # if an error occurred, or "delimiter not found" if the delimiter was not found before `max_size` bytes were read
---@nodiscard
function readable:readUntil(delimiter, max_size, include_delimiter, timeout)
	max_size = max_size or math.huge

	local pos = 1
	while true do
		local idx = self.read_buffer:peek():find(delimiter, pos)

		if idx then
			if idx > max_size then
				return nil, "delimiter not found"
			end

			if include_delimiter then
				return self.read_buffer:read(idx + #delimiter - 1)
			else
				self.read_buffer:skip(#delimiter)
				return self.read_buffer:read(idx - 1)
			end
		elseif #self.read_buffer >= max_size then
			return nil, "delimiter not found"
		end

		pos = #self.read_buffer - #delimiter + 2
		local new = self:fillAtLeast(1, timeout)

		if self.read_eof or self.error then
			return nil, self.error
		elseif new < 1 then
			-- no error but nothing was read, must be timeout
			return nil, "timeout"
		end
	end
end

local function complement(value, radix)
	return value >= radix / 2 and value - radix or value
end

--- Read a single 8 bit unsigned integer from the stream.
---
---@param timeout integer|nil # a timeout for an individual read operation in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred, or "timeout" if the timeout was reached
---@nodiscard
function readable:readUInt8(timeout)
	local data, err = self:readExact(1, timeout)
	if not data then
		return nil, err
	end

	return (string.byte(data, 1))
end

--- Read a single 8 bit signed integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function readable:readInt8(timeout)
	local data, err = self:readUInt8(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x100)
end

--- Read a single 16 bit unsigned little-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function readable:readUInt16LE(timeout)
	local data, err = self:readExact(2, timeout)
	if not data then
		return nil, err
	end

	local a, b = string.byte(data, 1, 2)
	return b * 0x100 + a
end

--- Read a single 16 bit unsigned big-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function readable:readUInt16BE(timeout)
	local data, err = self:readExact(2, timeout)
	if not data then
		return nil, err
	end

	local a, b = string.byte(data, 1, 2)
	return a * 0x100 + b
end

--- Read a single 16 bit signed little-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function readable:readInt16LE(timeout)
	local data, err = self:readUInt16LE(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x10000)
end

--- Read a single 16 bit signed big-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function readable:readInt16BE(timeout)
	local data, err = self:readUInt16BE(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x10000)
end

--- Read a single 32 bit unsigned little-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function readable:readUInt32LE(timeout)
	local data, err = self:readExact(4, timeout)
	if not data then
		return nil, err
	end

	local a, b, c, d = string.byte(data, 1, 4)
	return d * 0x1000000 + c * 0x10000 + b * 0x100 + a
end

--- Read a single 32 bit unsigned big-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function readable:readUInt32BE(timeout)
	local data, err = self:readExact(4, timeout)
	if not data then
		return nil, err
	end

	local a, b, c, d = string.byte(data, 1, 4)
	return a * 0x1000000 + b * 0x10000 + c * 0x100 + d
end

--- Read a single 32 bit signed little-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function readable:readInt32LE(timeout)
	local data, err = self:readUInt32LE(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x100000000)
end

--- Read a single 32 bit signed big-endian integer from the stream.
---
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer|nil data # the integer that was read
---@return string|nil error # if an error occurred
---@nodiscard
function readable:readInt32BE(timeout)
	local data, err = self:readUInt32BE(timeout)
	if not data then
		return nil, err
	end

	return complement(data, 0x100000000)
end

-- #endregion
-- #region readable.string

---@class luvit.stream.readable.string : luvit.stream.readable
---
--- A readable stream that reads from a string.
readable.string = class("readable.string", readable)

---@protected
---@param str string # the string to read from
function readable.string:init(str)
	self.__base.init(self, 0)
	self.read_buffer:set(str)
	self.read_eof = true
end

-- #endregion
-- #region readable.file

---@class luvit.stream.readable.file : luvit.stream.readable
---@field private fd integer # file descriptor to read from
---@field private position integer # current position in the file
---@field private read_timeout userdata # a libuv timer for read timeouts
---
--- A readable stream that reads from a file descriptor.
readable.file = class("readable.file", readable)

---@protected
---@param fd integer # file descriptor to read from
function readable.file:init(fd)
	self.__base.init(self)
	self.fd = fd
	self.position = 0
	---@diagnostic disable-next-line: assign-type-mismatch
	self.read_timeout = assert(luv.new_timer())
end

--- Open a file and return a readable stream for it.
---
---@param path string # path to the file to open
---@param flags? string # defaults to "r"
---@param mode? integer # defaults to 0o666
---@return luvit.stream.readable.file|nil stream # the readable stream, or `nil` if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function readable.file.open(path, flags, mode)
	local fd, err = luv.fs_open(path, flags or "r", mode or 438)
	if not fd then
		return nil, err
	end

	return readable.file(fd)
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer # a hint of how many bytes the caller would like to have available
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function readable.file:fill(count, timeout)
	local thread, main = coroutine.running()
	if main then
		local chunk, err = luv.fs_read(self.fd, count, self.position)

		if chunk and #chunk > 0 then
			self.position = self.position + #chunk
			self.read_buffer:write(chunk)
			return #chunk
		elseif err then
			self.error = err
			return 0
		else
			self.ended = true
		end
	end

	local yielded, nread = false, nil

	count = math.max(count, readable.chunk_size)
	local req, err = luv.fs_read(self.fd, count, self.position, function(err, chunk)
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
			if timeout then
				assert(luv.timer_stop(self.read_timeout))
			end

			return assertresume(thread, nread)
		end
	end)

	if not req then
		self.error = err
		return 0
	elseif nread then
		return nread
	end

	if timeout then
        assert(luv.timer_start(self.read_timeout, timeout, 0, function()
			luv.cancel(req)
			yielded = false
			return assertresume(thread, 0, true)
		end))
	end

	yielded = true
	return coroutine.yield()
end

-- #endregion
-- #region readable.stream

---@class luvit.stream.readable.stream : luvit.stream.readable
---@field private stream userdata # a libuv stream (e.g. a tcp or pipe handle)
---@field private read_timeout userdata # a libuv timer for read timeouts
---
--- A readable stream that reads from a libuv stream.
readable.stream = class("readable.stream", readable)

---@protected
---@param stream userdata # a libuv stream (e.g. a tcp or pipe handle)
function readable.stream:init(stream)
	self.__base.init(self)
	self.stream = stream
	---@diagnostic disable-next-line: assign-type-mismatch
	self.read_timeout = assert(luv.new_timer())
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer # a hint of how many bytes the caller would like to have available
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function readable.stream:fill(count, timeout)
	local thread, main = coroutine.running()
	assert(not main, "readable.stream cannot be used from the main thread")
	local nread = 0

	local ok, err = luv.read_start(self.stream, function(err, chunk)
		if chunk then
			nread = nread + #chunk
			self.read_buffer:write(chunk)
		else
			self.ended = true
		end

		if err then
			self.error = err
			if timeout then
				assert(luv.timer_stop(self.read_timeout))
			end

			return assertresume(thread, nread)
		elseif nread >= count or chunk == nil then
			luv.read_stop(self.stream)
			if timeout then
				assert(luv.timer_stop(self.read_timeout))
			end

			return assertresume(thread, nread)
		end
	end)

	if not ok then
		self.error = err
		return 0
	end

	if timeout then
		assert(luv.timer_start(self.read_timeout, timeout, 0, function()
			luv.read_stop(self.stream)
			return assertresume(thread, nread, true)
		end))
	end

	return coroutine.yield()
end

-- #endregion
-- #region readable.filter

---@class luvit.stream.readable.filter : luvit.stream.readable
---@field private source luvit.stream.readable # the source stream to read from
---@field private filter fun(data: string|nil): data: string|nil, err: string|nil # the filter function to apply to the data
---
--- A readable stream that reads from another readable stream and applies a filter function to the data.
readable.filter = class("readable.filter", readable)

---@protected
---@param source luvit.stream.readable # the source stream to read from
---@param filter fun(data: string|nil): data: string|nil, err: string|nil # the filter function to apply to the data
function readable.filter:init(source, filter)
	self.__base.init(self)
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
function readable.filter:fill(count, timeout)
	local chunk, read_err = self.source:readAtMost(readable.chunk_size, timeout)
	if read_err == "timeout" then
		return 0, true
	elseif read_err then
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
-- #region readable.limited

---@class luvit.stream.readable.limited : luvit.stream.readable
---@field private source luvit.stream.readable # the source stream to read from
---@field private remaining integer # number of bytes remaining to read
---
--- A readable stream that reads from another readable stream and limits the amount of data read.
readable.limited = class("readable.limited", readable)

---@protected
---@param source luvit.stream.readable # the source stream to read from
---@param limit integer # maximum number of bytes to read from the source stream
function readable.limited:init(source, limit)
	self.__base.init(self)
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
function readable.limited:fill(count, timeout)
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

		if self.remaining <= 0 then
			self.ended = true
		end

		return n
	else
		self.ended = true
		return 0
	end
end

-- #endregion

return readable
