local has_ffi, ffi = pcall(require, "ffi")

local class = import("class")

-- translate relative index to absolute index.
-- positive values count from the start, negative values count from the end.
-- clamped to [1, inf)
local function relative_start(len, i)
	if i > 0 then
		return i
	elseif i == 0 then
		return 1
	elseif i >= -len then
		return len + i + 1
	else -- i < -len
		return 1
	end
end

-- translate relative end to absolute end.
-- positive values count from the start, negative values count from the end.
-- clamped to [0, len]
local function relative_end(len, j)
	if j > len then
		return len
	elseif j >= 0 then
		return j
	elseif j >= -len then
		return len + j + 1
	else -- j < -len
		return 0
	end
end

if has_ffi then
	-- #region ffi implementation
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

	-- #region slice

	---@class luvit.slice
	---@field package ptr ffi.cdata* # pointer to the start of the slice
	---@field package length integer # length of the slice
	---@field private ref integer|nil # reference to the original string or buffer to keep it
	local slice = class("slice")

	---@protected
	---@param str string # the string to create a slice for
	function slice:init(str)
		self.ptr = ffi.cast("const uint8_t *", str)
		self.length = #str
		self.ref = store_ref(str)
	end

	--- Returns a slice object for the given string or slice. Does not create a copy for an existing slice.
	---
	---@param str string|luvit.slice # the string or slice to create a slice for
	---@return luvit.slice # the new slice
	---@nodiscard
	function slice.new(str)
		if getmetatable(str) == slice then
			---@type luvit.slice
			return str
		end

		return slice(str)
	end

	slice.empty = slice("")

	--- Get the byte value at index `i`, or between indices `i` and `j` (inclusive).
	---
	---@param i integer # start index
	---@param j? integer # optional end index, defaults to `i`
	---@return integer ... # the byte values between indices `i` and `j`
	function slice:byte(i, j)
		assert(type(i) == "number", "bad argument #1 to 'byte' (number expected)")
		assert(type(j) == "number" or j == nil, "bad argument #2 to 'byte' (number or nil expected)")

		i = relative_start(self.length, i)
		j = j and relative_end(self.length, j) or i

		if i > j then
			return
		elseif i == j then
			return self.ptr[i]
		end

		local len = j - i + 1
		return ffi.string(self.ptr + i - 1, len):byte(1, len)
	end

	--- Get the length of the slice in bytes.
	---
	---@return integer len # number of bytes in the slice
	function slice:len()
		return self.length
	end
	slice.__len = slice.len

	--- Get a new slice representing the bytes between indices `i` and `j` (inclusive).
	---
	---@param i integer # start index
	---@param j? integer # optional end index, defaults to the length of the slice
	---@return luvit.slice # the new slice
	function slice:sub(i, j)
		i = relative_start(self.length, i)
		j = j and relative_end(self.length, j) or self.length

		if i > j then
			return slice.empty
		end

		return setmetatable({
			ptr = self.ptr + i - 1,
			length = j - i + 1,
			ref = store_ref(self),
		}, slice)
	end

	--- Return the index of the first occurrence of `substring` in the slice, or `nil` if not found.
	--- The search starts at the optional index `init`, or at the beginning of the slice if `init` is not specified.
	---
	---@param substring string|luvit.slice # the substring to search for
	---@param init? integer # starting index
	---@return integer? idx # the index of the first occurrence of `substring`, or `nil` if not found
	function slice:find(substring, init)
		local len = self.length
		local ptr = self.ptr

		init = init and relative_start(len, init) or 1
		substring = slice.new(substring)

		local subs_len = substring.length
		local subs_ptr = substring.ptr

		local chr = subs_ptr[0]

		local pos = init - 1
		if subs_len == 0 or pos >= len then
			return nil
		elseif subs_len == 1 then
			local res = C.memchr(ptr + pos, chr, len - pos)
			if res == nil then
				return nil
			end

			return tonumber(ffi.cast("uintptr_t", res) - ffi.cast("uintptr_t", ptr)) + 1
		end

		while pos <= len - subs_len do
			local next_match = C.memchr(ptr + pos, chr, len - pos - subs_len + 1)
			if next_match == nil then
				return nil
			end

			pos = tonumber(ffi.cast("uintptr_t", next_match) - ffi.cast("uintptr_t", ptr)) + 1

			if C.memcmp(ptr + pos, subs_ptr + 1, subs_len - 1) == 0 then
				return pos
			end
		end
	end

	--- Return the index of the first occurrence any item of `substring` in the slice, or `nil` if not found.
	--- The search starts at the optional index `init`, or at the beginning of the slice if `init` is not specified.
	---
	---@param substring string|luvit.slice # items to search for
	---@param init? integer # starting index
	---@return integer? idx # the index of the first occurrence of any item in `substring`, or `nil` if not found
	function slice:find_any(substring, init)
		substring = slice.new(substring)

		local len = self.length
		local ptr = self.ptr

		init = init and relative_start(len, init) or 1

		local needle_len = substring.length
		local needle_ptr = substring.ptr
		if needle_len == 0 then
			return nil
		end

		for i = init - 1, len - 1 do
			if C.memchr(needle_ptr, ptr[i], needle_len) ~= nil then
				return i + 1
			end
		end

		return nil
	end

	--- Return the index of the first occurrence any item not of `substring` in the slice, or `nil` if not found.
	--- The search starts at the optional index `init`, or at the beginning of the slice if `init` is not specified.
	---
	---@param substring string|luvit.slice # items to skip
	---@param init? integer # starting index
	---@return integer? idx # the index of the first occurrence of any item not in `substring`, or `nil` if not found
	function slice:find_not_any(substring, init)
		substring = slice.new(substring)

		local len = self.length
		local ptr = self.ptr

		init = init and relative_start(len, init) or 1

		local needle_len = substring.length
		local needle_ptr = substring.ptr
		if needle_len == 0 then
			return nil
		end

		for i = init - 1, len - 1 do
			if C.memchr(needle_ptr, ptr[i], needle_len) == nil then
				return i + 1
			end
		end

		return nil
	end

	--- Return `true` if the contents of this slice is equal to the contents of `other`, `false` otherwise.
	---
	---@param self string|luvit.slice # the first slice to compare
	---@param other string|luvit.slice # the second slice to compare
	---@return boolean same # `true` if the contents are equal, `false` otherwise
	function slice:equals(other)
		self = slice.new(self)
		other = slice.new(other)

		if self.length ~= other.length then
			return false
		end

		return C.memcmp(self.ptr, other.ptr, self.length) == 0
	end
	slice.__eq = slice.equals

	--- Return the string representation of the slice.
	---
	---@return string str # the string representation of the slice
	function slice:tostring()
		return ffi.string(self.ptr, self.length)
	end
	slice.__tostring = slice.tostring

	--- Release all references to the underlying data.
	function slice:free()
		if self.ref then
			free_ref(self.ref)
			self.ref = nil
		end

		self.ptr = nil
		self.length = 0
	end
	slice.__gc = slice.free

	-- #endregion
	-- #region buffer

	---@class luvit.buffer
	---@field private ptr ffi.cdata* # pointer to the start of the buffer
	---@field private capacity integer # total capacity of the buffer
	---@field private head integer # index of the first valid byte in the buffer
	---@field private tail integer # index of the first free byte in the buffer
	---@field private ref integer|nil # reference to the original string or buffer to keep it
	local buffer = class("buffer")

	local initial_size = 64

	---@protected
	---@param size? integer # initial size of the buffer
	function buffer:init(size)
		self.ptr = nil
		self.capacity = 0
		self.head = 0
		self.tail = 0
		self.ref = nil

		if size and size > initial_size then
			self:grow(size)
		elseif size ~= 0 then
			self:grow(initial_size)
		end
	end

	--- Set the buffer to the given string, replacing any existing contents.
	---
	---@param str string|luvit.slice|luvit.buffer # the new contents of the buffer
	---@return luvit.buffer self
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

	--- Get the length of the readable portion in bytes.
	---
	---@return integer len # number of readable bytes
	function buffer:len()
		return self.tail - self.head
	end
	buffer.__len = buffer.len

	--- Reset the buffer to empty while keeping the allocated capacity.
	function buffer:reset()
		self.head = 0
		self.tail = 0
	end

	--- Reset the buffer to empty and free any allocated memory.
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

	--- Grow the buffer so that at least `n` additional bytes can be written without further allocations.
	---
	---@param requested integer # number of additional bytes needed
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

	--- Append `str` to the buffer.
	---@param str string|luvit.slice|luvit.buffer
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

	--- Peek at `n` bytes offset `i` bytes from the beginning of the buffer without consuming them, or peek at the
	--- entire buffer if `n` is not specified.
	---
	---@param n? integer number of bytes to peek at
	---@param start? integer offset from the beginning of the buffer, 0 means the beginning
	---@return luvit.slice
	function buffer:peek(n, start)
		local len = self.tail - self.head

		start = start and relative_start(len, start) or 1
		n = n and math.min(len - start + 1, n) or (len - start + 1)

		return setmetatable({
			ptr = self.ptr + self.head + start - 1,
			length = n,
			ref = store_ref(self),
		}, slice)
	end

	--- Read `n` bytes from the buffer, or the entire buffer if `n` is not specified.
	---
	---@param n? integer
	---@return luvit.slice
	function buffer:read(n)
		local str = buffer.peek(self, n)
		self.head = self.head + #str
		return str
	end

	--- Discard `n` bytes from the front of the buffer, or discard all bytes if `n` is not specified.
	---
	---@param n? integer
	function buffer:skip(n)
		assert(n >= 0, "invalid forward offset")
		self.head = math.min(self.capacity, self.head + n)
	end

	-- #endregion
	-- #endregion

	buffer.slice = slice
	return buffer
else
end
