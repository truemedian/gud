local has_ffi, ffi = pcall(require, "ffi")

---@type luvit.slice
local slice = {}
slice.__index = slice

---@type luvit.buffer
local buffer = {}
buffer.__index = buffer

local function clamp(x, min, max)
	if x < min then
		return min
	elseif x > max then
		return max
	else
		return x
	end
end

if has_ffi then
	local ref_table = { [0] = nil }

	local function store_ref(v)
		local ref = ref_table[0]

		if ref then
			ref_table[0] = ref_table[ref]
			ref_table[ref] = v
			return ref
		end

		ref = #ref_table + 1
		ref_table[ref] = v
		return ref
	end

	local function free_ref(ref)
		if not ref then
			return
		end

		ref_table[ref] = ref_table[0]
		ref_table[0] = ref
	end

	ffi.cdef([[
		void free(void *ptr);
		void *malloc(size_t size);
		void *realloc(void *ptr, size_t size);

		void *memmove(void *dest, const void *src, size_t n);
		void* memchr(const void* ptr, int ch, size_t count);
		int memcmp(const void* s1, const void* s2, size_t n);
	]])

	-- avoids issues when statically linked on windows
	local C = ffi.os == "Windows" and ffi.load("msvcrt") or ffi.C

	local function relative_index(len, i)
		local upper = len - 1

		if i > 0 then
			return clamp(i - 1, 0, upper)
		else
			return clamp(len + i, 0, upper)
		end
	end

	function slice.new(str)
		if getmetatable(str) == slice then
			return str
		end

		local new = setmetatable({
			ptr = ffi.cast("const uint8_t *", str),
			length = #str,
			ref = store_ref(str),
		}, slice)
		return new
	end

	function slice:byte(i, j)
		assert(type(i) == "number", "bad argument #1 to 'byte' (number expected)")
		assert(type(j) == "number" or j == nil, "bad argument #2 to 'byte' (number or nil expected)")

		i = relative_index(self.length, i)
		j = j and relative_index(self.length, j) or i

		if i > j then
			return nil
		elseif i == j then
			return self.ptr[i]
		end

		local len = j - i + 1
		return ffi.string(self.ptr + i, len):byte(1, len)
	end

	function slice:len()
		return self.length
	end
	slice.__len = slice.len

	function slice:sub(i, j)
		i = relative_index(self.length, i)
		j = j and relative_index(self.length, j) or (self.length - 1)

		local new = setmetatable({
			ptr = self.ptr + i,
			length = j - i + 1,
			ref = store_ref(self),
		}, slice)
		return new
	end

	function slice:find(substring, init)
		local len = self.length
		local ptr = self.ptr

		init = init and relative_index(len, init) or 0
		substring = slice.new(substring)

		local sublen = substring.length
		local subptr = substring.ptr

		local chr = subptr[0]

		if sublen == 0 then
			return nil
		elseif sublen == 1 then
			local res = C.memchr(ptr + init, chr, len - init)
			if res == nil then
				return nil
			end

			return tonumber(ffi.cast("uintptr_t", res) - ffi.cast("uintptr_t", ptr)) + 1
		end

		local pos = init
		while pos <= len - sublen do
			local next_match = C.memchr(ptr + pos, chr, len - pos - sublen + 1)
			if next_match == nil then
				return nil
			end

			pos = tonumber(ffi.cast("uintptr_t", next_match) - ffi.cast("uintptr_t", ptr)) + 1

			if C.memcmp(ptr + pos, subptr + 1, sublen - 1) == 0 then
				return pos
			end
		end
	end

	function slice:find_any(substring, init)
		substring = slice.new(substring)

		local len = self.length
		local ptr = self.ptr

		init = init and relative_index(len, init) or 0

		local needle_len = substring.length
		local needle_ptr = substring.ptr
		if needle_len == 0 then
			return nil
		end

		local min_found = math.huge
		for i = init, len - 1 do
			if C.memchr(needle_ptr, ptr[i], needle_len) ~= nil then
				min_found = math.min(min_found, i + 1)
			end
		end

		return min_found == math.huge and nil or min_found
	end

	function slice:equals(other)
		self = slice.new(self)
		other = slice.new(other)

		if self.length ~= other.length then
			return false
		end

		return C.memcmp(self.ptr, other.ptr, self.length) == 0
	end
	slice.__eq = slice.equals

	function slice:tostring()
		return ffi.string(self.ptr, self.length)
	end
	slice.__tostring = slice.tostring

	function slice:free()
		if self.ref then
			free_ref(self.ref)
			self.ref = nil
		end

		self.ptr = nil
		self.length = 0
	end
	slice.__gc = slice.free

	local initial_size = 64
	function buffer.new(size)
		local self = setmetatable({
			ptr = nil,
			capacity = 0,
			head = 0,
			tail = 0,
			ref = nil,
		}, buffer)

		if size and size > 0 then
			self:grow(size)
		else
			self:grow(initial_size)
		end

		return self
	end

	function buffer:set(str)
		self:free()

		self.ref = store_ref(str)

		if getmetatable(str) == buffer then
			self.ptr = str.ptr
			self.capacity = str.capacity
			self.head = str.head
			self.tail = str.tail
		elseif getmetatable(str) == slice then
			local len = str.length

			self.ptr = str.ptr
			self.capacity = len
			self.head = 0
			self.tail = len
		else
			local len = #str

			self.ptr = ffi.cast("uint8_t *", str)
			self.capacity = len
			self.head = 0
			self.tail = len
		end

		return self
	end

	function buffer:len()
		return self.tail - self.head
	end

	function buffer:reset()
		self.head = 0
		self.tail = 0
	end

	function buffer:free()
		if self.ref then
			free_ref(self.ref)
			self.ref = nil
		else
			C.free(self.ptr)
		end

		self.ptr = nil
		self.capacity = 0
		self.head = 0
		self.tail = 0
		self.flags = 0
	end
	buffer.__gc = buffer.free

	function buffer:grow(requested)
		local cur_len = self.tail - self.head
		local min_len = cur_len + requested
		local new_len = min_len + math.floor(min_len / 2) + 32

		if self.ref then
			free_ref(self.ref)
			self.ref = nil

			local buf = self.ptr

			self.ptr = ffi.cast("char *", assert(C.malloc(new_len), "not enough memory"))
			self.capacity = new_len

			ffi.copy(self.ptr, buf + self.head, cur_len)

			self.tail = cur_len
			self.head = 0

			return
		end

		local cur_capacity = self.capacity
		local free_space = cur_capacity - self.tail
		if free_space >= requested then
			return
		end

		if self.head ~= 0 then
			C.memmove(self.ptr, self.ptr + self.head, cur_len)

			self.tail = cur_len
			self.head = 0
		end

		local moved_space = cur_capacity - cur_len
		if moved_space >= requested then
			return
		end

		if self.ptr == nil then
			self.ptr = ffi.cast("char *", assert(C.malloc(new_len), "not enough memory"))
			self.capacity = new_len
			return
		end

		self.ptr = ffi.cast("char *", assert(C.realloc(self.ptr, new_len), "not enough memory"))
		self.capacity = new_len
	end

	function buffer:write(str)
		if getmetatable(str) == buffer then
			local len = str.tail - str.head
			self:grow(len)

			ffi.copy(self.ptr + self.tail, str.ptr + str.head, len)
			self.tail = self.tail + len
		elseif getmetatable(str) == slice then
			local len = str.length
			self:grow(len)

			ffi.copy(self.ptr + self.tail, str.ptr, len)
			self.tail = self.tail + len
		else
			local n = #str
			self:grow(n)

			ffi.copy(self.ptr + self.tail, str, n)
			self.tail = self.tail + n
		end
	end

	function buffer:peek(n, start)
		local len = self.tail - self.head

		start = start and relative_index(len, start) or 0
		n = n and clamp(n, 0, len - start) or (len - start)

		local new = setmetatable({
			ptr = self.ptr + self.head + start,
			length = n,
			ref = store_ref(self),
		}, slice)
		return new
	end

	function buffer:read(n)
		local str = buffer.peek(self, n)
		self.head = self.head + #str
		return str
	end

	function buffer:skip(n)
		assert(n >= 0, "invalid forward offset")
		self.head = math.min(self.capacity, self.head + n)
	end
end

return {
	new = buffer.new,
	buffer = buffer,
	slice = slice,
}
