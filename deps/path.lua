local luv = require("luv")
local target = import and import("target") or {}

---@alias path_t string

---@class std.path
local path = {}

---@class std.path.posix
path.posix = {}
path.posix.sep = "/"

---@class std.path.windows
path.windows = {}
path.windows.sep = "\\"

---Whether a path is absolute.
---@param pathname path_t
---@return boolean
function path.posix.isAbsolute(pathname)
	return string.sub(pathname, 1, 1) == "/"
end

---Whether a path is a directory (has a trailing separator).
---@param pathname path_t
---@return boolean
function path.posix.isDirectory(pathname)
	return string.sub(pathname, -1) == "/"
end

---Returns a new path with no empty or redundant components
---@param pathname path_t
---@return path_t
function path.posix.normalize(pathname)
	return path.posix.join(pathname)
end

---Returns the root of the path, will be "." for relative paths.
---@param pathname path_t
---@return path_t
function path.posix.getRoot(pathname)
	if path.posix.isAbsolute(pathname) then
		return "/"
	else
		return "."
	end
end

---Joins a list of paths together, does not duplicate path separators.
---@param ... path_t
---@return path_t
function path.posix.join(...)
	local first = select(1, ...)
	if first == nil then
		return ""
	end

	local parts, i = {}, 1
	if path.posix.isAbsolute(first) then
		parts[i] = ""
		i = i + 1
	end

	local len = select("#", ...)
	for j = 1, len do
		local pathname = select(j, ...)
		for part in path.posix.split(pathname) do
			if part ~= "." then
				parts[i] = part
				i = i + 1
			end
		end
	end

	local last = select(len, ...)
	if path.posix.isDirectory(last) and i > 1 then
		parts[i] = ""
		i = i + 1
	end

	return table.concat(parts, "/", 1, i - 1)
end

---Splits a path into its directory components.
---@param pathname path_t
---@return fun(): path_t|nil
function path.posix.split(pathname)
	return string.gmatch(pathname, "[^/]+")
end

---This function takes a path and returns a absolute path.
---
---If the path uses `..` segments on the root directory, they are discarded.
---It also resolves `.` and `..` segments.
---The result does not have a trailing separator
---
---If the path is relative, it uses `parent` or the current working directory as a starting point
---Note: This function may not be correct when used on symlinked paths, it will not follow symlinks.
---@param pathname path_t
---@param parent? path_t
---@return path_t
function path.posix.resolve(pathname, parent)
	local parts, i, min = {}, 1, 1

	if path.posix.isAbsolute(pathname) then
		parts[i] = ""
		i = i + 1
		min = 2
	else
		local cwd_path = parent or luv.cwd()

		if path.posix.isAbsolute(cwd_path) then
			parts[i] = ""
			i = i + 1
			min = 2
		end

		for part in path.posix.split(cwd_path) do
			parts[i] = part
			i = i + 1
		end
	end

	for part in path.posix.split(pathname) do
		if part == ".." then
			i = i - 1
		elseif part ~= "." then
			parts[i] = part
			i = i + 1
		end
	end

	if i <= min then
		i = min
		parts[i] = ""
	end

	if path.posix.isDirectory(pathname) and i > 1 then
		parts[i] = ""
		i = i + 1
	end

	return table.concat(parts, "/", 1, math.max(i - 1, min))
end

---Strip the last component from a path.
---
---If the path is a file in the current directory (no directory component) or the root directory (just `/`)
---Then this returns the empty string
---@param pathname path_t
---@return path_t
function path.posix.dirname(pathname)
	return string.match(pathname, "^(.+)/[^/]+/*$") or ""
end

---Returns the name of a file from a path.
---
---If the path has trailing slashes, they are stripped off and ignored.
---
---If `expected_ext` is true, this will always strip the extension from the name.
---If `expected_ext` is a string, this will only strip that string from the end.
---@param pathname path_t
---@param expected_ext? string|true
---@return string
function path.posix.basename(pathname, expected_ext)
	local basename = string.match(pathname, "([^/]+)/*$")

	if expected_ext == true then
		local last_dot = string.find(basename, "%.[^%.]*$")

		if last_dot and last_dot ~= 1 then
			return string.sub(basename, 1, last_dot - 1)
		else
			return basename
		end
	elseif expected_ext then
		if string.find(basename, expected_ext, #basename - #expected_ext + 1, true) then
			return string.sub(basename, 1, -#expected_ext - 1)
		else
			return basename
		end
	else
		return basename
	end
end

---Returns the extension of the file name (if any).
---
---Files that end with a `.` are considered to have no extension.
---Files that start with a `.` do not consider the first `.` as an extension.
---
---Examples:
---    'init.lua' => '.lua'
---    'src/init.lua' => '.lua'
---    '.gitignore' => ''
---    'keep.' => '.'
---    'init.lua.keep' => '.keep'
---    'src/init.lua.keep/' => '.keep'
---@param pathname path_t
---@return string
function path.posix.extension(pathname)
	local basename = path.posix.basename(pathname)
	return string.match(basename, "[^%.](%.[^%.]*)$") or ""
end

---Returns the relative path from `from` to `to`.
---
---If `from` and `to` each resolve to the same path (after calling `resolve` on each), `"."` is returned.
---@param from path_t
---@param to path_t
---@return path_t
function path.posix.relative(from, to)
	from = path.posix.resolve(from)
	to = path.posix.resolve(to)

	if from == to then
		return "."
	end

	local from_parts, to_parts = {}, {}
	for part in path.posix.split(from) do
		table.insert(from_parts, part)
	end

	for part in path.posix.split(to) do
		table.insert(to_parts, part)
	end

	local i = 1
	while from_parts[i] and to_parts[i] and from_parts[i] == to_parts[i] do
		i = i + 1
	end

	local rel_parts = {}
	for j = i, #from_parts do
		table.insert(rel_parts, "..")
	end

	for j = i, #to_parts do
		table.insert(rel_parts, to_parts[j])
	end

	return table.concat(rel_parts, "/")
end

---Whether a path is absolute.
---@param pathname path_t
---@return boolean
function path.windows.isAbsolute(pathname)
	return string.find(pathname, "^(\\\\[^\\]+\\)") ~= nil
		or string.find(pathname, "^[a-zA-Z]:[\\/]") ~= nil
		or string.find(pathname, "^[\\/]") ~= nil
end

---Whether a path is a directory (has a trailing separator).
---@param pathname path_t
---@return boolean
function path.windows.isDirectory(pathname)
	local last = string.sub(pathname, -1)
	return last == "/" or last == "\\"
end

---Returns a new path with no empty or redundant components
---@param pathname path_t
---@return path_t
function path.windows.normalize(pathname)
	return path.posix.join(pathname)
end

---Returns the root of the path, will be "." for relative paths.
---@param pathname path_t
---@return path_t
function path.windows.getRoot(pathname)
	local unc_host = string.match(pathname, "^(\\\\[^\\]+\\)")
	if unc_host then
		return unc_host
	end

	local drive_abs = string.match(pathname, "^([a-zA-Z]:)[\\/]")
	if drive_abs then
		return drive_abs .. "\\"
	end

	local drive_rel = string.match(pathname, "^([a-zA-Z]:)")
	if drive_rel then
		return drive_rel
	end

	local abs = string.find(pathname, "^[\\/]")
	if abs then
		return "\\"
	end

	return "."
end

---Joins a list of paths together, does not duplicate path separators.
---@param ... path_t
---@return path_t
function path.windows.join(...)
	local first = select(1, ...)
	if first == nil then
		return ""
	end

	local root = path.windows.getRoot(first)
	local parts, i = {}, 1

	local len = select("#", ...)
	for j = 1, len do
		local pathname = select(j, ...)
		for part in path.windows.split(pathname) do
			if part ~= "." then
				parts[i] = part
				i = i + 1
			end
		end
	end

	local last = select(len, ...)
	if path.windows.isDirectory(last) and i > 1 then
		parts[i] = ""
		i = i + 1
	end

	local joined = table.concat(parts, "\\", 1, i - 1)
	if root ~= "." then
		return root .. joined
	else
		return joined
	end
end

---Splits a path into its directory components.
---@param pathname path_t
---@return fun(): path_t|nil
function path.windows.split(pathname)
	local root = path.windows.getRoot(pathname)
	return string.gmatch(pathname:sub(#root + 1), "[^/\\]+")
end

---This function takes a path and returns a absolute path.
---
---If the path uses `..` segments on the root directory, they are discarded.
---It also resolves `.` and `..` segments.
---The result does not have a trailing separator
---
---If the path is relative, it uses `parent` or the current working directory as a starting point
---Note: This function may not be correct when used on symlinked paths, it will not follow symlinks.
---@param pathname path_t
---@param parent? path_t
---@return path_t
function path.windows.resolve(pathname, parent)
	error("not yet implemented")
end

---Strip the last component from a path.
---
---If the path is a file in the current directory (no directory component) or the root directory (just `/`)
---Then this returns the empty string
---@param pathname path_t
---@return path_t
function path.windows.dirname(pathname)
	return string.match(pathname, "^(.+)[/\\][^/\\]+[/\\]*$") or ""
end

---Returns the name of a file from a path.
---
---If the path has trailing slashes, they are stripped off and ignored.
---
---If `expected_ext` is true, this will always strip the extension from the name.
---If `expected_ext` is a string, this will only strip that string from the end.
---@param pathname path_t
---@param expected_ext? string|true
---@return string
function path.windows.basename(pathname, expected_ext)
	local basename = string.match(pathname, "([^/]+)/*$")

	if expected_ext == true then
		local last_dot = string.find(basename, "%.[^%.]*$")

		if last_dot and last_dot ~= 1 then
			return string.sub(basename, 1, last_dot - 1)
		else
			return basename
		end
	elseif expected_ext then
		if string.find(basename, expected_ext, #basename - #expected_ext + 1, true) then
			return string.sub(basename, 1, -#expected_ext - 1)
		else
			return basename
		end
	else
		return basename
	end
end

---Returns the extension of the file name (if any).
---
---Files that end with a `.` are considered to have no extension.
---Files that start with a `.` do not consider the first `.` as an extension.
---
---Examples:
---    'init.lua' => '.lua'
---    'src/init.lua' => '.lua'
---    '.gitignore' => ''
---    'keep.' => '.'
---    'init.lua.keep' => '.keep'
---    'src/init.lua.keep/' => '.keep'
---@param pathname path_t
---@return string
function path.windows.extension(pathname)
	local basename = path.windows.basename(pathname)
	return string.match(basename, "[^%.](%.[^%.]*)$") or ""
end

---Returns the relative path from `from` to `to`.
---
---If `from` and `to` each resolve to the same path (after calling `resolve` on each), `"."` is returned.
---@param from path_t
---@param to path_t
---@return path_t
function path.windows.relative(from, to)
	from = path.windows.resolve(from)
	to = path.windows.resolve(to)

	if path.windows.getRoot(from) ~= path.windows.getRoot(to) then
		return to
	end

	if from == to then
		return "."
	end

	local from_parts, to_parts = {}, {}
	for part in path.windows.split(from) do
		table.insert(from_parts, part)
	end

	for part in path.windows.split(to) do
		table.insert(to_parts, part)
	end

	local i = 1
	while from_parts[i] and to_parts[i] and from_parts[i] == to_parts[i] do
		i = i + 1
	end

	local rel_parts = {}
	for j = i, #from_parts do
		table.insert(rel_parts, "..")
	end

	for j = i, #to_parts do
		table.insert(rel_parts, to_parts[j])
	end

	return table.concat(rel_parts, "/")
end

-- These are provided for easy access to the current platform's path functions.

if target.os == "windows" then
	path.isAbsolute = path.windows.isAbsolute
	path.isDirectory = path.windows.isDirectory
	path.normalize = path.windows.normalize
	path.getRoot = path.windows.getRoot
	path.join = path.windows.join
	path.split = path.windows.split
	path.resolve = path.windows.resolve
	path.dirname = path.windows.dirname
	path.basename = path.windows.basename
	path.extension = path.windows.extension
	path.relative = path.windows.relative
else
	path.isAbsolute = path.posix.isAbsolute
	path.isDirectory = path.posix.isDirectory
	path.normalize = path.posix.normalize
	path.getRoot = path.posix.getRoot
	path.join = path.posix.join
	path.split = path.posix.split
	path.resolve = path.posix.resolve
	path.dirname = path.posix.dirname
	path.basename = path.posix.basename
	path.extension = path.posix.extension
	path.relative = path.posix.relative
end

return path
