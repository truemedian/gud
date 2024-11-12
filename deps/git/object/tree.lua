local oid = require('git/oid')

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

local function name_to_mode(kind)
	if kind == 'tree' then
		return 0x4000
	elseif kind == 'blob' then
		return 0x8000
	elseif kind == 'commit' then
		return 0xE000
	end

	error('unknown object kind: ' .. kind)
end

---@class git.object.tree.entry
---@field mode number
---@field name string
---@field object git.object

---@class git.object.tree
---@field files git.object.tree.entry[]
local tree = {}
local tree_mt = { __index = tree }

function tree.new()
	return setmetatable({ files = {} }, tree_mt)
end

---@param repository git.repository
---@param data string
---@return git.object.tree|nil, string|nil
function tree.decode(repository, data)
	local self = setmetatable({ files = {} }, tree_mt)
	local stop = #data
	local pos = 1

	local pattern = '^([0-7]+) ([^%z]+)%z(' .. string.rep('.', repository.oid.bin_length) .. ')()'
	while pos <= stop do
		local mode, name, bin_oid, after = data:match(pattern, pos)
		assert(mode, 'invalid tree format')

		local object = repository:load(oid.bin2hex(bin_oid))
		if not object then
			return nil, 'commit.decode: failed to load tree object'
		end

		mode = tonumber(mode, 8)
		table.insert(self.files, {
			mode = mode,
			name = name,
			object = object,
		})

		pos = after
	end

	return self
end

---@param repository git.repository
---@return string|nil, string|nil
function tree:recode(repository)
	local parts = {}

	table.sort(self.files, function(a, b)
		return a.name < b.name
	end)

	for _, entry in ipairs(self.files) do
		local recoded, err = entry.object:recode(repository)
		if not recoded then
			return nil, err
		end

		table.insert(parts, string.format('%06o %s\0%s', entry.mode, entry.name, oid.hex2bin(entry.object.oid)))
	end

	return table.concat(parts)
end

---@param name string
---@param object git.object
function tree:add_file(name, object)
	if string.find(name, '\0', 1, true) then
		error('malformed file name')
	elseif self:get_file(name) then
		error('duplicate file name')
	end

	local mode = name_to_mode(object.kind)

	table.insert(self.files, {
		mode = mode,
		name = name,
		object = object,
	})
end

---@param name string
function tree:remove_file(name)
	for i, entry in ipairs(self.files) do
		if entry.name == name then
			table.remove(self.files, i)
			return
		end
	end
end

---@param name string
---@return git.object|nil
function tree:get_file(name)
	for _, entry in ipairs(self.files) do
		if entry.name == name then
			return entry.object
		end
	end
end

return tree
