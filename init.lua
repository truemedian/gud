local repository = require('repository')
local storage = require('storage')

local fs = require('coro-fs').chroot('H:/repositories/truemedian/luvi/.git')
local this_storage = storage(fs)
local repo = repository(this_storage)
-- local repo = require('git').mount(fs)

local n = 0
local function recursively_iterate(r, hash)
    local kind, obj = r:load(hash)
    -- local kind, obj = r.loadAny(hash)

    n = n + 1
    if kind == 'commit' then
        recursively_iterate(r, obj.tree)

        for _, parent in ipairs(obj.parents) do recursively_iterate(r, parent) end
    elseif kind == 'tree' then
        for _, entry in ipairs(obj) do if entry.kind ~= 'commit' then recursively_iterate(r, entry.hash) end end
    elseif kind == 'blob' then
        -- nothing
    elseif kind == 'tag' then
        recursively_iterate(r, obj.object)
    else
        error('unknown object type: ' .. tostring(kind))
    end
end

local p = require('p')
local start = os.clock()
p.start('i0a')

for k, v in repo:tags() do
    print(k, v)
    recursively_iterate(repo, v)
end
-- for k, v in repo.leaves('refs/tags') do
--     recursively_iterate(repo, repo.getRef('refs/tags/' .. k))
-- end

for k, v in repo:branches() do
    print(k, v)
    recursively_iterate(repo, v)
end
-- for k, v in repo.leaves('refs/heads') do
--     recursively_iterate(repo, repo.getRef('refs/heads/' .. k))
-- end

local stop = os.clock()
local taken = stop - start
print(taken, n, taken / n * 1000)
p.stop()
