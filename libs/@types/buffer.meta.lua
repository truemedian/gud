---@meta

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

--- Reset the buffer to empty while keeping the allocated capacity.
---
function buffer:reset() end

--- Reset the buffer to empty and free any allocated memory.
---
function buffer:free() end

--- Append `str` to the buffer.
---@param str string
function buffer:write(str) end

--- Read `n` bytes from the buffer, or the entire buffer if `n` is not specified.
---
---@param n? integer
---@return string
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
---@return string
function buffer:peek(n, start) end

--- Finds the first occurrence of `substr` in the buffer, or `nil` if not found. The search starts
--- at the optional index `start`, or at the beginning of the buffer if `start` is not specified.
---
---@param substr string
---@param start? integer offset from the beginning of the buffer, 0 means the beginning
---@return integer?
function buffer:find_first(substr, start) end

--- Finds the first character equal to one of the characters in the given character sequence. The search starts
--- at the optional index `i`, or at the beginning of the buffer if `i` is not specified.
---
---@param matches string
---@param start? integer offset from the beginning of the buffer, 0 means the beginning
---@return integer?
function buffer:find_first_of(matches, start) end
