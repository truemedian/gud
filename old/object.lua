local bit = require('bit')
local miniz = require('miniz')

local hash_length = 20 -- SHA1 hash is 20 bytes
local hash_length_hex = hash_length * 2

local bin2hex_lookup = {}
local hex2bin_lookup = {}
for i = 0, 255 do
    bin2hex_lookup[i] = string.format('%02x', i)
    hex2bin_lookup[i] = string.char(i)
end

local function bin2hex(bin)
    local hex = {}
    for i = 1, #bin do
        hex[i] = bin2hex_lookup[string.byte(bin, i)]
    end
    return table.concat(hex)
end

local function hex2bin(str)
    local bin = {}
    for i = 1, #str, 2 do
        bin[#bin + 1] = hex2bin_lookup[tonumber(str:sub(i, i + 1), 16)]
    end
    return table.concat(bin)
end

local function mode_is_tree(mode)
    return mode == 0x4000 -- 0b0100_000_000000000
end

local function mode_is_file(mode)
    return bit.band(mode, 0xF000) == 0x8000 -- 0b1000_000_XXXXXXXXX
end

local function mode_is_symlink(mode)
    return bit.band(mode, 0xF000) == 0xA000 -- 0b1010_000_XXXXXXXXX
end

local function mode_is_gitlink(mode)
    return mode == 0xE000 -- 0b1110_000_000000000
end

local function mode_to_name(mode)
    if mode_is_tree(mode) then
        return 'tree'
    elseif mode_is_file(mode) then
        return 'blob'
    elseif mode_is_symlink(mode) then
        return 'blob'
    elseif mode_is_gitlink(mode) then
        return 'commit'
    end

    return 'unknown'
end

-- remove illegal characters from strings like emails or names
local function safe(str) return str:match('^[%.,:;"\']*(.-)[%.,:;"\']*$'):gsub('[%z\n<>]', '') end

local function encode_time(time)
    assert(time.seconds, 'time.seconds must be a number')
    assert(time.offset, 'time.offset must be a number')

    assert(time.seconds > 0, 'time.seconds must be a positive number')
    assert(time.offset >= -1440 and time.offset <= 1440, 'time.offset must be between -1440 and 1440')

    return string.format('%d %+03d%02d', time.seconds, time.offset / 60, time.offset % 60)
end

local function encode_person(person)
    assert(type(person.name) == 'string', 'person.name must be a string')
    assert(type(person.email) == 'string', 'person.email must be a string')
    assert(type(person.time) == 'table', 'person.time must be a table')

    return string.format('%s <%s> %s', safe(person.name), safe(person.email), encode_time(person.time))
end

local function encode_tree(tree)
    assert(type(tree) == 'table', 'tree must be a table')

    local result = {}

    for _, entry in ipairs(tree) do
        assert(type(entry.name) == 'string', 'entry.name must be a string')
        assert(type(entry.mode) == 'number', 'entry.mode must be a number: ' .. entry.name)
        assert(type(entry.hash) == 'string' and #entry.hash == hash_length,
               'entry.hash must be a hash string: ' .. entry.name)

        local line = string.format('%o %s\0%s', entry.mode, entry.name, hex2bin(entry.hash))

        table.insert(result, line)
    end

    return table.concat(result)
end

local function encode_tag(tag)
    assert(type(tag) == 'table', 'tag must be a table')
    assert(type(tag.object) == 'string' and #tag.object == hash_length_hex, 'tag.object must be a hash string')
    assert(tag.type == 'commit' or tag.type == 'tree' or tag.type == 'blob', 'tag.type must be commit, tree or blob')
    assert(type(tag.tag) == 'string', 'tag.tag must be a string')
    assert(type(tag.tagger) == 'table', 'tag.tagger must be a persion table')
    assert(type(tag.message) == 'string', 'tag.message must be a string')

    if tag.message:sub(-1) ~= '\n' then tag.message = tag.message .. '\n' end
    return string.format('object %s\ntype %s\ntag %s\ntagger %s\n\n%s', tag.object, tag.type, tag.tag,
                         encode_person(tag.tagger), tag.message)
end

local function encode_commit(commit)
    assert(type(commit) == 'table', 'commit must be a table')
    assert(type(commit.tree) == 'string' and #commit.tree == hash_length_hex, 'commit.tree must be a hash string')
    assert(type(commit.parents) == 'table', 'commit.parents must be a table')
    assert(type(commit.author) == 'table', 'commit.author must be a persion table')
    assert(type(commit.committer) == 'table', 'commit.committer must be a persion table')
    assert(type(commit.message) == 'string', 'commit.message must be a string')

    local lines = {}
    lines[1] = string.format('tree %s', commit.tree)
    for _, parent in ipairs(commit.parents) do
        assert(type(parent) == 'string' and #parent == hash_length_hex, 'commit.parents must be a table of hash strings')
        lines[#lines + 1] = string.format('parent %s', parent)
    end
    lines[#lines + 1] = string.format('author %s\ncommitter %s', encode_person(commit.author),
                                      encode_person(commit.committer))

    if commit.gpgsig then lines[#lines + 1] = 'gpgsig ' .. commit.gpgsig:gsub('\n', '\n ') end

    lines[#lines + 1] = ''
    lines[#lines + 1] = commit.message
    return table.concat(lines, '\n')
end

local function decode_time(data)
    local seconds, offset_hr, offset_min = string.match(data, '(%d+) ([+-]%d%d)(%d%d)')
    assert(seconds, 'malformed time data')

    local offset = tonumber(offset_hr) * 60 + tonumber(offset_min)
    assert(offset >= -1440 and offset <= 1440, 'malformed time offset (must be between -1440 and 1440)')

    return {seconds = tonumber(seconds), offset = offset}
end

local function decode_person(data)
    local name, email, time = string.match(data, '([^<]+) <([^>]+)> (.+)')
    assert(name, 'malformed person data')

    return {name = name, email = email, time = decode_time(time)}
end

local hash_pattern_bin = string.rep('.', hash_length)
local tree_pattern = '^([0-7]+) ([^%z]+)%z(' .. hash_pattern_bin .. ')' -- {mode} {name}\0{hash}
local function decode_tree(data)
    local pos, len = 1, #data

    local tree = {}
    while pos <= len do
        local _, after, mode, name, hash = string.find(data, tree_pattern, pos)
        assert(after, 'malformed tree object')

        mode = tonumber(mode, 8)
        table.insert(tree, {
            mode = mode,
            name = name,
            hash = bin2hex(hash),
            kind = mode_to_name(mode) -- 
        })

        pos = after + 1
    end

    assert(pos == len + 1, 'malformed tree object')
    return tree
end

local tag_pattern = '^object ([0-9a-fA-F]+)\ntype (%w+)\ntag ([^\n]+)\ntagger ([^\n]+)\n\n(.+)$'
local function decode_tag(data)
    local object, type, tag, tagger, message = string.match(data, tag_pattern)
    assert(object, 'malformed tag object')

    assert(#object == hash_length_hex, 'malformed tag object')
    assert(type == 'commit' or type == 'tree' or type == 'blob', 'malformed tag type')

    return {object = object, type = type, tag = tag, tagger = decode_person(tagger), message = message}
end

local function decode_commit(data)
    local pos, len = 1, #data

    local commit = {parents = {}}
    while pos <= len do
        local _, after, key, value = string.find(data, '^(%w+) ([^\n]+)\n', pos)
        if not after then
            commit.message = data:sub(pos)
            break
        end

        if key == 'tree' then
            assert(not commit.tree, 'malformed commit object')

            commit.tree = value
        elseif key == 'parent' then
            table.insert(commit.parents, value)
        elseif key == 'author' then
            assert(not commit.author, 'malformed commit object')

            commit.author = decode_person(value)
        elseif key == 'committer' then
            assert(not commit.committer, 'malformed commit object')

            commit.committer = decode_person(value)
        elseif key == 'gpgsig' then
            assert(not commit.gpgsig, 'malformed commit object')
            local before = after - #value

            if value == '-----BEGIN PGP SIGNATURE-----' then
                _, after = string.find(data, '-----END PGP SIGNATURE-----\n ?', after)
            elseif value == '-----BEGIN SSH SIGNATURE-----' then
                _, after = string.find(data, '-----END SSH SIGNATURE-----\n ?', after)
            else
                error('malformed gpgsig')
            end

            commit.gpgsig = data:sub(before, after - 1):gsub('\n ', '\n')
        else
            error('malformed commit object: unknown field ' .. key)
        end

        pos = after + 1
    end

    return commit
end

---@param kind string
---@param data string
---@return string
local function enframe(kind, data)
    assert(type(kind) == 'string', 'kind must be a string')
    assert(type(data) == 'string', 'data must be a string')

    return string.format('%s %d\0%s', kind, #data, data)
end

---@param framed string
---@return string, string
local function deframe(framed)
    assert(type(framed) == 'string', 'framed must be a string')

    local _, after, kind, len = string.find(framed, '^(%S+) (%d+)%z')
    if not kind then p(framed) end
    assert(kind, 'malformed frame')

    local data = framed:sub(after + 1)
    assert(#data == tonumber(len), 'malformed frame')
    return kind, data
end

---@param kind string
---@param data any
---@return string
local function encode(kind, data)
    assert(type(data) == 'string', 'data must be a string')

    local encoded

    if kind == 'commit' then
        encoded = encode_commit(data)
    elseif kind == 'tree' then
        encoded = encode_tree(data)
    elseif kind == 'tag' then
        encoded = encode_tag(data)
    elseif kind == 'blob' then
        assert(type(data) == 'string', 'blob data must be a string')

        encoded = data
    else
        error('unknown object kind: ' .. kind)
    end

    local framed = enframe(kind, encoded)
    local compressed = miniz.compress(framed)
    return compressed
end

---@param data string
---@param kind string
---@return any
local function decode(data, kind)
    assert(type(data) == 'string', 'data must be a string')
    assert(type(kind) == 'string', 'kind must be a string')

    local decoded
    if kind == 'commit' then
        decoded = decode_commit(data)
    elseif kind == 'tree' then
        decoded = decode_tree(data)
    elseif kind == 'tag' then
        decoded = decode_tag(data)
    elseif kind == 'blob' then
        decoded = data
    else
        error('unknown object kind: ' .. kind)
    end

    return decoded
end

--- Reads a hash from a string. The hash can be in binary or hex format.
--- @param data string
--- @return string
local function read_hash(data)
    if #data == hash_length then
        return bin2hex(data)
    else
        local line = data:match('^([^\n]+)')
        if #line == hash_length * 2 then
            if line:match('[^0-9a-fA-F]') then error('malformed hash') end

            return line
        else
            error('malformed hash')
        end
    end
end

--- Writes a hash to a either binary or hex format.
--- @param hash string
--- @param is_hex boolean
--- @return string
local function write_hash(hash, is_hex)
    assert(#hash == hash_length * 2, 'hash must be ' .. (hash_length * 2) .. ' bytes')

    if not is_hex then
        return bin2hex(hash)
    else
        return hash
    end
end

return {
    encode = encode,
    decode = decode,
    read_hash = read_hash,
    write_hash = write_hash,
    deframe = deframe,
    enframe = enframe
}
