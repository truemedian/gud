---@meta

---@class luvit.slice
local slice = {}
slice.__index = slice

--- Initialize a new slice with a given string or another slice.
---
---@param str string|luvit.slice
---@return luvit.slice
function slice.new(str) end

--- Get the byte value at index `i`, or between indices `i` and `j` (inclusive).
---
---@param self luvit.slice
---@param i integer
---@param j? integer
---@return integer ...
function slice.byte(self, i, j) end

--- Get the length of the slice in bytes.
---
---@param self luvit.slice
---@return integer
function slice.len(self) end
slice.__len = slice.len

--- Get a new slice representing the bytes between indices `i` and `j` (inclusive).
---
---@param self luvit.slice
---@param i integer
---@param j? integer
---@return luvit.slice
function slice.sub(self, i, j) end

--- Return the index of the first occurrence of `substring` in the slice, or `nil` if not found.
--- The search starts at the optional index `init`, or at the beginning of the slice if `init` is not specified.
---
---@param self luvit.slice
---@param substring string|luvit.slice
---@param init? integer
---@return integer?
function slice.find(self, substring, init) end

--- Return the index of the first occurrence any item of `substring` in the slice, or `nil` if not found.
--- The search starts at the optional index `init`, or at the beginning of the slice if `init` is not specified.
---
---@param self luvit.slice
---@param substring string|luvit.slice
---@param init? integer
---@return integer?
function slice.find_any(self, substring, init) end

--- Return `true` if the contents of this slice is equal to the contents of `other`, `false` otherwise.
---
---@param self string|luvit.slice
---@param other string|luvit.slice
---@return boolean
function slice.equals(self, other) end
slice.__eq = slice.equals

--- Return the string representation of the slice.
---
---@param self luvit.slice
---@return string
function slice.tostring(self) end
slice.__tostring = slice.tostring

---@class luvit.buffer
local buffer = {}
buffer.__index = buffer

--- Initialize a new buffer with a given size, or empty.
---
---@param size? integer
---@return luvit.buffer
function buffer.new(size) end

--- Get the length of the buffer in bytes.
---
---@return integer
function buffer:__len() end

--- Set the buffer to the given string, replacing any existing contents.
---
---@param str string|luvit.slice|luvit.buffer
function buffer:set(str) end

--- Reset the buffer to empty while keeping the allocated capacity.
---
function buffer:reset() end

--- Reset the buffer to empty and free any allocated memory.
---
function buffer:free() end

--- Append `str` to the buffer.
---@param str string|luvit.slice|luvit.buffer
function buffer:write(str) end

--- Read `n` bytes from the buffer, or the entire buffer if `n` is not specified.
---
---@param n? integer
---@return luvit.slice
function buffer:read(n) end

--- Discard `n` bytes from the front of the buffer, or discard all bytes if `n` is not specified.
---
---@param n? integer
function buffer:skip(n) end

--- Peek at `n` bytes offset `i` bytes from the beginning of the buffer without consuming them, or peek at the
--- entire buffer if `n` is not specified.
---
---@param n? integer number of bytes to peek at
---@param start? integer offset from the beginning of the buffer, 0 means the beginning
---@return luvit.slice
function buffer:peek(n, start) end
