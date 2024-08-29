local odb = require('odb')
local oid = require('oid')

local backend_loose = require('odb/loose')
local backend_onepack = require('odb/one_pack')

local my_oid = oid.new('sha1')
local my_odb = odb.new(my_oid)

local my_objects_dir = '.git/objects'
local my_odb_loose = backend_loose.load(my_odb, my_objects_dir)
local my_odb_onepack = assert(backend_onepack.load(my_odb, my_objects_dir, 'f8a65e562d27b16916fe62089beb0169eaef54bf'))

my_odb:add_backend(my_odb_loose)
my_odb:add_backend(my_odb_onepack)

local hash_queue = {}
local hashes_found = {}

table.insert(hash_queue, 'fd7f1394e200b4ced12c0ca02055e42451cd0ad9')

local n = 0
while true do
    local next_hash = table.remove(hash_queue)
    if not next_hash then
        break
    end

    if not hashes_found[next_hash] then
        local o = assert(my_odb:read(next_hash), 'missing object ' .. next_hash)
        n = n + 1

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
    end
end

print('enumerated ' .. n .. ' objects')