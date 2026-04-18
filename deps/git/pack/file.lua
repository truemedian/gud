local flate = require('flate')
local memory = require('memory')

local pack_file = {}

local full_kinds = {
	[1] = 'commit',
	[2] = 'tree',
	[3] = 'blob',
	[4] = 'tag',
}

local function read_delta_varint(data, at)
	local shift = 0
	local value = 0

	while true do
		local byte = string.byte(data, at)
		if not byte then
			return nil, at, 'truncated delta varint'
		end

		value = value + (byte % 0x80) * 2 ^ shift
		at = at + 1

		if byte < 0x80 then
			break
		end

		shift = shift + 7
		if shift > 56 then
			return nil, at, 'delta varint overflow'
		end
	end

	return value, at, nil
end

local function apply_delta(base, delta)
	local base_size, at, base_err = read_delta_varint(delta, 1)
	if base_size == nil then
		return nil, base_err
	end

	if base_size ~= #base then
		return nil, 'delta base size mismatch'
	end

	local result_size, next_at, result_err = read_delta_varint(delta, at)
	if result_size == nil then
		return nil, result_err
	end

	at = next_at

	local chunks, n = {}, 0
	while at <= #delta do
		local op = string.byte(delta, at)
		at = at + 1

		if op >= 0x80 then
			local copy_offset = 0
			local copy_size = 0

			if op % 0x02 >= 0x01 then
				copy_offset = copy_offset + string.byte(delta, at)
				at = at + 1
			end
			if math.floor(op / 0x02) % 0x02 >= 0x01 then
				copy_offset = copy_offset + string.byte(delta, at) * 0x100
				at = at + 1
			end
			if math.floor(op / 0x04) % 0x02 >= 0x01 then
				copy_offset = copy_offset + string.byte(delta, at) * 0x10000
				at = at + 1
			end
			if math.floor(op / 0x08) % 0x02 >= 0x01 then
				copy_offset = copy_offset + string.byte(delta, at) * 0x1000000
				at = at + 1
			end

			if math.floor(op / 0x10) % 0x02 >= 0x01 then
				copy_size = copy_size + string.byte(delta, at)
				at = at + 1
			end
			if math.floor(op / 0x20) % 0x02 >= 0x01 then
				copy_size = copy_size + string.byte(delta, at) * 0x100
				at = at + 1
			end
			if math.floor(op / 0x40) % 0x02 >= 0x01 then
				copy_size = copy_size + string.byte(delta, at) * 0x10000
				at = at + 1
			end

			if copy_size == 0 then
				copy_size = 0x10000
			end

			local copy_start = copy_offset + 1
			local copy_end = copy_offset + copy_size
			if copy_end > #base then
				return nil, 'delta copy exceeds base object'
			end

			n = n + 1
			chunks[n] = base:sub(copy_start, copy_end)
		elseif op > 0 then
			local literal_end = at + op - 1
			if literal_end > #delta then
				return nil, 'truncated delta literal'
			end

			n = n + 1
			chunks[n] = delta:sub(at, literal_end)
			at = literal_end + 1
		else
			return nil, 'invalid delta opcode'
		end
	end

	local payload = table.concat(chunks)
	if #payload ~= result_size then
		return nil, 'delta result size mismatch'
	end

	return payload, nil
end

--- @param pack_data string
--- @param expected_count integer
--- @param binsize integer
--- @return integer|nil content_end
--- @return string|nil err
function pack_file.validate(pack_data, expected_count, binsize)
	local mem = memory.new(pack_data)

	if pack_data:sub(1, 4) ~= 'PACK' then
		return nil, 'invalid pack signature'
	end

	local version = mem:readUint32BE(5)
	if version ~= 2 and version ~= 3 then
		return nil, 'unsupported pack version ' .. tostring(version)
	end

	local declared_count = mem:readUint32BE(9)
	if declared_count ~= expected_count then
		return nil, 'pack/index object count mismatch'
	end

	local content_end = #pack_data - binsize
	if content_end <= 12 then
		return nil, 'invalid pack size'
	end

	return content_end, nil
end

local function read_payload(cache, payload_offset, object_end)
	if object_end <= payload_offset then
		return nil, 'invalid pack object boundary'
	end

	local compressed = cache.data:sub(payload_offset, object_end - 1)
	local payload, inflate_err = flate.zlib.decompress(compressed)
	if not payload then
		return nil, inflate_err
	end

	return payload, nil
end

--- @param cache table
--- @param offset integer
--- @param oid_type std.git.oid_type
--- @param resolve_ref_delta fun(base_oid: std.git.oid, visited: table<string, boolean>): string|nil, string|nil, string|nil
--- @param visited table<string, boolean>
--- @return string|nil kind
--- @return string|nil payload
--- @return string|nil oid
--- @return string|nil err
function pack_file.readObjectAt(cache, offset, oid_type, resolve_ref_delta, visited)
	local cached = cache.object_by_offset[offset]
	if cached then
		return cached.kind, cached.payload, cached.oid, nil
	end

	local next_offset = cache.next_offset_by_offset[offset]
	local object_end = next_offset or (cache.content_end + 1)
	if offset < 13 or object_end > cache.content_end + 1 then
		return nil, nil, nil, 'invalid pack object offset'
	end

	local cursor = offset
	local first = string.byte(cache.data, cursor)
	if not first then
		return nil, nil, nil, 'truncated pack object header'
	end

	local type_code = math.floor(first / 0x10) % 0x08
	local size = first % 0x10

	local shift = 4
	while first >= 0x80 do
		cursor = cursor + 1
		first = string.byte(cache.data, cursor)
		if not first then
			return nil, nil, nil, 'truncated pack object size'
		end

		size = size + (first % 0x80) * 2 ^ shift
		shift = shift + 7
	end

	cursor = cursor + 1

	if type_code == 5 then
		return nil, nil, nil, 'unsupported pack object type 5'
	end

	local payload_offset = cursor
	local kind
	local payload

	if type_code >= 1 and type_code <= 4 then
		kind = full_kinds[type_code]
		local full_payload, payload_err = read_payload(cache, payload_offset, object_end)
		if not full_payload then
			return nil, nil, nil, payload_err
		end

		payload = full_payload
	elseif type_code == 6 then
		local dist = string.byte(cache.data, payload_offset)
		if not dist then
			return nil, nil, nil, 'truncated ofs-delta header'
		end

		local encoded = dist
		dist = dist % 0x80
		while encoded >= 0x80 do
			payload_offset = payload_offset + 1
			encoded = string.byte(cache.data, payload_offset)
			if not encoded then
				return nil, nil, nil, 'truncated ofs-delta base offset'
			end

			dist = (dist + 1) * 0x80 + (encoded % 0x80)
		end

		payload_offset = payload_offset + 1

		local delta, delta_err = read_payload(cache, payload_offset, object_end)
		if not delta then
			return nil, nil, nil, delta_err
		end

		local base_offset = offset - dist
		if base_offset <= 0 or base_offset >= offset then
			return nil, nil, nil, 'invalid ofs-delta base offset'
		end

		local base_kind, base_payload, _, base_err = pack_file.readObjectAt(cache, base_offset, oid_type, resolve_ref_delta, visited)
		if not base_kind then
			return nil, nil, nil, base_err
		end

		kind = base_kind
		local delta_apply_err
		payload, delta_apply_err = apply_delta(base_payload, delta)
		if not payload then
			return nil, nil, nil, delta_apply_err
		end
	elseif type_code == 7 then
		local base_oid_bin = cache.data:sub(payload_offset, payload_offset + oid_type.binsize - 1)
		if #base_oid_bin ~= oid_type.binsize then
			return nil, nil, nil, 'truncated ref-delta base oid'
		end

		local base_oid = oid_type:bin2hex(base_oid_bin)
		payload_offset = payload_offset + oid_type.binsize

		local delta, delta_err = read_payload(cache, payload_offset, object_end)
		if not delta then
			return nil, nil, nil, delta_err
		end

		local base_kind, base_payload, base_err = resolve_ref_delta(base_oid, visited)
		if not base_kind then
			return nil, nil, nil, base_err
		end

		kind = base_kind
		local delta_apply_err
		payload, delta_apply_err = apply_delta(base_payload, delta)
		if not payload then
			return nil, nil, nil, delta_apply_err
		end
	else
		return nil, nil, nil, 'unsupported pack object type ' .. tostring(type_code)
	end

	if #payload ~= size then
		return nil, nil, nil, 'pack object size mismatch'
	end

	local oid = oid_type:oid(payload, kind, true)
	local entry = {
		kind = kind,
		payload = payload,
		oid = oid,
	}

	cache.object_by_offset[offset] = entry
	cache.object_by_oid[oid] = entry

	return kind, payload, oid, nil
end

return pack_file
