local has_lj_buffer, lj_buffer = pcall(require, "string.buffer")
local has_ffi, ffi = pcall(require, "ffi")

local function escape_pattern(str)
	return (str:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

---@type luvit.buffer
local buffer = {}
buffer.__index = buffer

if has_lj_buffer then
	function buffer.new(size)
		return setmetatable({ lj_buffer.new(size) }, buffer)
	end

	function buffer:__len()
		return #self[1]
	end

	function buffer:reset()
		return self[1]:reset()
	end

	function buffer:free()
		return self[1]:free()
	end

	function buffer:write(str)
		if #self[1] == 0 then
			return self[1]:set(str)
		end

		return self[1]:put(str)
	end

	function buffer:read(n)
		return self[1]:get(n)
	end

	function buffer:skip(n)
		return self[1]:skip(n)
	end

	if has_ffi then
		ffi.cdef([[
			void* memchr(const void* ptr, int ch, size_t count);
			int memcmp(const void* s1, const void* s2, size_t n);
		]])

		-- avoids issues when statically linked on windows
		local C = ffi.os == "Windows" and ffi.load("msvcrt") or ffi.C

		function buffer:peek(n, start)
			local ptr, len = self[1]:ref()

			start = start or 0
			len = math.min(len, n or len)
			return ffi.string(ptr + start, math.max(len - start, 0))
		end

		function buffer:find_first(substr, start)
			local ptr, len = self[1]:ref()
			start = start or 0

			local sublen = #substr
			local chr = substr:byte(1)

			if #substr == 0 then
				return nil
			elseif #substr == 1 then
				local res = C.memchr(ptr + start, chr, len - start)
				if res == nil then
					return nil
				end

				return tonumber(ffi.cast("uintptr_t", res) - ffi.cast("uintptr_t", ptr)) + 1
			end

			local i = start
			while i <= len - sublen do
				local next_match = C.memchr(ptr + i, chr, len - i - sublen + 1)
				if next_match == nil then
					return nil
				end

				i = tonumber(ffi.cast("uintptr_t", next_match) - ffi.cast("uintptr_t", ptr))
				if C.memcmp(next_match, substr, sublen) == 0 then
					return i + 1
				end
			end
		end

		function buffer:find_first_of(matches, start)
			local ptr, len = self[1]:ref()
			start = start or 0

			for i = start, len - 1 do
				for j = 1, #matches do
					if ptr[i] == matches:byte(j) then
						return i + 1
					end
				end
			end
		end
	else
		function buffer:peek(n, start)
			local whole = tostring(self[1])
			start = (start or 0) + 1
			local stop = n and (start + n - 1) or nil
			return whole:sub(start, stop)
		end

		function buffer:find_first(substr, start)
			local whole = tostring(self[1])
			start = (start or 0) + 1
			return whole:find(substr, start, true)
		end

		function buffer:find_first_of(matches, start)
			local whole = tostring(self[1])
			start = (start or 0) + 1
			return whole:find("[" .. escape_pattern(matches) .. "]", start)
		end
	end
elseif has_ffi then
	ffi.cdef([[
	   void free(void *ptr);
	   void *realloc(void *ptr, size_t size);
	   void *memmove(void *dest, const void *src, size_t n);
	]])

	-- avoids issues when statically linked on windows
	local C = ffi.os == "Windows" and ffi.load("msvcrt") or ffi.C

	function buffer.new(size)
		local ptr = nil
		if size and size > 0 then
			ptr = assert(C.malloc(size), "not enough memory")
			ptr = ffi.gc(ffi.cast("unsigned char*", ptr), C.free)
		end

		return setmetatable({ ptr, 0, 0, 0 }, buffer)
	end

	function buffer:__len()
		return self[4] - self[3]
	end

	function buffer:reset()
		self[3] = 0
		self[4] = 0
	end

	function buffer:free()
		C.free(ffi.gc(self[1], nil))
		self[2] = 0
		self[3] = 0
		self[4] = 0
	end

	function buffer:write(str)
		local n = #str

		local c, r, w = self[2], self[3], self[4]
		local required = w - r + n

		if required >= c then
			local new_size = math.max(32, c)
			while required >= new_size do
				new_size = new_size * 2
			end
			local ptr = assert(C.realloc(self[1], new_size), "not enough memory")

			if self[1] then
				ffi.gc(self[1], nil)
			end
			self[1] = ffi.gc(ffi.cast("unsigned char*", ptr), C.free)
			self[2] = new_size
		end

		if r ~= 0 then
			local adj = w - r

			C.memmove(self[1], self[1] + r, adj)

			w = adj
			self[3] = 0
		end

		ffi.copy(self[1] + w, str, n)
		self[4] = w + n
	end

	function buffer:read(n)
		local str = buffer.peek(self, n)
		self[3] = self[3] + #str
		return str
	end

	function buffer:skip(n)
		assert(n >= 0, "invalid forward offset")
		self[3] = math.min(self[2], self[3] + n)
	end

	function buffer:peek(n, start)
		start = start or 0
		n = math.min(n or math.huge, self[2] - self[3])

		return ffi.string(self[1] + self[3] + start, n - start)
	end

	function buffer:find_first(substr, start)
		local whole = self:peek(nil, start)
		return whole:find(substr, 1, true) + (start or 0)
	end

	function buffer:find_first_of(matches, start)
		local whole = self:peek(nil, start)
		return whole:find("[" .. escape_pattern(matches) .. "]", 1) + (start or 0)
	end
else
	function buffer.new(size)
		return setmetatable({ "" }, buffer)
	end

	function buffer:__len()
		local n = 0
		for i = 1, rawlen(self) do
			n = n + #self[i]
		end
		return n
	end

	function buffer:reset()
		return self:free()
	end

	function buffer:free()
		for i = 1, rawlen(self) do
			self[i] = nil
		end
	end

	function buffer:write(str)
		return table.insert(self, str)
	end

	function buffer:read(n)
		local str = self:peek(n)
		self:skip(n)
		return str
	end

	function buffer:skip(n)
		if not n then
			return self:reset()
		end

		for i = 1, rawlen(self) do
			if n <= #self[i] then
				self[i] = self[i]:sub(n + 1)
				return
			else
				n = n - #self[i]
				self[i] = ""
			end
		end
	end

	local function compact(tbl)
		if rawlen(tbl) > 1 then
			tbl[1] = table.concat(tbl)
			for j = 2, rawlen(tbl) do
				tbl[j] = nil
			end
		end
	end

	function buffer:peek(n, i)
		compact(self)

		i = i or 0
		if n then
			return self[1]:sub(i + 1, n)
		end
		if i > 0 then
			return self[1]:sub(i + 1)
		end
		return self[1]
	end

	function buffer:find_first(substr, start)
		compact(self)

		start = (start or 0) + 1
		return self[1]:find(substr, start, true)
	end

	function buffer:find_first_of(matches, start)
		compact(self)

		start = (start or 0) + 1
		return self[1]:find("[" .. escape_pattern(matches) .. "]", start)
	end
end

return buffer
