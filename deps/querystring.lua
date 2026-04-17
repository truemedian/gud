local uri = require('uri')
local utility = require('utility')

local querystring = {}

--- @param str string
--- @param space string|nil
--- @return table
function querystring.decode(str, space)
	local result = {}
	for pair in string.split(str, '&', true) do
		local key, value = pair:match('([^=]*)=?(.*)')
		if key then
			key = uri.percentDecode(key, space)
			value = uri.percentDecode(value, space)

			if result[key] then
				if type(result[key]) == 'table' then
					table.insert(result[key], value)
				else
					result[key] = { result[key], value }
				end
			else
				result[key] = value
			end
		end
	end

	return result
end

--- @param tbl table
--- @param space string|nil
--- @return string
function querystring.encode(tbl, space)
	local parts, n = {}, 0
	for key, value in spairs(tbl) do
		key = uri.percentEncode(tostring(key), space)

		if type(value) == 'table' then
			for _, v in ipairs(value) do
				n = n + 1
				parts[n] = key .. '=' .. uri.percentEncode(tostring(v), space)
			end
		else
			n = n + 1
			parts[n] = key .. '=' .. uri.percentEncode(tostring(value), space)
		end
	end

	return table.concat(parts, '&', 1, n)
end

return querystring
