local sort = table.sort

local memory = require('memory')

local index = {}

--- @param idx_data string
--- @param binsize integer
--- @return table<string, integer>|nil offset_by_oid
--- @return table<integer, integer>|nil next_offset_by_offset
--- @return integer|nil object_count
--- @return string|nil err
function index.parse(idx_data, binsize)
	local mem = memory.new(idx_data)

	if #idx_data < 8 + 256 * 4 then
		return nil, nil, nil, 'invalid pack index: too short'
	end

	local signature = idx_data:sub(1, 4)
	if signature ~= '\255tOc' then
		return nil, nil, nil, 'unsupported pack index version'
	end

	local version = mem:readUint32BE(5)
	if version ~= 2 then
		return nil, nil, nil, 'unsupported pack index version ' .. tostring(version)
	end

	local fanout_offset = 9
	local object_count = mem:readUint32BE(fanout_offset + 255 * 4)
	if not object_count then
		return nil, nil, nil, 'invalid pack index fanout'
	end

	local oid_table_offset = fanout_offset + 256 * 4
	local crc_table_offset = oid_table_offset + object_count * binsize
	local offset_table_offset = crc_table_offset + object_count * 4
	local large_offset_table_offset = offset_table_offset + object_count * 4
	local trailer_size = binsize * 2

	if #idx_data < large_offset_table_offset - 1 + trailer_size then
		return nil, nil, nil, 'invalid pack index layout'
	end

	local offset_by_oid = {}
	local offsets = {}
	local large_offset_count = 0

	for i = 1, object_count do
		local oid_start = oid_table_offset + (i - 1) * binsize
		local oid_end = oid_start + binsize - 1
		if oid_end > #idx_data then
			return nil, nil, nil, 'truncated pack index oid table'
		end

		local oid_bin = idx_data:sub(oid_start, oid_end)

		local offset_32 = mem:readUint32BE(offset_table_offset + (i - 1) * 4)
		if not offset_32 then
			return nil, nil, nil, 'truncated pack index offset table'
		end

		local offset = offset_32
		if offset_32 >= 0x80000000 then
			local large_index = offset_32 - 0x80000000
			large_offset_count = math.max(large_offset_count, large_index + 1)

			local large_offset = mem:readUint64BE(large_offset_table_offset + large_index * 8)
			if not large_offset then
                return nil, nil, nil, 'truncated pack index large offset table'
            elseif large_offset > math.maxinteger then
                return nil, nil, nil, 'pack index large offset exceeds representable range'
			end

			offset = large_offset
		end

		offset_by_oid[oid_bin] = offset
		offsets[i] = offset
	end

	local large_offset_end = large_offset_table_offset + large_offset_count * 8
	if #idx_data < large_offset_end - 1 + trailer_size then
		return nil, nil, nil, 'invalid pack index trailer'
	end

	sort(offsets)

	local next_offset_by_offset = {}
	for i = 1, #offsets - 1 do
		next_offset_by_offset[offsets[i]] = offsets[i + 1]
	end

	return offset_by_oid, next_offset_by_offset, object_count, nil
end

return index
