local luvi = require("luvi")
local readable = import("stream/readable")
local pretty = import("pretty")
local fs = import("fs")

local utility = {}

local function shortname(source)
	if source:sub(1, 1) == "@" then
		return source:sub(2)
	elseif source:sub(1, 1) == "=" then
		return source:sub(2)
	elseif #source >= 40 then
		return source:sub(1, 39) .. "..."
	else
		return source
	end
end

local function functionname(f, tbl, left, seen)
	if left <= 0 or seen[tbl] then
		return nil, 0
	end

	seen[tbl] = true
	local best_name, best_level = nil, 0
	for k, v in pairs(tbl) do
		if type(k) == "string" and v == f then
			return k, left
        elseif type(v) == "table" then
			local name, level = functionname(f, v, left - 1, seen)
			if name and level > best_level then
				best_name = k .. "." .. name
				best_level = level
			end
		end
	end

	return best_name, best_level
end

local sources = {}
function utility.find_line(source, line)
	local name = shortname(source)

	local content = sources[name]
	if not content then
		if name:sub(1, 7) == "bundle:" then
			content = luvi.bundle.readfile(name:sub(8))
		else
			content = fs.readFile(name)
		end

		if not content then
			return nil
		end

		sources[name] = content
	end

	local stream = readable.string(content)
	while line > 1 do
		local chunk = stream:readLine()
		if not chunk then
			return nil
		end

		line = line - 1
	end

	local chunk = stream:readLine()
	if not chunk then
		local chunk_eof = stream:readAtLeast(1)
		if not chunk_eof then
			return nil
		end

		return chunk_eof
	end

	return chunk:tostring()
end

function utility.capturestack(level, thread)
	thread = thread or coroutine.running()
	level = level or 1

	local stack, i = {}, 1
	while true do
		local info = debug.getinfo(thread, level, "Slnf")
		if not info then
			break
		end

		stack[i] = info
		i = i + 1

		level = level + 1
	end

	return stack
end

function utility.traceback(err, stack)
	local parts, i = {}, 1

	if err ~= nil then
		parts[i] = pretty.colorize("error: " .. err, "fail") .. "\n"
		i = i + 1
	end

	for _, info in ipairs(stack) do
		if info.what == "C" then
			parts[i] = pretty.colorize("[C]:", "file")
			i = i + 1
		elseif info.currentline > 0 then
			parts[i] = pretty.colorize(string.format("%s:%d:", shortname(info.source), info.currentline), "file")
			i = i + 1
		else
			parts[i] = pretty.colorize(shortname(info.source) .. ":", "file")
		end

		if info.what == "main" then
			parts[i] = " in " .. pretty.colorize("main chunk", "info")
			i = i + 1
		elseif info.namewhat ~= "" then
			local best_name, best_level = nil, 0
			for k, v in pairs(package.loaded) do
				if type(v) == "table" then
					local name, score = functionname(info.func, v, 5, { [v] = true })

					if name and score > best_level then
						best_name = k .. "." .. name
						best_level = score
					end
				end
			end

			local name = best_name or info.name or "?"

			parts[i] = string.format(" in %s ", info.namewhat) .. pretty.colorize("'" .. name .. "'", "info")
			i = i + 1
		elseif info.what ~= "C" then
			parts[i] = " in anonymous function at "
				.. pretty.colorize(string.format("%s:%d", shortname(info.source), info.linedefined), "info")
			i = i + 1
		else
			parts[i] = " in C function"
			i = i + 1
		end

		parts[i] = "\n"
		i = i + 1

		local line_data = utility.find_line(info.source, info.currentline)
		if line_data then
			parts[i] = pretty.colorize(line_data, "code") .. "\n"
			i = i + 1
		end

		if info.what == "tail" or info.istailcall then
			parts[i] = "  ...(tail calls)...\n"
			i = i + 1
		end
	end

	return table.concat(parts, "")
end

utility.exception = {}
utility.exception.__index = utility.exception
function utility.exception:__tostring()
	return tostring(self[1])
end

function utility.exception:message()
	return self[1]
end

function utility.exception:traceback()
	local parts, i = {}, 1

	if self[1] ~= nil then
		parts[i] = pretty.colorize("error: " .. tostring(self[1]), "fail") .. "\n"
		i = i + 1
	else
		parts[i] = pretty.colorize("error: <unknown>", "fail") .. "\n"
		i = i + 1
	end

	for j = 2, #self do
		parts[i] = utility.traceback(nil, self[j])
		i = i + 1

		parts[i] = pretty.colorize("rethrown from here", "debug") .. "\n"
		i = i + 1
	end

	return table.concat(parts, "", 1, i - 2)
end

local raw_error = _G.error
function utility.error(msg, level)
	level = level or 1
	local stack = utility.capturestack(level + 2)

	if getmetatable(msg) == utility.exception then
		msg[#msg + 1] = stack
		return raw_error(msg, level)
	else
		msg = setmetatable({ msg }, utility.exception)
		msg[#msg + 1] = stack
		return raw_error(msg, level)
	end
end

function utility.assert(v, ...)
	if not v then
		return utility.error(... or "assertion failed!", 1)
	end

	return v
end

local function assertresume_aux(success, ...)
	if success then
		return ...
	else
		return error(..., 1)
	end
end

function utility.assertresume(co, ...)
	return assertresume_aux(coroutine.resume(co, ...))
end

_G.error = utility.error
_G.assert = utility.assert

return utility
