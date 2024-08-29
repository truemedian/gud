--- A buffer that can store data in chunks. Necessary to store large packfiles in memory.
---@class git.buffer
---@field parts string[]
---@field offsets number[]
---@field size number
local buffer = {}
local buffer_mt = {__index = buffer}

--- Creates a new buffer.
---@return git.buffer
function buffer.new()
    return setmetatable({parts = {}, offsets = {}}, buffer_mt)
end

--- Appends data to the buffer.
---@param data string
function buffer:add(data)
    local i = #self.parts + 1
    self.parts[i] = data

    if i == 1 then
        self.offsets[i] = 1
    else
        self.offsets[i] = self.offsets[i - 1] + #self.parts[i - 1]
    end

    self.size = (self.size or 0) + #data
end

--- Returns a substring of the buffer.
---@param i number
---@param j? number
---@return string
function buffer:sub(i, j)
    if not j then
        j = self.size
    end

    assert(i >= 1 and i <= self.size, 'sub index out of bounds i=' .. i .. ' size=' .. self.size)
    assert(j >= 1 and j <= self.size, 'sub index out of bounds j=' .. j .. ' size=' .. self.size)
    assert(i <= j, 'sub index out of bounds i=' .. i .. ' > j=' .. j)

    local parts = {}

    local start = 1 -- find the first part that contains the start of the range
    while i > self.offsets[start] + #self.parts[start] - 1 do
        start = start + 1
    end

    local stop = start -- find the last part that contains the end of the range
    while j > self.offsets[stop] + #self.parts[stop] - 1 do
        stop = stop + 1
    end

    local current_offset = self.offsets[start]
    local current_i = i - current_offset + 1
    local current_j = j - current_offset + 1
    if start == stop then
        return self.parts[start]:sub(current_i, current_j)
    end

    table.insert(parts, self.parts[start]:sub(current_i))

    for k = start + 1, stop - 1 do
        table.insert(parts, self.parts[k])
    end

    current_offset = self.offsets[stop]
    current_j = j - current_offset + 1

    table.insert(parts, self.parts[stop]:sub(1, current_j))

    return table.concat(parts)
end

--- Returns the bytes at the given index.
---@param i number
---@param j? number
function buffer:byte(i, j)
    if not j then
        j = i
    end

    return self:sub(i, j):byte(1, j - i + 1)
end

return buffer
