local odb = require('odb')
local oid = require('oid')

local backend_loose = require('odb/loose')
local backend_pack = require('odb/pack')

local backendref_files = require('refdb/files')

local my_oid = oid.new('sha1')
local my_odb = odb.new(my_oid)

local my_repository_dir = '../../torvalds/linux/.git'
local my_objects_dir = my_repository_dir .. '/objects'
local my_odb_loose = backend_loose.load(my_odb, my_objects_dir)
local my_odb_pack = assert(backend_pack.load(my_odb, my_objects_dir))

local my_refdb = backendref_files.load(my_repository_dir)

my_odb:add_backend(my_odb_loose)
my_odb:add_backend(my_odb_pack)

local hash_queue = {}
local hashes_found = {}

for tag, hash in my_refdb:tags() do
    table.insert(hash_queue, hash)
end

for branch, hash in my_refdb:branches() do
    table.insert(hash_queue, hash)
end

for remote, hash in my_refdb:remotes() do
    table.insert(hash_queue, hash)
end

print('starting search')

local n, f = 0, 0
while true do
    local next_hash = table.remove(hash_queue)
    if not next_hash then
        break
    end

    if not hashes_found[next_hash] then
        local s, o = pcall(my_odb.read, my_odb, next_hash)
        -- local o = assert(my_odb:read(next_hash), 'missing object ' .. next_hash)

        if n % 10000 == 0 then
            print('enumerated ' .. n .. ' objects')
        end

        if s and o then
            n = n + 1

            hashes_found[next_hash] = true
            if o.kind == 'commit' then
                local commit = o:parse_commit()

                for _, parent in ipairs(commit.parents) do
                    table.insert(hash_queue, parent)
                end

                table.insert(hash_queue, commit.tree)
            elseif o.kind == 'tree' then
                local tree = o:parse_tree()

                for _, entry in ipairs(tree) do
                    table.insert(hash_queue, entry.hash)
                end
            elseif o.kind == 'tag' then
                local tag = o:parse_tag()
                table.insert(hash_queue, tag.object)
            end
        else
            f = f + 1
        end
    end
end

print('enumerated ' .. n .. ' objects')
print('failed to read ' .. f .. ' objects')

local x = 0
for _ in pairs(my_odb.cache) do
    x = x + 1
end

print('cached ' .. x .. ' objects')
