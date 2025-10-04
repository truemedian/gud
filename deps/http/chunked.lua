local class = import("class")
local Readable = import("readable").Base
local Writable = import("writable").Base

local chunked = {}

-- #region chunked.readable

---@class luvit.http.chunked.Readable : luvit.readable.Base
---@field private source luvit.readable.Base # the source readable stream
---@field private first boolean # whether or not this is the first chunk
---@field private remaining integer # number of bytes remaining in the current chunk
---
--- A readable stream that reads chunked HTTP data from another readable stream.
local ChunkedReadable = class("http.chunked.Readable", Readable)

---@protected
---@param source luvit.readable.Base the source readable stream
function ChunkedReadable:init(source)
	Readable.init(self)
	self.source = source
	self.first = true
	self.remaining = 0
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer # a hint of how many bytes the caller would like to have available
---@param timeout integer|nil # a timeout for individual read operations in milliseconds
---@return integer count # number of new bytes available in the internal buffer
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function ChunkedReadable:fill(count, timeout)
	if self.remaining == 0 then
		if self.first then
			self.first = false
		else
			-- Consume the trailing \r\n after the previous chunk
			local line, err = self.source:readLine(2, false, timeout)
			if err == "timeout" then
				return 0, true
			elseif err then
				self.error = err
				return 0
			elseif #line ~= 0 then
				self.error = "invalid chunk"
				return 0
			end
		end

		local line, err = self.source:readLine(128, false, timeout)
		if err == "timeout" then
			return 0, true
		elseif err then
			self.error = err
			return 0
		elseif not line then
			self.error = "unexpected end of stream"
			return 0
		end

		local size = line:tostring():match("^([0-9a-fA-F]+)")
		if not size then
			self.error = "invalid chunk"
			return 0
		end

		self.remaining = tonumber(size) or 0
		if self.remaining == 0 then
			self.ended = true
			return 0
		end
	end

	local chunk, read_err = self.source:readAtMost(self.remaining, timeout)
	if read_err == "timeout" then
		return 0, true
	elseif read_err then
		self.error = read_err
		return 0
	end

	if chunk then
		local n = #chunk
		self.remaining = self.remaining - n
		self.read_buffer:write(chunk)
		return n
	else
		self.error = "unexpected end of stream"
		return 0
	end
end

-- #endregion
-- #region chunked.writable

---@class luvit.http.chunked.Writable : luvit.writable.Base
---@field private dest luvit.writable.Base
---
--- A writable stream that writes chunked HTTP data to another writable stream.
local ChunkedWritable = class("http.chunked.Writable", Writable)

---@protected
---@param dest luvit.writable.Base the destination writable stream
function ChunkedWritable:init(dest)
	Writable.init(self)
	self.dest = dest
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string # additional data to write after the buffered data
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return integer number # of bytes written from the write buffer and extra data
---@return boolean|nil timeout # whether or not a timeout occurred
---@nodiscard
function ChunkedWritable:drain(extra, timeout)
	local buffered = self.write_buffer:read():tostring()

	local ok, err = self.dest:write(string.format("%x\r\n", #buffered + #extra), timeout)
	if err == "timeout" then
		return 0, true
	elseif not ok then
		self.error = err
		return 0
	end

	ok, err = self.dest:write(buffered, timeout)
	if err == "timeout" then
		return 0, true
	elseif not ok then
		self.error = err
		return 0
	end

	if #extra > 0 then
		ok, err = self.dest:write(extra, timeout)
		if err == "timeout" then
			return 0, true
		elseif not ok then
			self.error = err
			return 0
		end
	end

	return #self.write_buffer + #extra
end

--- Finish writing. This will flush any remaining data in the write buffer.
---
---@param timeout integer|nil # a timeout for individual write operations in milliseconds
---@return boolean success # true if all data was flushed, false if an error occurred
---@return string|nil error # if an error occurred
---@nodiscard
function ChunkedWritable:finish(timeout)
	local flush_ok, flush_err = Writable.finish(self, timeout)
	if not flush_ok then
		return false, flush_err
	end

	local ok, err = self.dest:write("0\r\n\r\n", timeout)
	if err == "timeout" then
		return false, "timeout"
	elseif not ok then
		self.error = err
		return false, err
	end

	return self.dest:finish(timeout)
end

return chunked
