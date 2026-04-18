local class = require('class')

local flate = require('flate')
local fs = require('fs')
local path = require('path')

local object = require('git/object')
local pack_file = require('git/pack/file')
local pack_index = require('git/pack/index')

--- @class std.git.database : std.class<std.git.database>
--- @field git_dir string
--- @field objects_dir string
--- @field pack_dir string
--- @field oid_type std.git.oid_type
--- @field pack_cache table[]|nil
local database = class.new('std.git.database')

--- @param git_dir string
--- @param oid_type std.git.oid_type
function database:init(git_dir, oid_type)
	self.git_dir = git_dir
	self.objects_dir = path.join(git_dir, 'objects')
	self.pack_dir = path.join(self.objects_dir, 'pack')
	self.oid_type = oid_type
	self.pack_cache = nil
end

--- @param oid std.git.oid
--- @return string
function database:loosePath(oid)
	assert(self.oid_type:check_hex(oid), 'invalid oid')

	return path.join(self.objects_dir, oid:sub(1, 2), oid:sub(3))
end

--- @param kind string
--- @param payload string
--- @return std.git.oid|nil oid
--- @return string|nil err
--- @return boolean already_exists
function database:writeLoose(kind, payload)
	local oid = self.oid_type:oid(payload, kind, true)
	local final_path = self:loosePath(oid)
	if fs.exists(final_path) then
		local existing_kind, existing_payload, read_err = self:readLoose(oid)
		if not existing_kind or not existing_payload then
			return nil, read_err, false
		elseif existing_kind ~= kind or existing_payload ~= payload then
			return nil, 'hash collision detected', false
		end

		return oid, nil, true
	end

	local dir_path = path.dirname(final_path)
	local dir_ok, dir_err = fs.mkdirp(dir_path)
	if not dir_ok then
		return nil, dir_err, false
	end

	local raw = object.encode(kind, payload)
	local compressed = flate.zlib.compress(raw)
	local write_ok, write_err = fs.writeFileAtomic(final_path, compressed)
	if not write_ok then
		return nil, write_err, false
	end

	return oid, nil, false
end

--- @param oid std.git.oid
--- @return string|nil kind
--- @return string|nil payload
--- @return string|nil err
function database:readLoose(oid)
	if not self.oid_type:check_hex(oid) then
		return nil, nil, 'invalid oid'
	end

	local object_path = self:loosePath(oid)
	local compressed, read_err = fs.readFile(object_path)
	if not compressed then
		return nil, nil, read_err
	end

	local raw, inflate_err = flate.zlib.decompress(compressed)
	if not raw then
		return nil, nil, inflate_err
	end

	local kind, payload, decode_err = object.decode(raw)
	if not kind or not payload then
		return nil, nil, decode_err
	end

	local expected = self.oid_type:oid(payload, kind, true)
	if expected ~= oid then
		return nil, nil, 'object hash mismatch'
	end

	return kind, payload, nil
end

--- @return table[]|nil
--- @return string|nil err
function database:loadPackCaches()
	if self.pack_cache then
		return self.pack_cache, nil
	end

	local entries, read_err, errno = fs.readdir(self.pack_dir)
	if not entries then
		if errno == 'ENOENT' then
			self.pack_cache = {}
			return self.pack_cache, nil
		end

		return nil, read_err
	end

	local caches, n = {}, 0
	for i = 1, #entries do
		local entry = entries[i]
		local idx_name = entry.name
		if entry.type == 'file' and idx_name:sub(-4) == '.idx' then
			local base = idx_name:sub(1, -5)
			local pack_name = base .. '.pack'
			local idx_path = path.join(self.pack_dir, idx_name)
			local pack_path = path.join(self.pack_dir, pack_name)

			if fs.exists(pack_path) then
				local idx_data, idx_err = fs.readFile(idx_path)
				if not idx_data then
					return nil, idx_err
				end

				local offset_by_oid, next_offset_by_offset, object_count, parse_err =
					pack_index.parse(idx_data, self.oid_type.binsize)
				if not offset_by_oid then
					return nil, parse_err
				elseif object_count == nil then
					return nil, 'invalid pack index object count'
				end

				local offset_by_oid_hex = {}
				for oid_bin, object_offset in pairs(offset_by_oid) do
					offset_by_oid_hex[self.oid_type:bin2hex(oid_bin)] = object_offset
				end

				local pack_data, pack_err = fs.readFile(pack_path)
				if not pack_data then
					return nil, pack_err
				end

				local content_end, validate_err = pack_file.validate(pack_data, object_count, self.oid_type.binsize)
				if not content_end then
					return nil, validate_err
				end

				n = n + 1
				caches[n] = {
					pack_path = pack_path,
					idx_path = idx_path,
					data = pack_data,
					content_end = content_end,
					offset_by_oid = offset_by_oid_hex,
					next_offset_by_offset = next_offset_by_offset,
					object_by_offset = {},
					object_by_oid = {},
				}
			end
		end
	end

	self.pack_cache = caches
	return self.pack_cache, nil
end

--- @param oid std.git.oid
--- @param visited? table<string, boolean>
--- @return string|nil kind
--- @return string|nil payload
--- @return string|nil err
function database:readPacked(oid, visited)
	if not self.oid_type:check_hex(oid) then
		return nil, nil, 'invalid oid'
	end

	visited = visited or {}
	if visited[oid] then
		return nil, nil, 'detected circular delta reference'
	end
	visited[oid] = true

	local packs, load_err = self:loadPackCaches()
	if not packs then
		visited[oid] = nil
		return nil, nil, load_err
	end

	for i = 1, #packs do
		local cache = packs[i]
		local known = cache.object_by_oid[oid]
		if known then
			visited[oid] = nil
			return known.kind, known.payload, nil
		end

		local offset = cache.offset_by_oid[oid]
		if offset then
			local kind, payload, actual_oid, read_err = pack_file.readObjectAt(
				cache,
				offset,
				self.oid_type,
				function(base_oid, current_visited)
					return self:readObject(base_oid, current_visited)
				end,
				visited
			)
			visited[oid] = nil
			if not kind then
				return nil, nil, read_err
			end

			if actual_oid ~= oid then
				return nil, nil, 'pack index oid mismatch'
			end

			return kind, payload, nil
		end
	end

	visited[oid] = nil
	return nil, nil, 'object not found'
end

--- @param oid std.git.oid
--- @param visited? table<string, boolean>
--- @return string|nil kind
--- @return string|nil payload
--- @return string|nil err
function database:readObject(oid, visited)
	local kind, payload, loose_err = self:readLoose(oid)
	if kind and payload then
		return kind, payload, nil
	end

	if loose_err ~= 'object not found' then
		return nil, nil, loose_err
	end

	return self:readPacked(oid, visited)
end

--- @param oid std.git.oid
--- @return boolean
function database:existsPacked(oid)
	local packs = self:loadPackCaches()
	if not packs then
		return false
	end

	for i = 1, #packs do
		if packs[i].offset_by_oid[oid] ~= nil then
			return true
		end
	end

	return false
end

--- @param oid std.git.oid
--- @return boolean
function database:exists(oid)
	if not self.oid_type:check_hex(oid) then
		return false
	end

	if fs.exists(self:loosePath(oid)) then
		return true
	end

	return self:existsPacked(oid)
end

return database
