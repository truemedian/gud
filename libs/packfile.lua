local bit = require('bit')
local ffi = require('ffi')

local zero = ffi.cast('uint64_t', 0)

local function read_varint(data, offset)
    local byte = data:byte(offset)
    local result = bit.band(byte, 0x7f) + zero
    local shift = 7
    offset = offset + 1

    while bit.band(byte, 0x80) > 0 do
        byte = data:byte(offset)
        result = bit.lshift(result, shift)
        result = result + bit.band(byte, 0x7f)
        shift = shift + 7
        offset = offset + 1
    end

    return result, offset
end

local function read_u32(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset + 3)
    return b4 + b3 * 0x100 + b2 * 0x10000 + b1 * 0x1000000
end

local function read_u64(data, offset)
    local high = read_u32(data, offset)
    local low = read_u32(data, offset + 4)

    return bit.lshift(high + zero, 32) + low
end

---@class git.packfile
---@field fs git.storage.fs
---@field pack_fd number
---@field fanout number[]
---@field hashes string[]
---@field checksums number[]
---@field offsets number[]
local packfile = {}

---@param fs git.storage.fs
---@param pack_fd number
---@param index_fd number
local function load_packfile_from_fds(fs, pack_fd, index_fd)
    assert(fs.read(pack_fd, 8, 0) == 'PACK\0\0\0\2', 'invalid packfile signature')
    assert(fs.read(index_fd, 8, 0) == '\255tOc\0\0\0\2', 'invalid pack index signature')

    local fanout = {}
    for i = 1, 256 do
        local offset = 4 * (i - 1)
        fanout[i] = read_u32(assert(fs.read(index_fd, 4, 8 + offset), 1))
    end

    local pack_items = read_u32(assert(fs.read(pack_fd, 8, 4)))
    assert(pack_items == fanout[256], 'packfile and index mismatch')

    local index = {fanout = fanout, hashes = {}, checksums = {}, offsets = {}, pack_fd = pack_fd, fs = fs}

    local hashes_start = 8 + 4 * 256
    for i = 1, fanout[256] do
        local offset = 20 * (i - 1)
        index.hashes[i] = assert(fs.read(index_fd, 20, hashes_start + offset))
    end

    local checksums_start = hashes_start + 20 * fanout[256]
    for i = 1, fanout[256] do
        local offset = 4 * (i - 1)
        index.checksums[i] = read_u32(assert(fs.read(index_fd, 4, checksums_start + offset)), 1)
    end

    local long_offsets = {}
    local offsets_start = checksums_start + 4 * fanout[256]
    for i = 1, fanout[256] do
        local offset = 4 * (i - 1)
        index.offsets[i] = read_u32(assert(fs.read(index_fd, 4, offsets_start + offset)), 1)

        if index.offsets[i] > 0x7fffffff then long_offsets[#long_offsets + 1] = i end
    end

    local long_offsets_start = offsets_start + 4 * #long_offsets
    for _, i in ipairs(long_offsets) do
        local offset = 8 * (i - 1)
        index.offsets[i] = read_u64(assert(fs.read(index_fd, 8, long_offsets_start + offset)), 1)
    end

    fs.close(index_fd)
    return setmetatable(index, {__index = packfile})
end

---@param fs git.storage.fs
---@param pack_hash string
local function load_packfile(fs, pack_hash)
    local pack_fd, pack_err = fs.open('objects/pack/pack-' .. pack_hash .. '.pack', 'r', 0)
    assert(pack_fd, pack_err)

    local index_fd, index_err = fs.open('objects/pack/pack-' .. pack_hash .. '.idx', 'r', 0)
    if not index_fd then
        fs.close(pack_fd)
        error(index_err)
    end

    return load_packfile_from_fds(fs, pack_fd, index_fd)
end

---@param hash string
function packfile:find_offset(hash)
    local start_byte = tonumber(hash:sub(1, 2), 16) + 1

    local hash_search_start = self.fanout[start_byte - 1] or 1
    local hash_search_end = self.fanout[start_byte]

    local hash_offset = -1 -- binary search through the hashes
    while hash_search_start <= hash_search_end do
        local check_index = math.floor((hash_search_start + hash_search_end) / 2)
        local check_hash = self.hashes[check_index]

        if check_hash < hash then
            hash_search_start = check_index + 1
        elseif check_hash > hash then
            hash_search_end = check_index - 1
        else
            hash_offset = check_index
            break
        end
    end

    if hash_offset == -1 then return nil end
    return self.offsets[hash_offset]
end

---@param hash string
function packfile:read(hash)
    local offset = self:find_offset(hash)
    if not offset then return nil end

    local pack_fd = self.pack_fd
    local fs = self.fs

    local header = assert(fs.read(pack_fd, 16, offset))
    local first_byte = header:byte()

    local type = bit.rshift(bit.band(first_byte, 0x70), 4)
    local size = bit.band(first_byte, 0x0f)

    if bit.band(first_byte, 0x80) > 0 then
        local varsize, new_offset = read_varint(header, 2)
        size = size + varsize * 16

        offset = offset + new_offset
    else
        offset = offset + 1
    end

    
end
