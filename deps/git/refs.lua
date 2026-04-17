local class = require('class')

local fs = require('fs')
local lock = require('git/lock')
local path = require('path')

--- @class std.git.refs : std.class<std.git.refs>
--- @field git_dir string
--- @field refs_dir string
--- @field oid_type std.git.oid_type
--- @field cache table<string, std.git.oid>
local refs = class.new('std.git.refs')

--- @param git_dir string
--- @param oid_type std.git.oid_type
function refs:init(git_dir, oid_type)
	self.git_dir = git_dir
	self.refs_dir = path.join(git_dir, 'refs')
	self.oid_type = oid_type

	self.packed_mtime = 0
	self.cache = {}
end

--- @param name string
--- @return boolean
function refs.isValidRefName(name)
	if not name:startswith('refs/', true) and name ~= 'HEAD' then
		return false
	elseif name:endswith('/', true) or name:endswith('.lock', true) then
		return false
	elseif name:find('[%z\001-\031\127 ~^:?*%[]') then
		return false
	end

	for segment in string.split(name, '/', true) do
		if segment == '.' or segment == '..' or segment == '' then
			return false
		elseif segment:startswith('.', true) or segment:endswith('.', true) then
			return false
		end
	end

	return true
end

--- @param name string
--- @return string
function refs:refPath(name)
	return path.join(self.git_dir, name)
end

--- @param name string
--- @return string|nil value
--- @return string|nil err
function refs:readLoose(name)
	if not refs.isValidRefName(name) then
		return nil, 'invalid ref name'
	end

	local line, err = fs.readFile(self:refPath(name))
	if not line then
		return nil, err
	end

	return line:match('^([^\r\n]+)') or '', nil
end

--- @return boolean success
--- @return string|nil err
function refs:reloadCache()
	local packed_path = path.join(self.git_dir, 'packed-refs')

	local stat, stat_err, stat_errno = fs.stat(packed_path)
	if stat_errno == 'ENOENT' then
		return true, nil
	elseif not stat then
		return false, stat_err
	end

	if stat.mtime <= self.packed_mtime then
		return true, nil
	else
		self.packed_mtime = stat.mtime
		self.cache = {}
	end

	local data, err = fs.readFile(packed_path)
	if not data then
		return false, err
	end

	for line in string.split(data, '\n', true) do
		if line ~= '' and line:sub(1, 1) ~= '#' and line:sub(1, 1) ~= '^' then
			local oid, name = line:match('^([0-9a-f]+) (.+)$')
			if oid and name and refs.isValidRefName(name) and self.oid_type:check_hex(oid) then
				self.cache[name] = oid
			end
		end
	end

	return true, nil
end

--- @param name string
--- @return string|nil oid
--- @return string|nil err
function refs:resolve(name)
	local success, reload_err = self:reloadCache()
	if not success then
		return nil, reload_err
	end

	local loop = {}

	local current = name
	while true do
		if not refs.isValidRefName(current) then
			return nil, 'invalid ref name'
		elseif loop[current] then
			return nil, 'symbolic reference loop detected'
		end

		local cached = self.cache[current]
		if cached then
			return cached, nil
		end

		local line = self:readLoose(current)
		if not line then
			return nil, 'reference not found or invalid'
		end

		loop[current] = true
		local symbolic = line:match('^ref: ([^\r\n]+)')
		if symbolic then
			current = symbolic
		elseif self.oid_type:check_hex(line) then
			return line, nil
		else
			return nil, 'invalid reference format'
		end
	end
end

--- @param name string
--- @param oid std.git.oid
--- @return boolean success
--- @return string|nil err
function refs:update(name, oid)
	if not refs.isValidRefName(name) then
		return false, 'invalid ref name'
	elseif not self.oid_type:check_hex(oid) then
		return false, 'invalid oid'
	end

	local lockfile = lock.new(self:refPath(name))
	local acquired, lock_err = lockfile:acquire()
	if not acquired then
		return false, lock_err
	end

	local success, err = lockfile:write(oid:lower() .. '\n')
	if not success then
		lockfile:release()
		return false, err
	end

	return lockfile:commit()
end

--- @param name string
--- @param target string
--- @return boolean success
--- @return string|nil err
function refs:updateSymbolic(name, target)
	if not refs.isValidRefName(name) then
		return false, 'invalid ref name'
	elseif not refs.isValidRefName(target) then
		return false, 'invalid symbolic target'
	end

	local resolved_target = self:resolve(target)
	if not resolved_target then
		return false, 'symbolic target does not exist'
	end

	local lockfile = lock.new(self:refPath(name))
	local acquired, lock_err = lockfile:acquire()
	if not acquired then
		return false, lock_err
	end

	local success, err = lockfile:write('ref: ' .. target .. '\n')
	if not success then
		lockfile:release()
		return false, err
	end

	return lockfile:commit()
end

--- @param name string
--- @return boolean	success
--- @return string|nil err
function refs:delete(name)
	if not refs.isValidRefName(name) then
		return false, 'invalid ref name'
	elseif name == 'HEAD' then
		return false, 'cannot delete HEAD'
	end

	local deleted, delete_err, delete_errno = fs.unlink(self:refPath(name))
	if not deleted and delete_errno ~= 'ENOENT' then
		return false, delete_err
	end

	return true
end

--- @param dir_path string
--- @param prefix? string
local function walk_refs(dir_path, prefix)
	for name, kind in fs.scandir(dir_path) do
		local logical = prefix .. '/' .. name
		if kind == 'directory' then
			local full = path.join(dir_path, name)

			walk_refs(full, logical)
		elseif kind == 'file' then
			coroutine.yield(logical)
		end
	end
end

--- @param prefix? string
--- @return table<string, std.git.oid>|nil
--- @return string|nil err
function refs:list(prefix)
	prefix = prefix or ''
	local packed, packed_err = self:reloadCache()
	if not packed then
		return nil, packed_err
	end

	local out = prefix == '' and table.copy(self.cache)
		or table.filter(self.cache, function(name)
			return string.startswith(name, prefix)
		end)

	for name in coroutine.wrap(walk_refs), self.refs_dir, 'refs' do
		if name:sub(1, #prefix) == prefix and refs.isValidRefName(name) then
			out[name] = self:resolve(name)
		end
	end

	return out, nil
end

return refs
