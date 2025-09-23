local luv = require("luv")
local buffer = require("buffer")

local function make_wait()
	local thread = coroutine.running()

	return function(...)
		local success, err = coroutine.resume(thread, ...)
		if not success then
			error(debug.traceback(thread, err))
		end
	end
end

local source = {}

-- #region source.null

---@class luvit.stream.source.null : luvit.stream.source
---
--- A source that always returns nil.
source.null = {}
source.null.__index = source.null

--- Create a new null source.
---
---@return luvit.stream.source.null
function source.null.new()
	return source.null
end

--- Read an item from the source.
---
---@return string|nil item, string|nil err
function source.null:read()
	return nil
end

--- End the source, no more items will be read.
---
---@return boolean success, string|nil err
function source.null:finish()
	return true
end

-- #endregion
-- #region source.string

---@class luvit.stream.source.string : luvit.stream.source
---@field buffer luvit.buffer
---
--- A source that reads from a string.
source.string = {}
source.string.__index = source.string

--- Create a new string source.
---
---@param str string The string to read from.
---@return luvit.stream.source.string
function source.string.new(str)
	local self = setmetatable({ buffer = buffer.new() }, source.string)
	self.buffer:set(str)
	return self
end

--- Read an item from the source.
---
---@return string|nil item, string|nil err
function source.string:read()
	if #self.buffer == 0 then
		return nil
	end

	return self.buffer:read()
end

--- End the source, no more items will be read.
---
---@return boolean success, string|nil err
function source.string:finish()
	self.buffer:free()
	return true
end

-- #endregion
-- #region source.table

---@class luvit.stream.source.table : luvit.stream.source
---@field table string[]
---@field index integer
---
--- A source that reads from a table of strings.
source.table = {}
source.table.__index = source.table

--- Create a new table source.
---
---@param tbl string[] The table to read from.
---@return luvit.stream.source.table
function source.table.new(tbl)
	return setmetatable({ table = tbl, index = 1 }, source.table)
end

--- Read an item from the source.
---
---@return string|nil item, string|nil err
function source.table:read()
	if self.index > #self.table then
		return nil
	end

	local item = self.table[self.index]
	self.index = self.index + 1
	return item
end

--- End the source, no more items will be read.
---
---@return boolean success, string|nil err
function source.table:finish()
	return true
end

-- #endregion
-- #region source.uv_file

---@class luvit.stream.source.uv_file : luvit.stream.source
---@field fd integer
---
--- A source that reads from a file descriptor using libuv.
source.uv_file = {}
source.uv_file.__index = source.uv_file

--- Create a new file source.
---
---@param fd integer The file descriptor to read from.
---@return luvit.stream.source.uv_file
function source.uv_file.new(fd)
	return setmetatable({ fd = fd }, source.uv_file)
end

--- Read an item from the source.
---
---@return string|nil item, string|nil err
function source.uv_file:read()
	local req, err = luv.uv_fs_read(self.fd, 8192, -1, make_wait())
	if not req then
		return nil, err
	end

	local data
	err, data = coroutine.yield()
	if err then
		return nil, err
	elseif #data == 0 then
		return nil
	end

	return data
end

--- End the source, no more items will be read.
---
---@return boolean success, string|nil err
function source.uv_file:finish()
	return true
end

-- #endregion
-- #region source.uv_stream

---@class luvit.stream.source.uv_stream : luvit.stream.source
---@field stream uv_stream_t
---@field buffer luvit.buffer
---
--- A source that reads from a uv stream.
source.uv_stream = {}
source.uv_stream.__index = source.uv_stream

--- Create a new stream source.
---
---@param stream uv_stream_t The uv stream to read from.
---@return luvit.stream.source.uv_stream
function source.uv_stream.new(stream)
	local self = setmetatable({ stream = stream, buffer = buffer.new() }, source.uv_stream)
end

--- Read an item from the source.
---
---@return string|nil item, string|nil err
function source.uv_stream:read()
	
end

--- End the source, no more items will be read.
---
---@return boolean success, string|nil err
function source.uv_stream:finish()
	return true
end

-- #endregion

return source
