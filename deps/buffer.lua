local class = require('class')

local concat = table.concat
local max = math.max
local sub = string.sub

--- @class std.buffer
--- @field protected chunks string[] Stored chunks in FIFO order.
--- @field protected head integer 1-based index of the current front chunk.
--- @field protected tail integer 1-based index of the next tail chunk.
--- @field protected offset integer 1-based byte offset into the current head chunk.
--- @field protected length integer Total number of unread bytes in the buffer.
local buffer = class('std.buffer')

function buffer:init()
	self.chunks = {}
	self.head = 1
	self.tail = 1
	self.offset = 1
	self.length = 0
end

--- Appends data to the end of the buffer.
--- @param data string
function buffer:write(data)
	assert(type(data) == 'string', 'data must be a string')
	local data_len = #data
	if data_len == 0 then
		return
	end

	self.chunks[self.tail] = data
	self.tail = self.tail + 1
	self.length = self.length + data_len
end

--- Returns the number of buffered bytes.
--- @return integer
function buffer:len()
	return self.length
end
buffer.__len = buffer.len

--- Returns up to `n` bytes from the front without removing data. If less than `n` bytes are buffered, all buffered
--- bytes are returned.
---
--- If `n` is nil, all buffered bytes are returned.
--- @param n? integer
--- @return string data
function buffer:peek(n)
	if self.length == 0 then
		return ''
	end

	if n == nil then
		self:_normalize_head()

		local data = concat(self.chunks, nil, self.head, self.tail - 1)

		-- take the opportunity to compact the front of the buffer since we have to concatenate all chunks anyway
		self.chunks[1] = data
		for i = max(2, self.head), self.tail - 1 do
			self.chunks[i] = nil
		end

		self.head = 1
		self.tail = 2
		return data
	end

	assert(type(n) == 'number' and n >= 0, 'n must be a non-negative integer')
	if n > self.length then
		n = self.length
	elseif n == 0 then
		return ''
	end

	local chunks = self.chunks
	local head = self.head
	local remaining = n
	local parts, p = {}, 1

	local first_chunk = chunks[head]
	if not first_chunk then
		return ''
	end

	local first_available = #first_chunk - self.offset + 1
	if remaining <= first_available then
		return sub(first_chunk, self.offset, self.offset + remaining - 1)
	else
		parts[p] = sub(first_chunk, self.offset)
		remaining = remaining - first_available
		head = head + 1
		p = p + 1
	end

	while true do
		local chunk = chunks[head]
		if not chunk then
			break
		end

		local available = #chunk

		if remaining < available then
			parts[p] = sub(chunk, 1, remaining)

			break
		elseif remaining == available then
			parts[p] = chunk

			break
		else
			parts[p] = chunk
			head = head + 1
			remaining = remaining - available
		end

		p = p + 1
	end

	return concat(parts)
end

--- Returns up to `n` bytes from the front and removes them from the buffer. If less than `n` bytes are buffered, all
--- buffered bytes are returned.
---
--- If `n` is nil, all buffered bytes are returned.
--- @param n? integer
--- @return string data
function buffer:read(n)
	if self.length == 0 then
		return ''
	end

	if n == nil then
		self:_normalize_head()

		local data = concat(self.chunks, nil, self.head, self.tail - 1)

		self:clear()
		return data
	end

	assert(type(n) == 'number' and n >= 0, 'n must be a non-negative integer')
	if n == 0 then
		return ''
	elseif n > self.length then
		n = self.length
	end

	local chunks = self.chunks
	local head = self.head
	local remaining = n
	local parts, p = {}, 1

	local first_chunk = chunks[head]
	if not first_chunk then
		return ''
	end

	local first_available = #first_chunk - self.offset + 1
	if remaining < first_available then
		local data = sub(first_chunk, self.offset, self.offset + remaining - 1)
		self.length = self.length - remaining

		if self.length == 0 then
			self:clear()
		else
			self.head = head
			self.offset = self.offset + remaining
		end

		return data
	elseif remaining == first_available then
		local data = sub(first_chunk, self.offset)
		self.length = self.length - remaining

		if self.length == 0 then
			self:clear()
		else
			self.chunks[head] = nil
			self.head = head + 1
			self.offset = 1
		end

		return data
	else
		parts[p] = sub(first_chunk, self.offset)
		remaining = remaining - first_available
		head = head + 1
		p = p + 1
	end

	while true do
		local chunk = chunks[head]
		if not chunk then
			self:clear()
			return concat(parts)
		end

		local available = #chunk

		if remaining < available then
			parts[p] = sub(chunk, 1, remaining)

			for i = self.head, head - 1 do
				self.chunks[i] = nil
			end

			self.head = head
			self.offset = remaining + 1
			break
		elseif remaining == available then
			parts[p] = chunk

			for i = self.head, head do
				self.chunks[i] = nil
			end

			self.head = head + 1
			self.offset = 1
			break
		else
			parts[p] = chunk
			head = head + 1
			remaining = remaining - available
		end

		p = p + 1
	end

	local data = concat(parts)
	self.length = self.length - #data
	return data
end

--- Skips `n` bytes from the front of the buffer without returning them.
--- @param n integer
function buffer:skip(n)
	assert(type(n) == 'number' and n >= 0, 'n must be a non-negative integer')
	if n == 0 then
		return
	elseif n > self.length then
		n = self.length
	end

	local chunks = self.chunks
	local head = self.head
	local remaining = n

	while true do
		local chunk = chunks[head]
		if not chunk then
			break
		end

		local available = #chunk - self.offset + 1

		if remaining < available then
			self.offset = self.offset + remaining
			break
		elseif remaining == available then
			chunks[head] = nil
			head = head + 1
			self.offset = 1
			break
		else
			chunks[head] = nil
			head = head + 1
			remaining = remaining - available
			self.offset = 1
		end
	end

	if self.length == n then
		self:clear()
	else
		self.head = head
		self.length = self.length - n
	end
end

function buffer:_normalize_head()
	if self.offset > 1 then
		local head_chunk = self.chunks[self.head]
		if head_chunk then
			self.chunks[self.head] = sub(head_chunk, self.offset)
		end

		self.offset = 1
	end
end

function buffer:_shift()
	if self.head ~= 1 then
		local n = 1
		for i = self.head, self.tail - 1 do
			self.chunks[n], self.chunks[i] = self.chunks[i], nil
			n = n + 1
		end

		self.tail = n
		self.head = 1
	end
end

--- Returns a valid lua sequence of buffered data chunks. The returned table must not be modified by the caller and is
--- only valid until the next buffer mutation.
---
--- @return string[]
function buffer:parts()
	self:_normalize_head()
	self:_shift()

	return self.chunks
end

--- Returns the most conviently continguuous chunk of buffered data from the front of the buffer, or `nil` if the
--- buffer is empty.
---
--- @return string|nil
function buffer:chunk()
	self:_normalize_head()

	return self.chunks[self.head]
end

--- Clears all buffered data.
function buffer:clear()
	for i = self.head, self.tail - 1 do
		self.chunks[i] = nil
	end

	self.head = 1
	self.tail = 1
	self.offset = 1
	self.length = 0
end

return buffer
