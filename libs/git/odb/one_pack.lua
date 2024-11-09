local miniz = require('miniz')
local bit = require('bit')

local common = require('git/common')
local object = require('git/object')

---@class git.odb.backend.one_pack : git.odb.backend
---@field objects_dir string
---@field pack_hash string
---@field packfile string
---@field fanout integer[]
---@field hashes git.oid[]
---@field hashes_lookup table<integer, git.oid>
---@field offsets integer[]
---@field lengths table<integer, integer>
local backend_onepack = {}
local backend_onepack_mt = { __index = backend_onepack }

---@param objects_dir string
---@param pack_hash string
---@return string
local function pack_path(objects_dir, pack_hash)
	return objects_dir .. '/pack/pack-' .. pack_hash .. '.pack'
end

---@param objects_dir string
---@param pack_hash string
---@return string
local function idx_path(objects_dir, pack_hash)
	return objects_dir .. '/pack/pack-' .. pack_hash .. '.idx'
end

---@param arr git.oid[]
---@param value git.oid
---@param start integer
---@param stop integer
---@return integer|nil
local function binsearch(arr, value, start, stop)
	while start < stop do
		local mid = math.floor((start + stop) / 2)
		if arr[mid] < value then
			start = mid + 1
		elseif arr[mid] > value then
			stop = mid
		else
			return mid
		end
	end
end

---@param num integer
---@return integer, integer
local function unpack_type_and_size(num)
	local kind = bit.band(bit.rshift(num, 4), 0x7)
	local size_low = bit.band(num, 0xf)

	if num <= 0xffffffff then
		return kind, size_low + bit.lshift(bit.rshift(num, 7), 4)
	else
		return kind, size_low + math.floor(num / 0x80) * 0x10
	end
end

---@param odb git.odb
---@param objects_dir string
---@param pack_hash string
---@return git.odb.backend.one_pack|nil, nil|string
function backend_onepack.load(odb, objects_dir, pack_hash)
	local self = setmetatable({
		objects_dir = assert(objects_dir, 'missing objects directory'),
		pack_hash = pack_hash,
	}, backend_onepack_mt)

	self:refresh(odb)
	return self
end

---@param odb git.odb
---@param oid git.oid
---@return git.object|nil, nil|string
function backend_onepack:read(odb, oid)
	local offset = self:_find_offset(oid)
	if not offset then
		return nil, 'object not found in database'
	end

	return self:_read_at_offset(odb, offset)
end

---@param odb git.odb
---@param oid git.oid
---@return git.object.kind|nil, number|string
function backend_onepack:read_header(odb, oid)
	local offset = self:_find_offset(oid)
	if not offset then
		return nil, 'object not found in database'
	end

	return self:_read_header_at_offset(odb, offset)
end

---@param odb git.odb
---@param offset integer
---@return git.object
function backend_onepack:_read_at_offset(odb, offset)
	local chunk_length = assert(self.lengths[offset], 'packfile index missing length at ' .. offset)
	local oid = assert(self.hashes_lookup[offset], 'packfile index missing hash at ' .. offset)

	if odb.cache[oid] then
		return odb.cache[oid]
	end

	local kind_and_size, header_offset = common.read_pack_varsize(self.packfile, 1 + offset)
	local kind, uncompressed_size = unpack_type_and_size(kind_and_size)

	if kind == 1 or kind == 2 or kind == 3 or kind == 4 then
		local deflated_data = self.packfile:sub(header_offset, offset + chunk_length)
		local inflated_data = miniz.inflate(deflated_data, 1)
		assert(#inflated_data == uncompressed_size, 'inflated object does not match expected size')

		local real_kind
		if kind == 1 then
			real_kind = 'commit'
		elseif kind == 2 then
			real_kind = 'tree'
		elseif kind == 3 then
			real_kind = 'blob'
		elseif kind == 4 then
			real_kind = 'tag'
		end

		local obj = object.create(odb, real_kind, inflated_data, oid)
		odb:_cache_object(oid, obj)
		return obj
	elseif kind == 6 or kind == 7 then
		local base_object

		if kind == 6 then
			local base_offset
			base_offset, header_offset = common.read_pack_varoffset(self.packfile, header_offset)
			base_object = self:_read_at_offset(odb, offset - base_offset)
		elseif kind == 7 then
			local binary_ref = self.packfile:sub(header_offset, header_offset + odb.oid_type.bin_length - 1) ---@cast binary_ref git.oid_binary
			header_offset = header_offset + odb.oid_type.bin_length

			local reference = odb.oid_type:bin2hex(binary_ref)
			base_object = odb:read(reference)
		end

		assert(base_object, 'packed delta base object not found')
		local deflated_data = self.packfile:sub(header_offset, offset + chunk_length)
		local delta_data = miniz.inflate(deflated_data, 1)
		local delta_offset = 1

		assert(#delta_data == uncompressed_size, 'delta object does not match expected size')
		local base_size, result_size

		base_size, delta_offset = common.read_pack_varsize(delta_data, delta_offset)
		result_size, delta_offset = common.read_pack_varsize(delta_data, delta_offset)

		local base_data = base_object.data
		assert(base_size == #base_data, 'delta base object size does not match expected size')

		local parts = {}
		while delta_offset <= #delta_data do
			local instruction = delta_data:byte(delta_offset)
			delta_offset = delta_offset + 1

			if instruction < 0x80 then
				-- data instruction
				assert(instruction > 0, 'invalid data instruction')

				table.insert(parts, delta_data:sub(delta_offset, delta_offset + instruction - 1))
				delta_offset = delta_offset + instruction
			else
				-- copy instruction
				local copy_offset = 0
				local copy_length = 0

				if bit.band(instruction, 0x01) > 0 then
					copy_offset = delta_data:byte(delta_offset)
					delta_offset = delta_offset + 1
				end
				if bit.band(instruction, 0x02) > 0 then
					copy_offset = copy_offset + delta_data:byte(delta_offset) * 0x100
					delta_offset = delta_offset + 1
				end
				if bit.band(instruction, 0x04) > 0 then
					copy_offset = copy_offset + delta_data:byte(delta_offset) * 0x10000
					delta_offset = delta_offset + 1
				end
				if bit.band(instruction, 0x08) > 0 then
					copy_offset = copy_offset + delta_data:byte(delta_offset) * 0x1000000
					delta_offset = delta_offset + 1
				end
				if bit.band(instruction, 0x10) > 0 then
					copy_length = delta_data:byte(delta_offset)
					delta_offset = delta_offset + 1
				end
				if bit.band(instruction, 0x20) > 0 then
					copy_length = copy_length + delta_data:byte(delta_offset) * 0x100
					delta_offset = delta_offset + 1
				end
				if bit.band(instruction, 0x40) > 0 then
					copy_length = copy_length + delta_data:byte(delta_offset) * 0x10000
					delta_offset = delta_offset + 1
				end

				-- copy_length == 0 means 0x10000 bytes
				if copy_length == 0 then
					copy_length = 0x10000
				end

				assert(copy_offset <= #base_data, 'copy offset is out of bounds')
				assert(copy_offset + copy_length <= #base_data, 'copy length is out of bounds')

				table.insert(parts, base_data:sub(1 + copy_offset, copy_offset + copy_length))
			end
		end

		local result_data = table.concat(parts)
		assert(#result_data == result_size, 'delta result size does not match expected size')

		local obj = object.create(odb, base_object.kind, result_data, oid)
		odb:_cache_object(oid, obj)
		return obj
	end

	error('invalid object kind')
end

---@param odb git.odb
---@param offset integer
function backend_onepack:_read_header_at_offset(odb, offset)
	local chunk_length = assert(self.lengths[offset], 'packfile index missing length at ' .. offset)

	local kind_and_size, header_offset = common.read_pack_varsize(self.packfile, 1 + offset)
	local kind, uncompressed_size = unpack_type_and_size(kind_and_size)

	local real_kind
	if kind == 1 then
		return 'commit', uncompressed_size
	elseif kind == 2 then
		return 'tree', uncompressed_size
	elseif kind == 3 then
		return 'blob', uncompressed_size
	elseif kind == 4 then
		return 'tag', uncompressed_size
	elseif kind == 6 then
		local base_offset
		base_offset, header_offset = common.read_pack_varoffset(self.packfile, header_offset)

		real_kind = self:_read_header_at_offset(odb, base_offset)
	elseif kind == 7 then
		local binary_ref = self.packfile:sub(header_offset, header_offset + odb.oid_type.bin_length - 1) ---@cast binary_ref git.oid_binary
		header_offset = header_offset + odb.oid_type.bin_length

		local reference = odb.oid_type:bin2hex(binary_ref)

		real_kind = odb:read_header(reference)
	end
	assert(real_kind, 'packed delta base object not found')

	local deflated_data = self.packfile:sub(header_offset, header_offset + chunk_length)
	local delta_data = miniz.inflate(deflated_data, 1)

	local delta_offset, base_size, result_size = 1, 0, 0
	base_size, delta_offset = common.read_pack_varsize(delta_data, delta_offset)
	result_size, delta_offset = common.read_pack_varsize(delta_data, delta_offset)

	return real_kind, result_size
end

---@param odb git.odb
---@param oid git.oid
---@return boolean, nil|string
function backend_onepack:exists(odb, oid)
	return self:_find_offset(oid) ~= nil
end

---@param oid git.oid
---@return integer|nil
function backend_onepack:_find_offset(oid)
	local first_byte = tonumber(oid:sub(1, 2), 16) + 1

	local start = self.fanout[first_byte - 1] or 0
	local stop = self.fanout[first_byte] + 1

	local i = binsearch(self.hashes, oid, start + 1, stop)
	if i then
		return self.offsets[i]
	end
end

---@param odb git.odb
function backend_onepack:refresh(odb)
	local index_path = idx_path(self.objects_dir, self.pack_hash)
	local packfile_path = pack_path(self.objects_dir, self.pack_hash)

	local idx = common.read_file(index_path)
	assert(idx:sub(1, 8) == '\xfftOc\x00\x00\x00\x02', 'invalid packfile index signature')

	local pack = common.read_file(packfile_path)

	self.packfile = pack

	self.fanout = {}
	self.hashes = {}
	self.offsets = {}
	self.lengths = {}
	self.hashes_lookup = {}

	local fanout_start = 9
	for i = 0, 255 do
		self.fanout[i + 1] = common.read_u32be(idx, fanout_start + i * 4)
	end

	local hashes_start = fanout_start + 256 * 4
	for i = 0, self.fanout[256] - 1 do
		local offset = hashes_start + i * 20

		local binhash = idx:sub(offset, offset + 19) ---@cast binhash git.oid_binary
		self.hashes[i + 1] = odb.oid_type:bin2hex(binhash)

		assert(i == 0 or self.hashes[i + 1] > self.hashes[i], 'packfile index is not sorted')

		local first_byte = binhash:byte() + 1
		assert(i >= (self.fanout[first_byte - 1] or 0) and i < self.fanout[first_byte], 'packfile index is corrupt')
	end

	local long_offset_needed = { n = 0 }

	local checksums_start = hashes_start + self.fanout[256] * 20
	local offsets_start = checksums_start + self.fanout[256] * 4
	for i = 0, self.fanout[256] - 1 do
		local offset = offsets_start + i * 4
		self.offsets[i + 1] = common.read_u32be(idx, offset)

		if self.offsets[i + 1] > 0x7fffffff then
			local long_index = bit.band(self.offsets[i + 1], 0x7fffffff)
			long_offset_needed[long_index] = i + 1
			long_offset_needed.n = math.max(long_offset_needed.n, long_index)
		end
	end

	local lengths_start = offsets_start + self.fanout[256] * 4
	for i = 0, long_offset_needed.n - 1 do
		local j = long_offset_needed[i]
		assert(j, 'packfile index has extraneous long offset')

		local offset = lengths_start + i * 8
		self.offsets[j] = common.read_u64be(idx, offset)
	end

	local sorted_offsets = {}
	for i = 1, self.fanout[256] do
		sorted_offsets[i] = self.offsets[i]
	end
	table.sort(sorted_offsets)

	for i = 1, self.fanout[256] do
		local start = sorted_offsets[i]
		local stop = sorted_offsets[i + 1] or #pack
		self.lengths[start] = stop - start

		self.hashes_lookup[self.offsets[i]] = self.hashes[i]
	end
end

---@param oid git.oid
---@param data string
---@param kind git.object.kind
---@return boolean, nil|string
function backend_onepack:write(oid, data, kind)
	return false
end

return backend_onepack
