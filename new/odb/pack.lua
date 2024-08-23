local miniz = require('miniz')
local fs = require('fs')
local common = require('common')

local object = require('../object.lua')

---@class git.odb.backend.pack : git.odb.backend
---@field objects_dir string
---@field packs table<string, git.odb.pack>
local backend_pack = {}
local backend_pack_mt = {__index = backend_pack}

local function pack_path(objects_dir, pack_hash) return objects_dir .. '/pack/pack-' .. pack_hash .. '.pack' end
local function idx_path(objects_dir, pack_hash) return objects_dir .. '/pack/pack-' .. pack_hash .. '.idx' end

---@param objects_dir string
function backend_pack.load(objects_dir)
    return setmetatable({objects_dir = assert(objects_dir, 'missing objects directory')}, backend_pack_mt)
end

---@param oid git.oid
---@return git.object|nil, string|nil
function backend_pack:read(oid) end

---@param oid git.oid
---@return git.object.kind|nil, number|string
function backend_pack:read_header(oid) end

---@param oid git.oid
---@return boolean, string|nil
function backend_pack:exists(oid) end

---@param odb git.odb
function backend_pack:refresh(odb)
    for entry in fs.scandirSync(self.objects_dir .. '/pack') do
        local pack_hash = entry.name:match('^pack%-(%x+)%.pack$')
        if pack_hash then self:_load_index(odb, pack_hash) end
    end
end

---@param odb git.odb
---@param pack_hash git.oid
function backend_pack:_load_index(odb, pack_hash)
    local idx, pack, err

    local index_path = idx_path(self.objects_dir, pack_hash)
    local packfile_path = pack_path(self.objects_dir, pack_hash)

    idx, err = fs.readFileSync(index_path)
    if err then return nil, err end

    pack, err = fs.readFileSync(packfile_path)
    if err then return nil, err end

    local index = {fanout = {}, hashes = {}, offsets = {}, lengths = {}}

    assert(idx:sub(1, 8) == '\xfftOc\x00\x00\x00\x02', 'invalid packfile index signature')

    local fanout_start = 9
    for i = 0, 255 do index.fanout[i + 1] = common.read_u32be(idx, fanout_start + i * 4) end

    local hashes_start = fanout_start + 256 * 4
    for i = 0, index.fanout[256] - 1 do
        local offset = hashes_start + i * 20

        local binhash = idx:sub(offset, offset + 19)
        index.hashes[i + 1] = odb.oid_type:bin2hex(binhash)

        assert(i == 0 or index.hashes[i + 1] > index.hashes[i], 'packfile index is not sorted')

        local first_byte = binhash:byte() + 1
        assert(i >= (index.fanout[first_byte - 1] or 0) and i < index.fanout[first_byte], 'packfile index is corrupt')
    end

    local long_offset_needed = {n = 0}

    local checksums_start = hashes_start + index.fanout[256] * 20
    local offsets_start = checksums_start + index.fanout[256] * 4
    for i = 0, index.fanout[256] - 1 do
        local offset = offsets_start + i * 4
        index.offsets[i + 1] = common.read_u32be(idx, offset)

        if index.offsets[i + 1] > 0x7fffffff then
            local long_index = bit.band(index.offsets[i + 1], 0x7fffffff)
            long_offset_needed[long_index] = i + 1
            long_offset_needed.n = math.max(long_offset_needed.n, long_index)
        end
    end

    local lengths_start = offsets_start + index.fanout[256] * 4
    for i = 0, long_offset_needed.n do
        local j = long_offset_needed[i]
        assert(j, 'packfile index has extraneous long offset')

        local offset = lengths_start + i * 8
        index.offsets[j] = common.read_u32be(idx, offset)
    end

    local sorted_offsets = {}
    for i = 1, index.fanout[256] do sorted_offsets[i] = index.offsets[i] end
    table.sort(sorted_offsets)

    for i = 1, index.fanout[256] do
        local start = sorted_offsets[i]
        local stop = sorted_offsets[i + 1] or #pack
        index.lengths[i] = stop - start
    end


end

---@param oid git.oid
---@param data string
---@param kind git.object.kind
---@return boolean, string|nil
function backend_pack:write(oid, data, kind) end

return backend_pack
