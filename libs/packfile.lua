local bit = require('bit')
local miniz = require('miniz')

local ffi = require('ffi')
local zero = ffi.cast('uint64_t', 0)

local object = require('object')

local function read_varsize(data, offset)
    local byte = data:byte(offset)
    local result = bit.band(byte, 0x7f) + zero
    local shift = 7
    offset = offset + 1

    while bit.band(byte, 0x80) > 0 do
        byte = data:byte(offset)
        local value = bit.lshift(bit.band(byte, 0x7f), shift)
        result = result + value

        shift = shift + 7
        offset = offset + 1
    end

    return tonumber(result), offset
end

local function read_varoffset(data, offset)
    local byte = data:byte(offset)
    local result = bit.band(byte, 0x7f) + zero
    offset = offset + 1

    while bit.band(byte, 0x80) > 0 do
        byte = data:byte(offset)

        result = bit.lshift(result + 1, 7) + bit.band(byte, 0x7f)
        offset = offset + 1
    end

    return tonumber(result), offset
end

local function read_u32(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset + 3)
    return b4 + b3 * 0x100 + b2 * 0x10000 + b1 * 0x1000000
end

local function read_u64(data, offset)
    local high = read_u32(data, offset)
    local low = read_u32(data, offset + 4)

    return low + high * 0x100000000
end

local function apply_delta_instruction(parts, delta, delta_offset, base)
    local instruction = delta:byte(delta_offset)
    delta_offset = delta_offset + 1

    if instruction < 0x80 then
        -- data instruction
        assert(instruction > 0, 'invalid data instruction')

        table.insert(parts, delta:sub(delta_offset, delta_offset + instruction - 1))
        delta_offset = delta_offset + instruction
    else
        -- copy instruction
        local copy_offset = 0
        local copy_length = 0

        if bit.band(instruction, 0x01) > 0 then
            copy_offset = delta:byte(delta_offset)
            delta_offset = delta_offset + 1
        end
        if bit.band(instruction, 0x02) > 0 then
            copy_offset = copy_offset + delta:byte(delta_offset) * 0x100
            delta_offset = delta_offset + 1
        end
        if bit.band(instruction, 0x04) > 0 then
            copy_offset = copy_offset + delta:byte(delta_offset) * 0x10000
            delta_offset = delta_offset + 1
        end
        if bit.band(instruction, 0x08) > 0 then
            copy_offset = copy_offset + delta:byte(delta_offset) * 0x1000000
            delta_offset = delta_offset + 1
        end
        if bit.band(instruction, 0x10) > 0 then
            copy_length = delta:byte(delta_offset)
            delta_offset = delta_offset + 1
        end
        if bit.band(instruction, 0x20) > 0 then
            copy_length = copy_length + delta:byte(delta_offset) * 0x100
            delta_offset = delta_offset + 1
        end
        if bit.band(instruction, 0x40) > 0 then
            copy_length = copy_length + delta:byte(delta_offset) * 0x10000
            delta_offset = delta_offset + 1
        end

        -- copy_length == 0 means 0x10000 bytes
        if copy_length == 0 then copy_length = 0x10000 end

        assert(copy_offset <= #base, 'copy offset is out of bounds')
        assert(copy_offset + copy_length <= #base, 'copy length is out of bounds')

        table.insert(parts, base:sub(1 + copy_offset, copy_offset + copy_length))
    end

    return delta_offset
end

---@class git.packfile
---@field pack_hash string
---@field fs git.storage.fs
---@field pack_fd number
---@field fanout number[]
---@field hashes string[]
---@field checksums number[]
---@field offsets number[]
---@field lengths number[]
local packfile = {}

function packfile:unload()
    self.fs.close(self.pack_fd)
end

function packfile:reload_index()
    local fs = self.fs
    local index_fd = assert(fs.open('objects/pack/pack-' .. self.pack_hash .. '.idx', 'r', 0))

    assert(fs.read(index_fd, 8, 0) == '\255tOc\0\0\0\2', 'invalid pack index signature')

    self.fanout = {}
    for i = 1, 256 do
        local offset = 4 * (i - 1)
        self.fanout[i] = read_u32(assert(fs.read(index_fd, 4, 8 + offset), 1))
    end

    local hashes_start = 8 + 4 * 256
    for i = 1, self.fanout[256] do
        local offset = 20 * (i - 1)
        local binary_hash = assert(fs.read(index_fd, 20, hashes_start + offset))
        self.hashes[i] = object.read_hash(binary_hash)

        assert(i == 1 or self.hashes[i] > self.hashes[i - 1], 'hashes are not sorted') -- check if the hashes are sorted

        -- check if the hash is in the correct fanout bucket
        local first_byte = binary_hash:byte() + 1
        assert(i <= self.fanout[first_byte] and i > (self.fanout[first_byte - 1] or 0),
               'hash is in the wrong fanout bucket')
    end

    local checksums_start = hashes_start + 20 * self.fanout[256]
    for i = 1, self.fanout[256] do
        local offset = 4 * (i - 1)
        self.checksums[i] = read_u32(assert(fs.read(index_fd, 4, checksums_start + offset)), 1)
    end

    local long_offsets = {} -- offsets[k] = long_offsets[v]
    local long_offsets_num = 0

    local offsets_start = checksums_start + 4 * self.fanout[256]
    for i = 1, self.fanout[256] do
        local offset = 4 * (i - 1)
        self.offsets[i] = read_u32(assert(fs.read(index_fd, 4, offsets_start + offset)), 1)

        if self.offsets[i] > 0x7fffffff then
            local long_offsets_index = bit.band(self.offsets[i], 0x7fffffff) + 1

            long_offsets[long_offsets_index] = i
            long_offsets_num = math.max(long_offsets_num, long_offsets_index)
        end
    end

    local long_offsets_start = offsets_start + 4 * #long_offsets
    for i = 1, long_offsets_num do
        local j = long_offsets[i]
        assert(j, 'extraneous long offset provided')

        local offset = 8 * (i - 1)
        self.offsets[j] = read_u64(assert(fs.read(index_fd, 8, long_offsets_start + offset)), 1)
    end

    local sorted_offsets = {}
    for i = 1, self.fanout[256] do sorted_offsets[i] = self.offsets[i] end

    local packfile_size = fs.fstat(self.pack_fd).size

    table.sort(sorted_offsets)
    for i = 1, self.fanout[256] do
        local start_offset = sorted_offsets[i]
        local end_offset = sorted_offsets[i + 1] or packfile_size

        self.lengths[start_offset] = end_offset - start_offset
    end

    fs.close(index_fd)
end

---@param hash string
function packfile:find_hash(hash)
    local start_byte = tonumber(hash:sub(1, 2), 16) + 1

    local hash_search_start = (self.fanout[start_byte - 1] or 0) + 1
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
    return hash_offset
end

---@param hash string
---@param repository git.repository
function packfile:read(hash, repository)
    local hash_offset = self:find_hash(hash)
    if not hash_offset then return nil end

    local file_offset = self.offsets[hash_offset]
    return self:read_at_offset(file_offset, repository)
end

local type_to_name = {'commit', 'tree', 'blob', 'tag', 'offset_delta', 'ref_delta'}

---@param pack_offset number
---@param repository git.repository
---@return string, string
function packfile:read_at_offset(pack_offset, repository)
    local pack_fd = self.pack_fd
    local fs = self.fs

    local chunk_length = self.lengths[pack_offset]
    assert(chunk_length and chunk_length >= 0, 'chunk is missing length')

    local header = assert(fs.read(pack_fd, 32, pack_offset))
    local type_and_size, header_offset = read_varsize(header, 1)
    local type = bit.rshift(bit.band(type_and_size, 0x70), 4)
    local uncompressed_size = bit.rshift(bit.band(type_and_size + zero, bit.bnot(0x7f + zero)), 3) +
                                  bit.band(type_and_size, 0x0f)

    if type == 1 or type == 2 or type == 3 or type == 4 then
        local deflated_data = assert(fs.read(pack_fd, chunk_length, pack_offset + header_offset - 1))
        local inflated_data = miniz.inflate(deflated_data, 1)

        assert(#inflated_data == uncompressed_size, 'inflated data size does not match expected size')
        return type_to_name[type], inflated_data
    elseif type == 6 or type == 7 then -- offset delta
        local base_kind, base_data

        if type == 6 then
            local base_offset, delta_header_offset = read_varoffset(header, header_offset)

            base_kind, base_data = self:read_at_offset(pack_offset - base_offset, repository)
            header_offset = delta_header_offset

            if not base_kind then error('offset delta base not found') end
        elseif type == 7 then
            local binary_ref = header:sub(header_offset, header_offset + 19)
            local reference = object.read_hash(binary_ref)

            base_kind, base_data = repository:load_raw(reference)
            header_offset = header_offset + 20

            if not base_kind then error('reference delta base not found') end
        end

        local parts = {}
        local delta_offset = 1

        local deflated_data =
            assert(fs.read(pack_fd, chunk_length - header_offset + 1, pack_offset + header_offset - 1))
        local delta_data = miniz.inflate(deflated_data, 1)

        local base_size, result_size
        base_size, delta_offset = read_varsize(delta_data, delta_offset)
        result_size, delta_offset = read_varsize(delta_data, delta_offset)

        assert(base_size == #base_data, 'base size does not match expected size')
        while delta_offset <= #delta_data do
            delta_offset = apply_delta_instruction(parts, delta_data, delta_offset, base_data)
        end

        local undeltified_data = table.concat(parts)
        assert(#undeltified_data == result_size, 'inflated data size does not match expected size')

        return base_kind, undeltified_data
    else
        error('invalid pack object type')
    end
end

local function load_packfile(fs, pack_hash)
    local pack = setmetatable({pack_hash = pack_hash, fs = fs, hashes = {}, checksums = {}, offsets = {}, lengths = {}},
                              {__index = packfile})

    pack.pack_fd = assert(fs.open('objects/pack/pack-' .. pack_hash .. '.pack', 'r', 0))
    pack:reload_index()

    return pack
end

return load_packfile
