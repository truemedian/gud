local class = require('class')

local object = require('git/object')

local sort = table.sort
local floor = math.floor

--- @class std.git.object.tree.entry
--- @field mode integer
--- @field name string
--- @field oid std.git.oid

--- @class std.git.object.tree : std.git.object, std.class<std.git.object.tree>
--- @field entries std.git.object.tree.entry[]
local tree = class.new('std.git.object.tree', object)
tree.kind = 'tree'

--- Returns the permission bits of a tree entry mode.
---
--- The low 3 bits represent the RWX permissions of any user.
--- The middle 3 bits represent the RWX permissions of the group that owns the file.
--- The high 3 bits represent the RWX permissions of the user that owns the file.
--- @param mode integer
--- @return integer permissions
function tree.mode_permissions(mode)
	return mode % 0x200
end

--- Returns the type of a tree entry mode. Defined enumerations are:
---
--- - 0x4: directory
--- - 0x8: file
--- - 0xA: symlink
--- - 0xC: gitlink
--- @param mode integer
--- @return string type
function tree.mode_kind(mode)
	local kind = floor(mode / 0x1000)

	if kind == 0x4 then
		return 'directory'
	elseif kind == 0x8 then
		return 'file'
	elseif kind == 0xA then
		return 'symlink'
	elseif kind == 0xC then
		return 'gitlink'
	else
		return 'unknown'
	end
end

--- @param entry std.git.object.tree.entry
--- @return string
local function entry_sort_key(entry)
	if tree.mode_kind(entry.mode) == 'directory' then
		return entry.name .. '/'
	end

	return entry.name
end

--- @param entries std.git.object.tree.entry[]
function tree:init(entries)
	self.entries = entries or {}
	assert(type(self.entries) == 'table', 'tree entries must be a table')
end

--- @param data string
--- @param oid_type std.git.oid_type
--- @return std.git.object.tree|nil
--- @return string|nil err
function tree.parse(data, oid_type)
	local entry_pattern = '^([0-7]+) ([^%z]+)%z(' .. string.rep('.', oid_type.binsize) .. ')()'

	local entries, n = {}, 0

	local i = 1
	while i <= #data do
		local mode, name, oid_bin, last = data:match(entry_pattern, i)
		if not mode then
			return nil, 'invalid tree entry'
		end

		n = n + 1
		entries[n] = {
			mode = tonumber(mode, 8),
			name = name,
			oid = oid_type:bin2hex(oid_bin),
		}

		i = last
	end

	return tree.new(entries)
end

--- @param oid_type std.git.oid_type
--- @return string|nil payload
--- @return string|nil err
function tree:serialize(oid_type)
	sort(self.entries, function(a, b)
		return entry_sort_key(a) < entry_sort_key(b)
	end)

	local parts, n = {}, 0
	for i = 1, #self.entries do
		local entry = self.entries[i]

		if not tree.mode_kind(entry.mode) then
			return nil, 'tree entry mode is not valid'
		elseif #entry.name == 0 then
			return nil, 'tree entry name must be non-empty'
		elseif entry.name:match('/') then
			return nil, 'tree entry name cannot contain slash'
		elseif not oid_type:check_hex(entry.oid) then
			return nil, 'tree entry oid has invalid format'
		end

		n = n + 1
		parts[n] = string.format('%06o', entry.mode)
		n = n + 1
		parts[n] = ' '
		n = n + 1
		parts[n] = entry.name
		n = n + 1
		parts[n] = '\0'
		n = n + 1
		parts[n] = oid_type:hex2bin(entry.oid)
	end

	return table.concat(parts)
end

return tree
