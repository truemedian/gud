local bit = require('bit')

local char, byte, rep = string.char, string.byte, string.rep
local band, rshift, lshift = bit.band, bit.rshift, bit.lshift
local concat = table.concat

local DEFAULT_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local base64 = {}

--- Encodes the given data as a base64 string.
--- @param data string
--- @param pad? boolean
--- @param column? integer|boolean
--- @param alphabet? string
function base64.encode(data, pad, column, alphabet)
	alphabet = alphabet or DEFAULT_ALPHABET
	column = column == true and 76 or column or false

	assert(column == false or (column > 0 and column % 4 == 0), 'column must be an integer multiple of 4')
	assert(#alphabet == 64, 'alphabet must be 64 characters long')

	local column_n = column and math.floor(column / 4) or nil
	local data_len = #data

	local result, n = {}, 1
	for i = 1, data_len - 2, 3 do
		local a, b, c = byte(data, i, i + 2)

		local triple = a * 0x10000 + b * 0x100 + c
		local w = rshift(band(triple, 0xFC0000), 18) + 1
		local x = rshift(band(triple, 0x03F000), 12) + 1
		local y = rshift(band(triple, 0x000FC0), 6) + 1
		local z = band(triple, 0x00003F) + 1

		result[n] = char(byte(alphabet, w), byte(alphabet, x), byte(alphabet, y), byte(alphabet, z))
		n = n + 1

		if column_n and (n - 1) % column_n == 0 then
			result[n] = '\n'
			n = n + 1
		end
	end

	local remaining = data_len % 3
	if remaining == 1 then
		local a = byte(data, -1)
		local triple = a

		local w = rshift(band(triple, 0xFC), 2) + 1
		local x = lshift(band(triple, 0x03), 4) + 1

		result[n] = char(byte(alphabet, w), byte(alphabet, x))
		n = n + 1
	elseif remaining == 2 then
		local a, b = byte(data, -2, -1)
		local triple = a * 0x100 + b

		local w = rshift(band(triple, 0xFC00), 10) + 1
		local x = rshift(band(triple, 0x03F0), 4) + 1
		local y = lshift(band(triple, 0x000F), 2) + 1

		result[n] = char(byte(alphabet, w), byte(alphabet, x), byte(alphabet, y))
		n = n + 1
	end

	if pad and remaining > 0 then
		result[n] = rep('=', 3 - remaining)
		n = n + 1
	end

	return concat(result, nil, 1, n - 1)
end

--- Decodes the given base64 string.
---
--- @param data string
--- @param alphabet? string
--- @return string|nil decoded
function base64.decode(data, alphabet)
	alphabet = alphabet or DEFAULT_ALPHABET

	assert(#alphabet == 64, 'alphabet must be 64 characters long')

	local map = {}
	for i = 1, 64 do
		map[byte(alphabet, i)] = i - 1
	end

	local result, n = {}, 1

	local buffer, i, j = 0, 1, 0
	while i <= #data do
		local e = byte(data, i)
		i = i + 1

		if e == 0x0A or e == 0x0D then
			-- skip newlines
		elseif e == 0x3D then
			-- padding character, stop processing
			break
		else
			local v = map[e]
			if not v then
				-- invalid character, stop processing
				return nil
			end

			buffer = buffer * 0x40 + v
			j = j + 1

			if j == 4 then
				local d1 = rshift(band(buffer, 0xFF0000), 16)
				local d2 = rshift(band(buffer, 0x00FF00), 8)
				local d3 = band(buffer, 0x0000FF)

				result[n] = char(d1, d2, d3)
				n = n + 1

				buffer, j = 0, 0
			end
		end
	end

	if j == 3 then
		local d1 = rshift(buffer, 10)
		local d2 = band(rshift(buffer, 2), 0xFF)

		result[n] = char(d1, d2)
		n = n + 1
	elseif j == 2 then
		local d1 = band(rshift(buffer, 4), 0xFF)

		result[n] = char(d1)
		n = n + 1
	elseif j == 1 then
		return nil
	end

	return concat(result, nil, 1, n - 1)
end

return base64
