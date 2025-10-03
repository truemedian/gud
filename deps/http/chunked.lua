local readable = require("stream/readable.lua")
local writable = require("stream/writable.lua")

local chunked = {}

-- #region chunked.readable

---@class luvit.http.chunked.readable : luvit.stream.readable
---@field private source luvit.stream.readable
---@field private first boolean
---@field private remaining integer
---
--- A readable stream that reads chunked HTTP data from another readable stream.
chunked.readable = {}
chunked.readable.__index = chunked.readable

for k, v in pairs(readable) do
	chunked.readable[k] = v
end

--- Create a new chunked readable stream.
---
---@param source luvit.stream.readable the source readable stream
---@return luvit.http.chunked.readable stream
---@nodiscard
function chunked.readable.new(source)
	local self = setmetatable({
		source = source,
		remaining = 0,
		first = true,
	}, chunked.readable)
	self:init()

	return self
end

--- Request for the stream to fill its internal buffer with at least `count` more bytes.
---
---@protected
---@param count integer a hint of how many bytes the caller would like to have available
---@return integer count number of new bytes available in the internal buffer
---@nodiscard
function chunked.readable:fill(count)
	if self.remaining == 0 then
		if self.first then
			self.first = false
		else
			-- Consume the trailing \r\n after the previous chunk
			local line, err = self.source:readLine(2)
			if err then
				self.error = err
				return 0
			elseif #line ~= 0 then
				self.error = "invalid chunk"
				return 0
			end
		end

		local line, err = self.source:readLine(128):tostring()
		if err then
			self.error = err
			return 0
		elseif not line then
			self.error = "unexpected end of stream"
			return 0
		end

		local size = line:match("^([0-9a-fA-F]+)")
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

	local chunk, read_err = self.source:readAtMost(self.remaining)
	if read_err then
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

---@class luvit.http.chunked.writable : luvit.stream.writable
---@field private dest luvit.stream.writable
---
--- A writable stream that writes chunked HTTP data to another writable stream.
chunked.writable = {}
chunked.writable.__index = chunked.writable

for k, v in pairs(writable) do
	chunked.writable[k] = v
end

--- Create a new chunked writable stream.
---
---@param dest luvit.stream.writable the destination writable stream
---@return luvit.http.chunked.writable stream
---@nodiscard
function chunked.writable.new(dest)
	local self = setmetatable({
		dest = dest,
	}, chunked.writable)
	self:init()
	return self
end

--- Write as much data as possible from the write buffer and the optional extra data to the underlying stream.
---
---@protected
---@param extra string additional data to write after the buffered data
---@return integer number of bytes written from the write buffer and extra data
---@return string|nil error if an error occurred during writing
---@nodiscard
function chunked.writable:drain(extra)
	local buffered = self.write_buffer:read():tostring()

	local ok, err = self.dest:write(string.format("%x\r\n", #buffered + #extra))
	if not ok then
		self.error = err
		return 0, err
	end

	ok, err = self.dest:write(buffered)
	if not ok then
		self.error = err
		return 0
	end

	if #extra > 0 then
		ok, err = self.dest:write(extra)
		if not ok then
			self.error = err
			return 0
		end
	end

	return #self.write_buffer + #extra
end

--- Finish writing. This will flush any remaining data in the write buffer.
---@return boolean
---@return string|nil
function chunked.writable:finish()
	if self.error then
		return false, self.error
	end

	local ok, err = self.dest:write("0\r\n\r\n")
	if not ok then
		return false, err
	end

	if #self.write_buffer > 0 then
		ok, err = self:flush()
		if not ok then
			return false, err
		end
	end

	return self.dest:finish()
end

return chunked
