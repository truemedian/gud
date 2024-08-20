local object = require('object')
local packfile = require('packfile')

---@class git.repository
---@field storage git.storage
---@field packs table<string, git.packfile>
---@field object_cache table<string, any>
local repository = {}

function repository:reload_index()
    for _, pack in pairs(self.packs) do pack:unload() end

    self.packs = {}
    for item in self.storage.fs.scandir('objects/pack') do
        if item.name:sub(-5) == '.pack' then
            local hash = item.name:sub(6, -6)

            local pack = packfile(self.storage.fs, hash)
            self.packs[hash] = pack
        end
    end
end

---@param hash string
---@return string|nil
---@return any|nil
function repository:load(hash)
    local kind, data = self:load_raw(hash)
    if not kind or not data then return end

    local parsed = object.decode(data, kind)
    return kind, parsed
end

---@param hash string
---@return string|nil
---@return string|nil
function repository:load_raw(hash)
    local loose_path = 'objects/' .. hash:sub(1, 2) .. '/' .. hash:sub(3)
    local loose_data = self.storage:read(loose_path)
    if loose_data then
        local kind, data = object.deframe(loose_data)
        self.object_cache[hash] = data

        return kind, data
    end

    for _, pack in pairs(self.packs) do
        local kind, data = pack:read(hash, self)
        if kind and data then
            self.object_cache[hash] = data

            return kind, data
        end
    end
end

function repository:getReference(ref)
    if ref == 'HEAD' then
        local head = self.storage:read('HEAD')
        if not head then return nil end

        head = assert(head:match('ref: (.*)'), 'invalid HEAD')
        return self:getReference(head)
    end

    if ref:sub(1, 5) ~= 'refs/' then
        return self:getReference('refs/heads/' .. ref) or self:getReference('refs/tags/' .. ref)
    end

    local hash = self.storage:read(ref)
    if hash then return object.read_hash(hash) end

    local packed_refs = self.storage:read('packed-refs')
    if packed_refs then
        local start_ref = string.find(packed_refs, ref, 1, true)

        if start_ref then
            local start = start_ref - 41
            local stop = start_ref - 2
            return object.read_hash(packed_refs:sub(start, stop))
        end
    end

    return nil
end

function repository:branches()
    local scanner = self.storage:nodes('refs/heads')
    local packed_refs = self.storage:read('packed-refs')

    local pos = 1
    local function scan_packed()
        if not packed_refs then return end

        local hash, name, after = packed_refs:match('(%x+) refs/heads/(%S+)\n()', pos)
        if not hash then return end

        pos = after
        return name, object.read_hash(hash)
    end

    local scan
    local function scan_unpacked()
        local item = scanner()
        if not item then
            scan = scan_packed
            return scan()
        end

        local hash = self.storage:read('refs/heads/' .. item.name)
        if not hash then
            scan = scan_packed
            return scan()
        end

        return item.name, object.read_hash(hash)
    end

    scan = scan_unpacked
    return function() return scan() end
end

function repository:tags()
    local scanner = self.storage:nodes('refs/tags')
    local packed_refs = self.storage:read('packed-refs')

    local pos = 1
    local function scan_packed()
        if not packed_refs then return end

        local hash, name, after = packed_refs:match('(%x+) refs/tags/(%S+)\n()', pos)
        if not hash then return end

        pos = after + 1
        return name, hash
    end

    local scan
    local function scan_unpacked()
        local item = scanner()
        if not item then
            scan = scan_packed
            return scan()
        end

        local hash = self.storage:read('refs/tags/' .. item.name)
        if not hash then
            scan = scan_packed
            return scan()
        end

        return item.name, object.read_hash(hash)
    end

    scan = scan_unpacked
    return function() return scan() end
end

return function(storage)
    local repo = setmetatable({
        storage = assert(storage),
        packs = {},
        object_cache = setmetatable({}, {__mode = "kv"}),
        object_store = setmetatable({}, {__mode = "kv"})
    }, {__index = repository}) -- create wrapped storage

    repo:reload_index()
    return repo
end
