local luv = require("luv")

local function make_wait()
	local thread = coroutine.running()

	return function(...)
		local success, err = coroutine.resume(thread, ...)
		if not success then
			error(debug.traceback(thread, err))
		end
	end
end

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
---@param ... string
---@return boolean success, string|nil err
function sink.null:write(...)
	return true
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@return boolean success, string|nil err
function sink.null:flush()
	return true
end

--- End the sink, no more items will be written.
---
---@return boolean success, string|nil err
function sink.null:finish()
	return true
end

-- #endregion
-- #region sink.counting

---@class luvit.stream.sink.counting : luvit.stream.sink
---@field count integer The number of items written to the sink.
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
---@param ... string
---@return boolean success, string|nil err
function sink.counting:write(...)
	local size = 0
	for i = 1, select("#", ...) do
		local v = select(i, ...)
		size = size + #v
	end

	self.count = self.count + size
	return true
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@return boolean success, string|nil err
function sink.counting:flush()
	return true
end

--- End the sink, no more items will be written.
---
---@return boolean success, string|nil err
function sink.counting:finish()
	return true
end

-- #endregion
-- #region sink.table

---@class luvit.stream.sink.table : luvit.stream.sink
---@field items any[] The table to write items to.
---
--- A sink that writes items to a table.
sink.table = {}
sink.table.__index = sink.table

--- Create a new table sink.
---
---@param items any[]? The table to write items to. If not provided, a new table will be created.
---@return luvit.stream.sink.table
function sink.table.new(items)
	items = items or {}
	return setmetatable({ items = items, n = #items }, sink.table)
end

--- Write items to the sink.
---
---@param ... string
---@return boolean success, string|nil err
function sink.table:write(...)
	local count = select("#", ...)

	local n = self.n
	for i = 1, count do
		local v = select(i, ...)
		self.items[n + i] = v
	end

	self.n = n + count
	return true
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@return boolean success, string|nil err
function sink.table:flush()
	return true
end

--- End the sink, no more items will be written.
---
---@return boolean success, string|nil err
function sink.table:finish()
	return true
end

-- #endregion
-- #region sink.uv_file

---@class luvit.stream.sink.uv_file : luvit.stream.sink
---@field fd integer The file descriptor to write to.
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
---@param ... string
---@return boolean success, string|nil err
function sink.uv_file:write(...)
	local n_buffers = select("#", ...)

	---@type string|string[]
	local buffers = ...
	if n_buffers == 1 then
		buffers = { ... }
	end

	while true do
		local req, err = luv.uv_fs_write(self.fd, buffers, -1, make_wait())
		if not req then
			return false, err
		end

		local n_written
		err, n_written = coroutine.yield()
		if err then
			return false, err
		end

		if n_buffers == 1 then
			if n_written < #buffers then
				buffers = buffers:sub(n_written + 1)
			else
				return true
			end
		end

		while n_buffers > 0 do
			if n_written < #buffers[1] then
				buffers[1] = buffers[1]:sub(n_written + 1)
				break
			else
				n_written = n_written - #buffers[1]
				table.remove(buffers, 1)
				n_buffers = n_buffers - 1
			end
		end

		if n_buffers == 0 then
			return true
		elseif n_buffers == 1 then
			buffers = buffers[1]
		end
	end
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@return boolean success, string|nil err
function sink.uv_file:flush()
	local req, err = luv.uv_fs_fdatasync(self.fd, make_wait())
	if not req then
		return false, err
	end

	local success
	err, success = coroutine.yield()
	return success, err
end

--- End the sink, no more items will be written.
---
---@return boolean success, string|nil err
function sink.uv_file:finish()
	return self:flush()
end

-- #endregion
-- #region sink.uv_stream

---@class luvit.stream.sink.uv_stream : luvit.stream.sink
---@field fd integer The file descriptor to write to.
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
---@param ... string
---@return boolean success, string|nil err
function sink.uv_stream:write(...)
	local n_buffers = select("#", ...)

	---@type string|string[]
	local buffers = ...
	if n_buffers == 1 then
		buffers = { ... }
	end

	local req, err = luv.uv_write(self.fd, buffers, make_wait())
	if not req then
		return false, err
	end

	err = coroutine.yield()
	return not err, err
end

--- Indicate that the sink should attempt to push any buffered items to the underlying resource.
---
---@return boolean success, string|nil err
function sink.uv_stream:flush()
	return true
end

--- End the sink, no more items will be written.
---
---@return boolean success, string|nil err
function sink.uv_stream:finish()
	local req, err = luv.uv_shutdown(self.fd, make_wait())
	if not req then
		return false, err
	end

	err = coroutine.yield()
	return not err, err
end

-- #endregion

return sink
