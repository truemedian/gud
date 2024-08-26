local miniz = require('miniz')
local fs = require('fs')
local common = require('common')

local object = require('../object.lua')

---@class git.odb.backend.one_pack : git.odb.backend
---@field objects_dir string
---@field pack_hash string
---@field packfile string
---@field fanout number[]
---@field hashes git.oid[]
---@field offsets number[]
---@field lengths number[]
local backend_onepack = {}
local backend_onepack_mt = {__index = backend_onepack}

local function pack_path(objects_dir, pack_hash) return objects_dir .. '/pack/pack-' .. pack_hash .. '.pack' end
local function idx_path(objects_dir, pack_hash) return objects_dir .. '/pack/pack-' .. pack_hash .. '.idx' end

---@param arr git.oid[]
---@param value git.oid
---@param start integer
---@param stop integer
local function binsearch(arr, value, start, stop)
    while start < stop do
        local mid = math.floor((start + stop) / 2)
        if arr[mid] < value then
            start = mid + 1
        else
            stop = mid
        end
    end

    return start
end

---@param objects_dir string
function backend_onepack.load(odb, objects_dir)
    local self = setmetatable({objects_dir = assert(objects_dir, 'missing objects directory')}, backend_onepack_mt)
    local idx, pack, err

    local index_path = idx_path(self.objects_dir, self.pack_hash)
    local packfile_path = pack_path(self.objects_dir, self.pack_hash)

    idx, err = fs.readFileSync(index_path)
    if not idx then return nil, err end

    pack, err = fs.readFileSync(packfile_path)
    if not pack then return nil, err end

    self.packfile = pack
    assert(idx:sub(1, 8) == '\xfftOc\x00\x00\x00\x02', 'invalid packfile index signature')

    local fanout_start = 9
    for i = 0, 255 do self.fanout[i + 1] = common.read_u32be(idx, fanout_start + i * 4) end

    local hashes_start = fanout_start + 256 * 4
    for i = 0, self.fanout[256] - 1 do
        local offset = hashes_start + i * 20

        local binhash = idx:sub(offset, offset + 19)
        self.hashes[i + 1] = odb.oid_type:bin2hex(binhash)

        assert(i == 0 or self.hashes[i + 1] > self.hashes[i], 'packfile index is not sorted')

        local first_byte = binhash:byte() + 1
        assert(i >= (self.fanout[first_byte - 1] or 0) and i < self.fanout[first_byte], 'packfile index is corrupt')
    end

    local long_offset_needed = {n = 0}

    local checksums_start = hashes_start + self.fanout[256] * 20
    local offsets_start = checksums_start + self.fanout[256] * 4
    for i = 0, self.fanout[256] - 1 do
        local offset = offsets_start + i * 4
        self.offsets[i + 1] = common.read_u32be(idx, offset)

        if self.offsets[i + 1] > 0x7fffffff then
            local long_index = bit.band(self.offsets[i + 1], 0x7fffffff)
            long_offset_needed[long_index] = i + 1
            long_offset_needed.n = math.max(long_offset_needed.n, long_index)
        end
    end

    local lengths_start = offsets_start + self.fanout[256] * 4
    for i = 0, long_offset_needed.n do
        local j = long_offset_needed[i]
        assert(j, 'packfile index has extraneous long offset')

        local offset = lengths_start + i * 8
        self.offsets[j] = common.read_u32be(idx, offset)
    end

    local sorted_offsets = {}
    for i = 1, self.fanout[256] do sorted_offsets[i] = self.offsets[i] end
    table.sort(sorted_offsets)

    for i = 1, self.fanout[256] do
        local start = sorted_offsets[i]
        local stop = sorted_offsets[i + 1] or #pack
        self.lengths[i] = stop - start
    end

    return self
end

---@param oid git.oid
---@return git.object|nil, string|nil
function backend_onepack:read(odb, oid) end

---@param oid git.oid
---@return git.object.kind|nil, number|string
function backend_onepack:read_header(oid)
    local offset = self:_find_offset(oid)
    if not offset then return nil, 'object not found in database' end

    
end

function backend_onepack:_read_at_offset(odb, offset)
    local chunk_length = assert(self.lengths[offset], 'packfile index missing length at ' .. offset)

    
end

---@param oid git.oid
---@return boolean, string|nil
function backend_onepack:exists(oid)
    return self:_find_offset(oid) ~= nil
end

function backend_onepack:_find_offset(oid)
    local first_byte = tonumber(oid:sub(1, 2), 16) + 1

    local start = self.fanout[first_byte - 1] or 0
    local stop = self.fanout[first_byte]

    local i = binsearch(self.hashes, oid, start, stop)
    if i == stop then return nil end

    return self.offsets[i + 1]
end

---@param odb git.odb
function backend_onepack:refresh(odb) end

---@param oid git.oid
---@param data string
---@param kind git.object.kind
---@return boolean, string|nil
function backend_onepack:write(oid, data, kind)
    return false
end

return backend_onepack
