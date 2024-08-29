local bit = require('bit')

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

---@alias git.object.kind 'commit'|'tree'|'blob'|'tag'
---@class git.object
---@field kind git.object.kind
---@field data string
---@field oid git.oid
---@field odb git.odb
local object = {}
local object_mt = {__index = object}

---@param odb git.odb
---@param kind git.object.kind
---@param data string
---@param oid git.oid
---@return git.object
function object.create(odb, kind, data, oid)
    assert(odb.oid_type:digest(data, kind) == oid, 'object data does not match oid')

    return setmetatable({odb = odb, kind = kind, data = data, oid = oid}, object_mt)
end

function object:parse()
    if self.kind == 'blob' then
        return self.data
    elseif self.kind == 'tree' then
        return self:parse_tree()
    elseif self.kind == 'commit' then
        return self:parse_commit()
    elseif self.kind == 'tag' then
        return self:parse_tag()
    end
end

function object:parse_tree()
    assert(self.kind == 'tree', 'object is not a tree')

    local tree = {}
    local pos = 1

    local pattern = '^([0-7]+) ([^%z]+)%z(' .. string.rep('.', self.odb.oid_type.bin_length) .. ')()'
    while pos <= #self.data do
        local mode, name, oid, after = self.data:match(pattern, pos)
        assert(mode, 'invalid tree format')

        mode = tonumber(mode, 8)
        table.insert(tree, {mode = mode, name = name, hash = self.odb.oid_type:bin2hex(oid), kind = mode_to_name(mode)})

        pos = after
    end

    assert(pos == #self.data + 1, 'malformed tree object')
    return tree
end

function object:parse_commit()
    assert(self.kind == 'commit', 'object is not a commit')

    local commit = {parents = {}}
    local pos = 1
    local stop = self.data:find('\n\n', pos, true)

    while pos <= stop do
        local name, value_start = self.data:match('^(%S+) ()', pos)
        assert(value_start, 'invalid commit format')

        local value_end = self.data:match('\n()[%S\n]', value_start)
        if not value_end then
            value_end = stop
        end

        local value = self.data:sub(value_start, value_end - 2)
        pos = value_end

        if name == 'tree' then
            commit.tree = value
        elseif name == 'parent' then
            table.insert(commit.parents, value)
        elseif name == 'author' then
            commit.author = decode_person(value)
        elseif name == 'committer' then
            commit.committer = decode_person(value)
        elseif name == 'gpgsig' then
            commit.gpgsig = value:gsub('\n ', '\n')
        elseif name == 'HG:rename-source' then
            -- ignore
        elseif name == 'mergetag' then
            -- ignore
        else
            error('unknown commit field: ' .. name)
        end
    end

    assert(commit.tree, 'missing tree field in commit object')
    assert(commit.author, 'missing author field in commit object')
    assert(commit.committer, 'missing committer field in commit object')

    commit.message = self.data:sub(stop + 1)
    return commit
end

function object:parse_tag()
    assert(self.kind == 'tag', 'object is not a tag')

    local tag = {}
    local pos = 1
    local _, stop = self.data:find('\n\n', pos, true)

    while pos < stop do
        local name, value_start = self.data:match('^(%w+) ()', pos)
        assert(value_start, 'invalid tag format')

        local value_end = self.data:match('\n()%w', value_start)
        if not value_end then
            value_end = stop
        end

        local value = self.data:sub(value_start, value_end - 2)
        pos = value_end

        if name == 'object' then
            tag.object = value
        elseif name == 'type' then
            tag.type = value
        elseif name == 'tag' then
            tag.tag = value
        elseif name == 'tagger' then
            tag.tagger = decode_person(value)
        else
            error('unknown tag field: ' .. name)
        end
    end

    assert(tag.object, 'missing object field in tag object')
    assert(tag.type, 'missing type field in tag object')
    assert(tag.tagger, 'missing tagger field in tag object')
    assert(tag.tag, 'missing tag field in tag object')

    tag.message = self.data:sub(stop + 1)
    return tag
end

return object
