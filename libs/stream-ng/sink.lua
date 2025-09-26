local luv = require("luv")
local buffer = require("buffer")
local miniz = require("miniz")

local sink = {}

-- #region sink.null

---@class luvit.stream.sink.null : luvit.stream.sink
---
--- A sink that discards all written items.
sink.null = {}
sink.null.__index = sink.null

--- Create a new null sink.
---
---@return luvit.stream.sink.null
function sink.null.new()
	return sink.null
end

--- Write items to the sink.
---
---@param items luvit.stream.sink.iovec
---@param callback luvit.stream.sink.success
function sink.null:writev(items, callback)
	return callback(true)
end

--- Write an item to the sink.
---
---@param item luvit.stream.sink.item
---@param callback luvit.stream.sink.success
function sink.null:write(item, callback)
	return callback(true)
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@param callback luvit.stream.sink.success
function sink.null:flush(callback)
	return callback(true)
end

--- End the sink, no more items will be written.
---
---@param callback luvit.stream.sink.success
function sink.null:finish(callback)
	return callback(true)
end

-- #endregion
-- #region sink.counting

---@class luvit.stream.sink.counting : luvit.stream.sink
---@field count integer
---
--- A sink that counts the number of items written to it. Does not store the items.
sink.counting = {}
sink.counting.__index = sink.counting

--- Create a new counting sink.
---
---@return luvit.stream.sink.counting
function sink.counting.new()
	return setmetatable({ count = 0 }, sink.counting)
end

--- Write items to the sink.
---
---@param items luvit.stream.sink.iovec
---@param callback luvit.stream.sink.success
function sink.counting:writev(items, callback)
	local size = 0

	for _, v in ipairs(items) do
		size = size + #v
	end

	self.count = self.count + size
	return callback(true)
end

--- Write an item to the sink.
---
---@param item luvit.stream.sink.item
---@param callback luvit.stream.sink.success
function sink.counting:write(item, callback)
	self.count = self.count + #item
	return callback(true)
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@param callback luvit.stream.sink.success
function sink.counting:flush(callback)
	return callback(true)
end

--- End the sink, no more items will be written.
---
---@param callback luvit.stream.sink.success
function sink.counting:finish(callback)
	return callback(true)
end

-- #endregion
-- #region sink.table

---@class luvit.stream.sink.table : luvit.stream.sink
---@field items string[]
---
--- A sink that writes items to a table.
sink.table = {}
sink.table.__index = sink.table

--- Create a new table sink.
---
---@param items string[]? The table to write items to. If not provided, a new table will be created.
---@return luvit.stream.sink.table
function sink.table.new(items)
	items = items or {}
	return setmetatable({ items = items, n = #items }, sink.table)
end

--- Write items to the sink.
---
---@param items luvit.stream.sink.iovec
---@param callback luvit.stream.sink.success
function sink.table:writev(items, callback)
	local n = self.n

	for i, v in ipairs(items) do
		self.items[n + i] = tostring(v)
	end

	self.n = n + #items
	return callback(true)
end

--- Write an item to the sink.
---
---@param item luvit.stream.sink.item
---@param callback luvit.stream.sink.success
function sink.table:write(item, callback)
	self.n = self.n + 1
	self.items[self.n] = tostring(item)
	return callback(true)
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@param callback luvit.stream.sink.success
function sink.table:flush(callback)
	return callback(true)
end

--- End the sink, no more items will be written.
---
---@param callback luvit.stream.sink.success
function sink.table:finish(callback)
	return callback(true)
end

-- #endregion
-- #region sink.uv_file

---@class luvit.stream.sink.uv_file : luvit.stream.sink
---@field fd integer
---
--- A sink that writes items to a file descriptor using libuv.
sink.uv_file = {}
sink.uv_file.__index = sink.uv_file

--- Create a new table sink.
---
---@param fd integer The file descriptor to write to.
---@return luvit.stream.sink.uv_file
function sink.uv_file.new(fd)
	assert(type(fd) == "number", "invalid file descriptor")
	assert(fd >= 0, "invalid file descriptor")

	return setmetatable({ fd = fd }, sink.uv_file)
end

--- Write items to the sink.
---
---@param items luvit.stream.sink.iovec
---@param callback luvit.stream.sink.success
function sink.uv_file:writev(items, callback)
	-- any slices need to be converted to strings
	for i, v in ipairs(items) do
		items[i] = tostring(v)
	end

	local req, err = luv.uv_fs_write(self.fd, items, -1, function(err, n_written)
		if err then
			return callback(false, err)
		end

		-- figure out what remains to be written
		local new_start, old_end = 0, #items
		for i = 1, old_end do
			local item = items[i]
			if n_written >= #item then
				n_written = n_written - #item
			else
				new_start = i
				break
			end

			items[i] = nil
		end

		-- all items were written
		if new_start == 0 then
			return callback(true)
		end

		-- shift remaining items to the front of the array
		for i = new_start, old_end do
			items[i - new_start + 1] = items[i]
			items[i] = nil
		end

		-- if there's a partial write, adjust the first items
		if n_written > 0 then
			items[1] = items[1]:sub(n_written + 1)
		end

		-- write remaining items
		return self:writev(items, callback)
	end)

	if not req then
		return callback(false, err)
	end
end

--- Write an item to the sink.
---
---@param item luvit.stream.sink.item
---@param callback luvit.stream.sink.success
function sink.uv_file:write(item, callback)
	local req, err = luv.uv_fs_write(self.fd, tostring(item), -1, function(err, n_written)
		if err then
			return callback(false, err)
		end

		local remaining = item:sub(n_written + 1)
		if #remaining > 0 then
			return self:write(remaining, callback)
		end

		return callback(true)
	end)

	if not req then
		return callback(false, err)
	end
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@param callback luvit.stream.sink.success
function sink.uv_file:flush(callback)
	local req, err = luv.uv_fs_fdatasync(self.fd, function(err, success)
		return callback(success, err)
	end)

	if not req then
		return callback(false, err)
	end
end

--- End the sink, no more items will be written.
---
---@param callback luvit.stream.sink.success
function sink.uv_file:finish(callback)
	return self:flush(callback)
end

-- #endregion
-- #region sink.uv_stream

---@class luvit.stream.sink.uv_stream : luvit.stream.sink
---@field stream uv_stream_t
---
--- A sink that writes items to a file descriptor using libuv.
sink.uv_stream = {}
sink.uv_stream.__index = sink.uv_stream

--- Create a new sink that writes to a luv stream.
---
---@param stream uv_stream_t The stream to write to.
---@return luvit.stream.sink.uv_stream
function sink.uv_stream.new(stream)
	return setmetatable({ stream = stream }, sink.uv_stream)
end

--- Write items to the sink.
---
---@param items luvit.stream.sink.iovec
---@param callback luvit.stream.sink.success
function sink.uv_stream:writev(items, callback)
	-- any slices need to be converted to strings
	for i, v in ipairs(items) do
		items[i] = tostring(v)
	end

	local req, err = luv.uv_write(self.stream, items, function(err)
		return callback(not err, err)
	end)

	if not req then
		return callback(false, err)
	end
end

--- Write an item to the sink.
---
---@param item luvit.stream.sink.item
---@param callback luvit.stream.sink.success
function sink.uv_stream:write(item, callback)
	local req, err = luv.uv_write(self.stream, tostring(item), function(err)
		return callback(not err, err)
	end)

	if not req then
		return callback(false, err)
	end
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@param callback luvit.stream.sink.success
function sink.uv_stream:flush(callback)
	return callback(true)
end

--- End the sink, no more items will be written.
---
---@param callback luvit.stream.sink.success
function sink.uv_stream:finish(callback)
	local req, err = luv.uv_shutdown(self.fd, function(err)
		return callback(not err, err)
	end)

	if not req then
		return callback(false, err)
	end
end

-- #endregion
-- #region sink.synchronize

---@class luvit.stream.sink.sync
---@field sink luvit.stream.sink
---
--- A sink that synchronizes another sink
sink.sync = {}
sink.sync.__index = sink.sync

--- Create a new synchronized sink.
---
---@param sink luvit.stream.sink The sink to synchronize.
---@return luvit.stream.sink.sync
function sink.sync.new(sink)
	return setmetatable({ sink = sink }, sink.sync)
end

--- Write items to the sink.
---
---@param items luvit.stream.sink.iovec
function sink.sync:writev(items)
	local co = coroutine.running()
	local success, err
	local yielded = false

	self.sink:writev(items, function(s, e)
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

--- Write an item to the sink.
---
---@param item luvit.stream.sink.item
function sink.sync:write(item)
	local co = coroutine.running()
	local success, err
	local yielded = false

	self.sink:write(item, function(s, e)
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

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@return boolean, string|nil
function sink.sync:flush()
	local co = coroutine.running()
	local success, err
	local yielded = false

	self.sink:flush(function(s, e)
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

--- End the sink, no more items will be written.
---
---@return boolean, string|nil
function sink.sync:finish()
	local co = coroutine.running()
	local success, err
	local yielded = false

	self.sink:finish(function(s, e)
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
-- #region sink.buffered

---@class luvit.stream.sink.buffered : luvit.stream.sink
---@field under luvit.stream.sink
---@field buffer luvit.buffer
---@field high_water_mark integer
---
--- A sink that buffers items before writing them to another sink.
sink.buffered = {}
sink.buffered.__index = sink.buffered

--- Create a new buffered sink.
---
---@param under luvit.stream.sink The underlying sink.
---@param high_water_mark integer The maximum number of bytes to buffer before flushing.
---@return luvit.stream.sink.buffered
function sink.buffered.new(under, high_water_mark)
	return setmetatable({
		under = under,
		buffer = buffer.new(),
		high_water_mark = high_water_mark or 4096,
	}, sink.buffered)
end

--- Write items to the sink.
---
---@param items luvit.stream.sink.iovec
---@param callback luvit.stream.sink.success
function sink.buffered:writev(items, callback)
	local len = #self.buffer
	for _, v in ipairs(items) do
		len = len + #v
	end

	if len >= self.high_water_mark then
		return self:flush(function(success, err)
			if not success then
				return callback(false, err)
			end

			return self.under:writev(items, callback)
		end)
	end

	for _, v in ipairs(items) do
		self.buffer:write(v)
	end

	return callback(true)
end

--- Write an item to the sink.
---
---@param item luvit.stream.sink.item
---@param callback luvit.stream.sink.success
function sink.buffered:write(item, callback)
	local len = #self.buffer + #item
	if len >= self.high_water_mark then
		return self:flush(function(success, err)
			if not success then
				return callback(false, err)
			end

			return self.under:write(item, callback)
		end)
	end

	self.buffer:write(item)
	return callback(true)
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@param callback luvit.stream.sink.success
function sink.buffered:flush(callback)
	if #self.buffer == 0 then
		return callback(true)
	end

	return self.under:write(self.buffer:read(), callback)
end

--- End the sink, no more items will be written.
---
---@param callback luvit.stream.sink.success
function sink.buffered:finish(callback)
	if #self.buffer == 0 then
		self.buffer:free()
		return callback(true)
	end

	return self.under:write(self.buffer:read(), function(success, err)
		self.buffer:free()
		return callback(success, err)
	end)
end

-- #endregion
-- #region sink.deflate

---@class luvit.stream.sink.deflate : luvit.stream.sink
---@field under luvit.stream.sink
---@field deflator userdata
---
--- A sink that compresses items before writing them to another sink.
sink.deflate = {}
sink.deflate.__index = sink.deflate

--- Create a new deflating sink.
---
---@param under luvit.stream.sink The underlying sink.
function sink.deflate.new(under)
	local deflator = miniz.new_deflator()
	return setmetatable({ under = under, deflator = deflator }, sink.deflate)
end

--- Write items to the sink.
---
---@param items luvit.stream.sink.iovec
---@param callback luvit.stream.sink.success
function sink.deflate:writev(items, callback)
	local out = {}

	for _, v in ipairs(items) do
		local chunk, err = self.deflator:deflate(v)
		if not chunk then
			return callback(false, err)
		end

		if #chunk > 0 then
			table.insert(out, chunk)
		end
	end

	if #out == 0 then
		return callback(true)
	end

	return self.under:writev(out, callback)
end

--- Write an item to the sink.
---
---@param item luvit.stream.sink.item
---@param callback luvit.stream.sink.success
function sink.deflate:write(item, callback)
	local chunk, err = self.deflator:deflate(item)
	if not chunk then
		return callback(false, err)
	end

	if #chunk == 0 then
		return callback(true)
	end

	return self.under:write(chunk, callback)
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@param callback luvit.stream.sink.success
function sink.deflate:flush(callback)
	local chunk, err = self.deflator:deflate("", "sync")
	if not chunk then
		return callback(false, err)
	end

	if #chunk == 0 then
		return callback(true)
	end

	return self.under:write(chunk, callback)
end

--- End the sink, no more items will be written.
---
---@param callback luvit.stream.sink.success
function sink.deflate:finish(callback)
	local chunk, err = self.deflator:deflate("", "finish")
	if not chunk then
		return callback(false, err)
	end

	if #chunk == 0 then
		return callback(true)
	end

	return self.under:write(chunk, callback)
end

-- #endregion

return sink
