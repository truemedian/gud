local class = require('class')

local flate = require('flate')
local fs = require('fs')
local path = require('path')

local object = require('git/object')

--- @class std.git.database : std.class<std.git.database>
--- @field git_dir string
--- @field objects_dir string
--- @field oid_type std.git.oid_type
local database = class.new('std.git.database')

--- @param git_dir string
--- @param oid_type std.git.oid_type
function database:init(git_dir, oid_type)
	self.git_dir = git_dir
	self.objects_dir = path.join(git_dir, 'objects')
	self.oid_type = oid_type
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

--- @param oid std.git.oid
--- @return boolean
function database:exists(oid)
	if not self.oid_type:check_hex(oid) then
		return false
	end

	return fs.exists(self:loosePath(oid))
end

return database
