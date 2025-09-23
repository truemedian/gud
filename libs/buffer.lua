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

local ref_table = setmetatable({}, { __mode = "k" })

if has_ffi then
	local COW = 1

	ffi.cdef([[
        void free(void *ptr);
        void *malloc(size_t size);
        void *realloc(void *ptr, size_t size);
        void *memmove(void *dest, const void *src, size_t n);
		
		void* memchr(const void* ptr, int ch, size_t count);
		int memcmp(const void* s1, const void* s2, size_t n);

        typedef struct {
            uint8_t *ptr;
            uint32_t capacity;
            uint32_t head;
            uint32_t tail;
            uint8_t flags;
        } luvit_buffer_t;
		
        typedef struct {
            const uint8_t *ptr;
            uint32_t length;
        } luvit_slice_t;
    ]])

	local slice_t = ffi.typeof("luvit_slice_t")
	ffi.metatype(slice_t, slice)

	local buffer_t = ffi.typeof("luvit_buffer_t")
	ffi.metatype(buffer_t, buffer)

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

	local empty_slice = slice_t()

	function slice.new(str)
		if ffi.istype(slice_t, str) then
			return str
		end

		local self = slice_t(ffi.cast("const uint8_t *", str), #str)
		-- ref_table[self] = str
		return self
	end

	function slice:byte(i, j)
		assert(type(i) == "number", "bad argument #1 to 'byte' (number expected)")
		assert(type(j) == "number" or j == nil, "bad argument #2 to 'byte' (number or nil expected)")

		i = relative_index(self.length, i)
		j = relative_index(self.length, j or i)

		if i > j then
			return nil
		elseif i == j then
			return self.ptr[i]
		end

		return ffi.string(self.ptr + i, j - i + 1):byte(1, j - i + 1)
	end

	function slice:len()
		return self.length
	end
	slice.__len = slice.len

	function slice:sub(i, j)
		i = relative_index(self.length, i)
		j = relative_index(self.length, j or self.length)

		if i > j then
			return empty_slice
		end

		local new = slice_t(self.ptr + i, j - i + 1)
		-- ref_table[new] = self
		return new
	end

	function slice:find(substring, init)
		substring = slice.new(substring)

		local len = self.length
		init = relative_index(len, init or 1)

		local sublen = substring.length
		local chr = substring.ptr[0]

		local ptr = self.ptr
		if sublen == 0 then
			return nil
		elseif sublen == 1 then
			local res = C.memchr(ptr + init, chr, len - init)
			if res == nil then
				return nil
			end

			return tonumber(ffi.cast("uintptr_t", res) - ffi.cast("uintptr_t", ptr)) + 1
		end

		local i = init
		while i <= len - sublen do
			local next_match = C.memchr(ptr + i, chr, len - i - sublen + 1)
			if next_match == nil then
				return nil
			end

			i = tonumber(ffi.cast("uintptr_t", next_match) - ffi.cast("uintptr_t", ptr))

			local match = true
			for j = i + 1, i + sublen - 1 do
				if ptr[j] ~= substring.ptr[j - i] then
					match = false
					break
				end
			end

			if match then
				return i + 1
			end

			i = i + 1
		end
	end

	function slice:find_any(substring, init)
		substring = slice.new(substring)

		local len = self.length
		init = relative_index(len, init or 1)

		local haystack_ptr = self.ptr
		local needle_len = substring.length
		local needle_ptr = substring.ptr
		if needle_len == 0 then
			return nil
		end

		for i = init, len - 1 do
			if C.memchr(needle_ptr, haystack_ptr[i], needle_len) ~= nil then
				return i + 1
			end
		end
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

	local initial_size = 64
	function buffer.new(size)
		local self = buffer_t()
		if size and size > 0 then
			self:resize(size)
		else
			self:resize(initial_size)
		end
		return self
	end

	function buffer:set(str)
		self:free()

		ref_table[self] = str
		self.flags = COW

		if ffi.istype(buffer_t, str) then
			self.ptr = str.ptr
			self.capacity = str.capacity
			self.head = str.head
			self.tail = str.tail
		elseif ffi.istype(slice_t, str) then
			self.ptr = str.ptr
			self.capacity = str.length
			self.head = 0
			self.tail = str.length
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
		if self.flags ~= COW then
			C.free(self.ptr)
		end

		self.ptr = nil
		self.capacity = 0
		self.head = 0
		self.tail = 0
		self.flags = 0
	end

	function buffer:resize(requested)
		local cur_len = self.tail - self.head
		local min_len = cur_len + requested
		local new_len = min_len + math.floor(min_len / 2) + 32

		if self.flags == COW then
			ref_table[self] = nil
			local buf = self.ptr

			self.ptr = assert(C.malloc(new_len), "not enough memory")
			self.capacity = new_len

			ffi.copy(self.ptr, buf + self.head, cur_len)

			self.tail = cur_len
			self.head = 0
			self.flags = 0

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

		self.ptr = assert(C.realloc(self.ptr, new_len), "not enough memory")
		self.capacity = new_len
	end

	function buffer:write(str)
		if ffi.istype(buffer_t, str) then
			local n = str:len()
			self:resize(n)

			ffi.copy(self.ptr + self.tail, str.ptr + str.head, n)
			self.tail = self.tail + n
		elseif ffi.istype(slice_t, str) then
			local n = str.length
			self:resize(n)

			ffi.copy(self.ptr + self.tail, str.ptr, n)
			self.tail = self.tail + n
		else
			local n = #str
			self:resize(n)

			ffi.copy(self.ptr + self.tail, str, n)
			self.tail = self.tail + n
		end
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

	function buffer:peek(n, start)
		local len = self.tail - self.head

		start = relative_index(len, start or 1)
		n = clamp(n or (len - start), 0, len - start)

		local new = slice_t(self.ptr + self.head + start, n)
		-- ref_table[new] = self
		return new
	end
end

return {
	new = buffer.new,
	buffer = buffer,
	slice = slice,
}
