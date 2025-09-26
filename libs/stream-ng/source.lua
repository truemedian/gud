local luv = require("luv")
local buffer = require("buffer")
local miniz = require("miniz")

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
---@param max_size number The maximum size of the item to read. If `0`, the source may return an item of any size.
---@param callback luvit.stream.source.response
function source.null:read(max_size, callback)
	return callback(nil)
end

--- End the source, no more items will be read.
---
---@param callback luvit.stream.source.success
function source.null:finish(callback)
	return callback(true)
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
---@param max_size number The maximum size of the item to read. If `0`, the source may return an item of any size.
---@param callback luvit.stream.source.response
function source.string:read(max_size, callback)
	if #self.buffer == 0 then
		return callback(nil)
	end

	return callback(self.buffer:read(max_size):tostring())
end

--- End the source, no more items will be read.
---
---@param callback luvit.stream.source.success
function source.string:finish(callback)
	self.buffer:free()
	return callback(true)
end

-- #endregion
-- #region source.table

---@class luvit.stream.source.table : luvit.stream.source
---@field table string[]
---@field index integer
---@field offset integer
---
--- A source that reads from a table of strings.
source.table = {}
source.table.__index = source.table

--- Create a new table source.
---
---@param tbl string[] The table to read from.
---@return luvit.stream.source.table
function source.table.new(tbl)
	return setmetatable({ table = tbl, index = 1, offset = 1 }, source.table)
end

--- Read an item from the source.
---
---@param max_size number The maximum size of the item to read. If `0`, the source may return an item of any size.
---@param callback luvit.stream.source.response
function source.table:read(max_size, callback)
	if self.index > #self.table then
		return callback(nil)
	end

	local item = self.table[self.index]

	-- item fits within max_size
	if max_size == 0 or (#item - self.offset + 1) <= max_size then
		self.index = self.index + 1
		return callback(item:sub(self.offset))
	end

	-- item is larger than max_size
	local result = item:sub(self.offset, self.offset + max_size - 1)
	self.offset = self.offset + max_size
	return callback(result)
end

--- End the source, no more items will be read.
---
---@param callback luvit.stream.source.success
function source.table:finish(callback)
	return callback(true)
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
---@param max_size number The maximum size of the item to read. If `0`, the source may return an item of any size.
---@param callback luvit.stream.source.response
function source.uv_file:read(max_size, callback)
	local req, err = luv.uv_fs_read(self.fd, max_size, -1, function(err, data)
		if err then
			return callback(nil, err)
		elseif #data == 0 then
			return callback(nil)
		end

		return callback(data)
	end)

	if not req then
		return callback(nil, err)
	end
end

--- End the source, no more items will be read.
---
---@param callback luvit.stream.source.success
function source.uv_file:finish(callback)
	return callback(true)
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
	return setmetatable({ stream = stream, buffer = buffer.new() }, source.uv_stream)
end

--- Read an item from the source.
---
---@param max_size number The maximum size of the item to read. If `0`, the source may return an item of any size.
---@param callback luvit.stream.source.response
function source.uv_stream:read(max_size, callback)
	if #self.buffer > 0 then
		if max_size == 0 then
			max_size = #self.buffer
		end

		return callback(self.buffer:read(max_size):tostring())
	end

	local success, err = luv.uv_read_start(self.stream, function(err, data)
		if err then
			return callback(nil, err)
		elseif data == nil then
			return callback(nil)
		elseif #data <= max_size or max_size == 0 then
			return callback(data)
		end

		self.buffer:set(data)
		return callback(self.buffer:read(max_size):tostring())
	end)

	if not success then
		return callback(nil, err)
	end
end

--- End the source, no more items will be read.
---
---@param callback luvit.stream.source.success
function source.uv_stream:finish(callback)
	return callback(true)
end

-- #endregion
-- #region source.synchronize

---@class luvit.stream.source.sync
---@field source luvit.stream.source
---
--- A source that synchronizes another source
source.sync = {}
source.sync.__index = source.sync

--- Create a new synchronized source.
---
---@param source luvit.stream.source The source to synchronize.
---@return luvit.stream.source.sync
function source.sync.new(source)
	return setmetatable({ source = source }, source.sync)
end

--- Read an item from the source.
---
---@param max_size number The maximum size of the item to read. If `0`, the source may return an item of any size.
function source.sync:read(max_size)
	local co = coroutine.running()
	local data, err
	local yielded = false

	self.source:read(max_size, function(d, e)
		if yielded then
			return coroutine.resume(co, d, e)
		else
			data = d
			err = e
			yielded = true
		end
	end)

	if yielded then
		return data, err
	end

	yielded = true
	return coroutine.yield()
end

--- End the source, no more items will be read.
---
---@return boolean
function source.sync:finish()
	local co = coroutine.running()
	local success, err
	local yielded = false

	self.source:finish(function(s, e)
		if yielded then
			return coroutine.resume(co, s, e)
		else
			success = s
			err = e
			yielded = true
		end
	end)

	if yielded then
		return success, err
	end

	yielded = true
	return coroutine.yield()
end

-- #endregion
-- #region source.inflate

---@class luvit.stream.source.inflate : luvit.stream.source
---@field under luvit.stream.source
---@field inflater userdata
---@field buffer luvit.buffer
---
--- A source that decompresses items read from another source.
source.inflate = {}
source.inflate.__index = source.inflate

--- Create a new inflate source.
---
---@param under luvit.stream.source The source to read compressed items from.
---@return luvit.stream.source.inflate
function source.inflate.new(under)
	local inflater = miniz.new_inflater()
	return setmetatable({ under = under, inflater = inflater, buffer = buffer.new() }, source.inflate)
end

--- Read an item from the source.
---
---@param max_size number The maximum size of the item to read. If `0`, the source may return an item of any size.
---@param callback luvit.stream.source.response
function source.inflate:read(max_size, callback)
	if #self.buffer > 0 then
		if max_size == 0 then
			max_size = #self.buffer
		end

		return callback(self.buffer:read(max_size):tostring())
	end

	self.under:read(0, function(data, err)
		if err then
			return callback(nil, err)
		elseif data == nil then
			local chunk, infl_err = self.inflater:inflate("", "finish")
			if infl_err then
				return callback(nil, infl_err)
			elseif #chunk == 0 then
				return callback(nil)
			end

			self.buffer:set(chunk)
			return callback(self.buffer:read(max_size):tostring())
		end

		local chunk, infl_err = self.inflater:inflate(data)
		if infl_err then
			return callback(nil, infl_err)
		elseif #chunk == 0 then
			-- need more data to produce output
			return self:read(max_size, callback)
		elseif max_size == 0 or #chunk <= max_size then
			return callback(chunk)
		end

		self.buffer:set(chunk)
		return callback(self.buffer:read(max_size):tostring())
	end)
end

--- End the source, no more items will be read.
---
---@param callback luvit.stream.source.success
function source.inflate:finish(callback)
	self.buffer:free()
	return self.under:finish(callback)
end

-- #endregion

return source
