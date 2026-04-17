local abs = math.abs

local identity = {}

--- @class std.git.identity
--- @field name string
--- @field email string
--- @field time integer
--- @field offset integer

--- Determine if a name/email is safe for use in an identity (i.e., does not contain problematic characters).
--- @param name string
--- @return boolean
function identity.is_safe(name)
	return type(name) == 'string' and name ~= '' and not name:find('[<>]')
end

--- @param line string
--- @return std.git.identity|nil parsed
--- @return string|nil err
function identity.parse(line)
	local name, email, when, tz_hr, tz_min = line:match('^([^<]*) <([^>]*)> (%-?%d+) ([%+%-]%d%d)(%d%d)$')
	if not name then
		return nil, 'invalid identity line'
	end

	local tz_hour = tonumber(tz_hr)
	local tz_minute = tonumber(tz_min)
	if not tz_hour or not tz_minute then
		return nil, 'invalid identity line'
	end

	local sign = tz_hr:sub(1, 1) == '-' and -1 or 1
	local offset = sign * (abs(tz_hour) * 60 + tz_minute)

	return {
		name = name,
		email = email,
		time = tonumber(when),
		offset = offset,
	}
end

--- @param value std.git.identity
--- @return string|nil line
--- @return string|nil err
function identity.format(value)
	local offset = value.offset
	local sign = offset < 0 and '-' or '+'
	local tz_hr, tz_min = math.floor(math.abs(offset) / 60), math.abs(offset) % 60

	if not identity.is_safe(value.name) then
		return nil, 'identity name contains unsafe characters'
	elseif not identity.is_safe(value.email) then
		return nil, 'identity email contains unsafe characters'
	end

	return string.format('%s <%s> %d %s%02d%02d', value.name, value.email, value.time, sign, tz_hr, tz_min)
end

return identity
