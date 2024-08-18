local object = require('object')

---@class git.repository
---@field storage git.storage
local repository = {}

function repository:load(hash)
    local loose_path = 'objects/' .. hash:sub(1, 2) .. '/' .. hash:sub(3)
    local loose_object = self.storage:read(loose_path)
    if not loose_object then end

    return object.decode(self.storage:read(hash))
end

function repository:getReference(ref)
    if ref:sub(1, 5) ~= 'refs/' then
        return self:getReference('refs/heads/' .. ref) or self:getReference('refs/tags/' .. ref)
    end

    local hash = self.storage:read(ref)
    if hash then return object.read_hash(hash) end

    local packed_refs = self.storage:read('packed-refs')
    if packed_refs then
        local packed_hash = string.find(packed_refs, ref, 1, true)

        if packed_hash then
            local start = packed_hash - 41
            local stop = packed_hash - 2
            return object.read_hash(packed_refs:sub(start, stop))
        end
    end

    return nil
end

return function(storage)
    return setmetatable({storage = assert(storage)}, {__index = repository}) -- create wrapped storage
end
