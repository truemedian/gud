local max_header_size = 8192

local function fillHeaders(readable)
	local pos = 1
	while true do
		local avail = readable:peek()
		local idx1 = avail:find("\n\n", pos)

		if idx1 and idx1 <= max_header_size then
			return true
		end

		local idx2 = avail:find("\r\n\r\n", pos)

		if idx2 and idx2 <= max_header_size then
			return true
		end

		if readable.ended or readable.error then
			return false, readable.error or "end of stream"
		elseif #avail >= max_header_size then
			return false, "header too large"
		end

		pos = #avail - 2
		readable:fillAtLeast(1)
	end
end

local function parseHeaders(readable, context)
	local i = 1
	while true do
		local line = readable:readLine()
		if #line == 0 then
			break
		end

		-- please don't use header continuations
		if line:byte(1) == 9 or line:byte(1) == 32 then
			if i == 1 then
				return nil, "malformed header continuation"
			end

			context[i - 1].value = context[i - 1].value .. " " .. line:tostring():match("^[ \t]*(.-)%s*$")
		else
			local name, value = line:tostring():match("^([^:%s]+):%s*(.-)%s*$")
			if name and value then
				context[i] = { name:lower(), value }
				i = i + 1
			else
				return nil, "malformed header line"
			end
		end
	end

	return context
end

local function parseRequest(readable)
	local headers_ok, headers_err = fillHeaders(readable)
	if not headers_ok then
		return nil, headers_err
	end

	local status_line = readable:readLine():tostring()
	local method, path, version = status_line:match("^(%S+) (%S+) (%S+)$")
	if not method then
		return nil, "invalid status line"
	end

	if version ~= "HTTP/1.1" and version ~= "HTTP/1.0" then
		return nil, "unsupported HTTP version"
	end

	local context = {
		method = method,
		path = path,
		version = version,
	}

	return parseHeaders(readable, context)
end

local function parseResponse(readable)
	local headers_ok, headers_err = fillHeaders(readable)
	if not headers_ok then
		return nil, headers_err
	end

	local status_line = readable:readLine():tostring()
	local version, status_code, status_message = status_line:match("^(%S+) (%d%d%d) (.-)$")
	if not version then
		return nil, "invalid status line"
	end

	if version ~= "HTTP/1.1" and version ~= "HTTP/1.0" then
		return nil, "unsupported HTTP version"
	end

	local context = {
		version = version,
		status_code = tonumber(status_code),
		status_message = status_message,
	}

	return parseHeaders(readable, context)
end

return {
	parseRequest = parseRequest,
	parseResponse = parseResponse,
}
