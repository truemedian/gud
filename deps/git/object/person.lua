---@class git.object.person
---@field name string
---@field email string
---@field time number
---@field offset number
local person = {}
local person_mt = { __index = person }

function person.new(name, email, offset)
	return setmetatable({
		name = name,
		email = email,
		time = 0,
		offset = offset or 0,
	}, person_mt)
end

---@param data any
---@return git.object.person|nil, string|nil
function person.decode(data)
	local name, email, time = string.match(data, '([^<]*) <([^>]*)> (.+)')
	if not name then
		return nil, 'person.decode: malformed person data'
	end

	local seconds, offset_hr, offset_min = string.match(time, '(%d+) ([+-]%d%d)(%d%d)')
	if not seconds then
		return nil, 'person.decode: malformed time data'
	end

	local offset = tonumber(offset_hr) * 60 + tonumber(offset_min)
	if not (offset >= -1440 and offset <= 1440) then
		return nil, 'person.decode: malformed time offset (must be between -1440 and 1440)'
	end

	return setmetatable({
		name = name,
		email = email,
		time = tonumber(seconds),
		offset = offset,
	}, person_mt),
		nil
end

---@return string
function person:encode()
	local safe_name = self.name:gsub('[%c<>]', '')
	local safe_email = self.email:gsub('[%c<>]', '')

	local offset_hr = math.floor(self.offset / 60)
	local offset_min = self.offset % 60

	return string.format('%s <%s> %d %+03d%02d', safe_name, safe_email, self.time, offset_hr, offset_min)
end

function person:update_time()
	self.time = os.time()
end

return person
