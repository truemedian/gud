local repository = require('repository')
local storage = require('storage')

local this_storage = storage('H:/repositories/truemedian/zig/.git')
local repo = repository(this_storage)
-- local repo = require('git').mount(fs)

local tot = 0
for k, v in pairs(repo.packs) do tot = tot + v.fanout[256] end

local checked = {}
local to_check = {}

local n = 0
local function recursively_iterate(r, hash)
    -- if n > 100000 then return end

    if checked[hash] then return end
    checked[hash] = true

    local kind, obj = r:load(hash)
    -- local kind, obj = r.loadAny(hash)

    n = n + 1
    if kind == 'commit' then
        table.insert(to_check, obj.tree)
        -- recursively_iterate(r, obj.tree)

        for _, parent in ipairs(obj.parents) do
            table.insert(to_check, parent)
            -- recursively_iterate(r, parent)
        end
    elseif kind == 'tree' then
        for _, entry in ipairs(obj) do
            if entry.kind ~= 'commit' then
                table.insert(to_check, entry.hash)
                -- recursively_iterate(r, entry.hash)
            end
        end
    elseif kind == 'blob' then
        -- nothing
    elseif kind == 'tag' then
        -- recursively_iterate(r, obj.object)
        table.insert(to_check, obj.object)
    else
        error('unknown object type: ' .. tostring(kind))
    end

    if n % 10000 == 0 then print(n, #to_check) end
end

-- local p = require('jit.p')
-- p.start('F3i0a')

print('start', tot)
local start = os.clock()

for k, v in repo:tags() do
    print(k, v)
    recursively_iterate(repo, v)
end

for k, v in repo:branches() do
    print(k, v)
    recursively_iterate(repo, v)
end

for k, v in repo:remote_branches() do
    print(k, v)
    recursively_iterate(repo, v)
end

-- for k, v in repo.leaves('refs/tags') do
--     recursively_iterate(repo, repo.getRef('refs/tags/' .. k))
-- end

-- for k, v in repo.leaves('refs/heads') do
--     recursively_iterate(repo, repo.getRef('refs/heads/' .. k))
-- end

while #to_check > 0 do recursively_iterate(repo, table.remove(to_check, #to_check)) end

local stop = os.clock()
local taken = stop - start
print(taken, n, taken / n * 1000)
-- p.stop()
