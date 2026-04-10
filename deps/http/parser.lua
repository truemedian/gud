local byte, sub, find, match = string.byte, string.sub, string.find, string.match

local parser = {}

--- @param s string
--- @return boolean
local function is_value(s)
	return not find(s, '[^\x20-\xFF\t]', 1)
end

--- @param s string
--- @return boolean
local function is_token(s)
	if #s == 0 then
		return false
	end

	return not find(s, "[^!#$%&'*+-.^_`|~%w]", 1)
end

--- @param s string
--- @param i number
--- @param j number
--- @return string
local function field_value(s, i, j)
	while i <= j do
		local b = byte(s, i)
		if b ~= 0x20 and b ~= 0x09 then -- SP or HTAB
			break
		end

		i = i + 1
	end

	while j >= i do
		local b = byte(s, j)
		if b ~= 0x20 and b ~= 0x09 then -- SP or HTAB
			break
		end

		j = j - 1
	end

	if i > j then
		return ''
	end

	if i == 1 and j == #s then
		return s
	end

	return sub(s, i, j)
end

--- @param line string
--- @return string|nil method
--- @return string target
--- @return string version
--- @return number last
function parser.parse_request_line(line)
	local method, target, version, last = match(line, '^(%S+) (%S+) HTTP/(%d%.%d)\r?\n()')
	return method, target, version, last
end

--- @param line string
--- @return string|nil version
--- @return number status_code
--- @return string reason_phrase
--- @return number last
function parser.parse_response_line(line)
	local version, status_code, reason_phrase, last = match(line, '^HTTP/(%d%.%d) (%d%d%d) ([^\r\n]*)\r?\n()')
	---@diagnostic disable-next-line: return-type-mismatch
	return version, tonumber(status_code), reason_phrase, last
end

local function finish_field(headers, current_name, current_value)
	if current_name then
		if not is_value(current_value) then
			return false, 'malformed header line'
		end

		headers:add(current_name, current_value)
		current_name = nil
	end

	return true
end

--- @param headers std.http.headers
--- @param head string
--- @param i number
--- @return boolean success
--- @return string|nil err
function parser.parse_head(headers, head, i)
	local current_name
	local current_value

	while true do
		local line_start = i
		local line_end = find(head, '\n', line_start, true)
		if not line_end then
			return false, 'missing head termination'
		end

		i = line_end + 1
		local value_end = line_end - 1
		if value_end >= line_start and byte(head, value_end) == 0x0D then -- CR
			value_end = value_end - 1
		end

		if value_end < line_start then
			if i <= #head then
				return false, 'extraneous data after head termination'
			end

			return finish_field(headers, current_name, current_value)
		end

		local first = byte(head, line_start)
		if first == 0x20 or first == 0x09 then -- SP or HTAB
			if not current_name then
				return false, 'malformed header line'
			end

			current_value = current_value .. ' ' .. field_value(head, line_start, value_end)
		else
			local _, finish_err = finish_field(headers, current_name, current_value)
			if finish_err then
				return false, finish_err
			end

			local colon = find(head, ':', line_start + 1, true)
			if not colon or colon > value_end then
				return false, 'malformed header line'
			end

			local name = sub(head, line_start, colon - 1)
			if not is_token(name) then
				return false, 'invalid header name'
			end

			current_name = name
			current_value = field_value(head, colon + 1, value_end)
		end
	end
end

return parser
