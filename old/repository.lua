local openssl = require('openssl')

local object = require('object')
local packfile = require('packfile')
local miniz = require('miniz')

---@field storage git.storage
---@field packs table<string, git.packfile>
local repository = {}

function repository:reload_index()
    self.packs = {}
    if not self.storage:access('objects/pack') then return end

    for name in self.storage:leaves('objects/pack') do
        if name:sub(-5) == '.pack' then
            local hash = name:sub(6, -6)

            local pack = packfile(self.storage, hash)
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
        local inflated = miniz.inflate(loose_data, 1)
        assert(openssl.digest.digest('sha1', inflated) == hash, 'object does not match hash')

        local kind, data = object.deframe(inflated)
        return kind, data
    end

    for _, pack in pairs(self.packs) do
        local kind, data = pack:read(hash, self)

        if kind and data then
            local enframed = object.enframe(kind, data)
            assert(openssl.digest.digest('sha1', enframed) == hash, 'object does not match hash')

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
    local function iterate()
        for name in self.storage:leaves('refs/heads') do
            local hash = self.storage:read('refs/heads/' .. name)

            if hash then coroutine.yield(name, object.read_hash(hash)) end
        end

        local packed_refs = self.storage:read('packed-refs')
        if not packed_refs then return end

        for hash, name in packed_refs:gmatch('(%x+) refs/heads/(%S+)\n') do
            coroutine.yield(name, object.read_hash(hash))
        end
    end

    return coroutine.wrap(iterate)
end

function repository:tags()
    local function iterate()
        for name in self.storage:leaves('refs/tags') do
            local hash = self.storage:read('refs/tags/' .. name)

            if hash then coroutine.yield(name, object.read_hash(hash)) end
        end

        local packed_refs = self.storage:read('packed-refs')
        if not packed_refs then return end

        for hash, name in packed_refs:gmatch('(%x+) refs/tags/(%S+)\n') do
            coroutine.yield(name, object.read_hash(hash))
        end
    end

    return coroutine.wrap(iterate)
end

function repository:remote_branches()
    local function iterate()
        for remote_name in self.storage:leaves('refs/remotes') do
            for name in self.storage:leaves('refs/remotes/' .. remote_name) do
                local remote_and_name = remote_name .. '/' .. name
                local hash = self.storage:read('refs/remotes/' .. remote_and_name)

                if hash then
                    if hash:sub(1, 5) == 'ref: ' then
                        local other = self.storage:read(hash:sub(6))
                        if other then coroutine.yield(remote_and_name, object.read_hash(other)) end
                    else
                        coroutine.yield(remote_and_name, object.read_hash(hash))
                    end
                end
            end
        end

        local packed_refs = self.storage:read('packed-refs')
        if not packed_refs then return end

        for hash, name in packed_refs:gmatch('(%x+) refs/remotes/(%S+)\n') do
            coroutine.yield(name, object.read_hash(hash))
        end
    end

    return coroutine.wrap(iterate)
end

return function(storage)
    local repo = setmetatable({storage = assert(storage), packs = {}}, {__index = repository})

    repo:reload_index()
    return repo
end
