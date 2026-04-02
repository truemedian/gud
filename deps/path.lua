local luv = require('luv')

local sub, lower, find, match, gmatch = string.sub, string.lower, string.find, string.match, string.gmatch
local concat = table.concat
local max = math.max

--- @class std.path
local path = {}

--- @class std.path.posix
path.posix = {}
path.posix.sep = '/'

--- @class std.path.windows
path.windows = {}
path.windows.sep = '\\'

--- @param impl std.path.posix|std.path.windows
--- @param parts table
--- @param i integer
--- @param pathname string
--- @return integer
local function append_parts(impl, parts, i, pathname)
	for part in impl.split(pathname) do
		if part ~= '.' then
			i = i + 1
			parts[i] = part
		end
	end

	return i
end

--- @param pathname string
--- @param expected_ext? string|true
--- @param basename_pattern string
--- @return string
local function basename_impl(pathname, expected_ext, basename_pattern)
	local basename = match(pathname, basename_pattern) or ''

	if expected_ext == true then
		local last_dot = find(basename, '%.[^%.]*$')

		if last_dot and last_dot ~= 1 then
			return sub(basename, 1, last_dot - 1)
		else
			return basename
		end
	elseif expected_ext then
		if find(basename, expected_ext, #basename - #expected_ext + 1, true) then
			return sub(basename, 1, -#expected_ext - 1)
		else
			return basename
		end
	else
		return basename
	end
end

--- @param impl std.path.posix|std.path.windows
--- @param parts table
--- @param i integer
--- @param pathname string
--- @param min integer
--- @return string, integer
local function resolve_middle_impl(impl, parts, i, pathname, min)
	for part in impl.split(pathname) do
		if part == '..' then
			i = max(i - 1, min)
		elseif part ~= '.' then
			i = i + 1
			parts[i] = part
		end
	end

	return concat(parts, impl.sep, 1, i), i
end

--- @param impl std.path.posix|std.path.windows
--- @param original string
--- @param middle string
--- @param absolute boolean
--- @param root string
--- @return string
local function resolve_finalize_impl(impl, original, middle, absolute, root)
	if middle == '' then
		if impl.isDirectory(original) then
			if absolute then
				return root ~= '' and root or impl.sep
			end

			return '.' .. impl.sep
		end

		if absolute then
			return root ~= '' and root or impl.sep
		end

		return '.'
	end

	if absolute then
		local prefix = root ~= '' and root or impl.sep
		if impl.isDirectory(original) then
			return prefix .. middle .. impl.sep
		end

		return prefix .. middle
	end

	if impl.isDirectory(original) then
		return middle .. impl.sep
	end

	return middle
end

--- @param impl std.path.posix|std.path.windows
--- @param from string
--- @param to string
--- @return string
local function relative_impl(impl, from, to)
	from = impl.resolve(from)
	to = impl.resolve(to)

	if impl.getRoot(from) ~= impl.getRoot(to) then
		return to
	end
	if from == to then
		return '.'
	end

	local from_parts, to_parts = { n = 0 }, { n = 0 }
	for part in impl.split(from) do
		from_parts.n = from_parts.n + 1
		from_parts[from_parts.n] = part
	end

	for part in impl.split(to) do
		to_parts.n = to_parts.n + 1
		to_parts[to_parts.n] = part
	end

	local i = 1
	while from_parts[i] and to_parts[i] and from_parts[i] == to_parts[i] do
		i = i + 1
	end

	local rel_parts = { n = 0 }
	for _ = i, from_parts.n do
		rel_parts.n = rel_parts.n + 1
		rel_parts[rel_parts.n] = '..'
	end

	for j = i, to_parts.n do
		rel_parts.n = rel_parts.n + 1
		rel_parts[rel_parts.n] = to_parts[j]
	end

	return concat(rel_parts, impl.sep)
end

--- Whether a path is absolute.
--- @param pathname string
--- @return boolean
function path.posix.isAbsolute(pathname)
	return sub(pathname, 1, 1) == '/'
end

--- Whether a path is a directory (has a trailing separator).
--- @param pathname string
--- @return boolean
function path.posix.isDirectory(pathname)
	return sub(pathname, -1) == '/'
end

--- Returns a new path with no empty or redundant components
--- @param pathname string
--- @return string
function path.posix.normalize(pathname)
	return path.posix.join(pathname)
end

--- Returns the root of the path, will be "." for relative paths.
--- @param pathname string
--- @return string
function path.posix.getRoot(pathname)
	if path.posix.isAbsolute(pathname) then
		return '/'
	else
		return '.'
	end
end

--- Joins a list of paths together, does not duplicate path separators.
--- @param ... string
--- @return string
function path.posix.join(...)
	local first = select(1, ...)
	if first == nil then
		return ''
	end

	local parts, i = {}, 0
	if path.posix.isAbsolute(first) then
		i = i + 1
		parts[i] = ''
	end

	local len = select('#', ...)
	for j = 1, len do
		local pathname = select(j, ...)
		i = append_parts(path.posix, parts, i, pathname)
	end

	local last = select(len, ...)
	if path.posix.isDirectory(last) and i > 1 then
		i = i + 1
		parts[i] = ''
	end

	return concat(parts, '/', 1, i)
end

--- Splits a path into its directory components.
--- @param pathname string
--- @return fun(): string|nil
function path.posix.split(pathname)
	return gmatch(pathname, '[^/]+')
end

--- This function takes a path and returns a absolute path.
---
--- If the path uses `..` segments on the root directory, they are discarded.
--- It also resolves `.` and `..` segments.
--- The result does not have a trailing separator
---
--- If the path is relative, it uses `parent` or the current working directory as a starting point
--- Note: This function may not be correct when used on symlinked paths, it will not follow symlinks.
--- @param pathname string
--- @param parent? string
--- @return string
function path.posix.resolve(pathname, parent)
	local parts, i = {}, 0
	local absolute = path.posix.isAbsolute(pathname)
	local root = absolute and '/' or ''

	if not path.posix.isAbsolute(pathname) then
		local cwd_path = parent or luv.cwd() or '.'

		if path.posix.isAbsolute(cwd_path) then
			absolute = true
			root = '/'
		end

		i = append_parts(path.posix, parts, i, cwd_path)
	end

	local pathstr = resolve_middle_impl(path.posix, parts, i, pathname, 0)
	return resolve_finalize_impl(path.posix, pathname, pathstr, absolute, root)
end

--- Strip the last component from a path.
---
--- If the path is a file in the current directory (no directory component) or the root directory (just `/`)
--- Then this returns the empty string
--- @param pathname string
--- @return string
function path.posix.dirname(pathname)
	return match(pathname, '^(.+)/[^/]+/*$') or ''
end

--- Returns the name of a file from a path.
---
--- If the path has trailing slashes, they are stripped off and ignored.
---
--- If `expected_ext` is true, this will always strip the extension from the name.
--- If `expected_ext` is a string, this will only strip that string from the end.
--- @param pathname string
--- @param expected_ext? string|true
--- @return string
function path.posix.basename(pathname, expected_ext)
	return basename_impl(pathname, expected_ext, '([^/]+)/*$')
end

--- Returns the extension of the file name (if any).
---
--- Files that end with a `.` are considered to have no extension.
--- Files that start with a `.` do not consider the first `.` as an extension.
---
--- Examples:
---    'init.lua' => '.lua'
---    'src/init.lua' => '.lua'
---    '.gitignore' => ''
---    'keep.' => '.'
---    'init.lua.keep' => '.keep'
---    'src/init.lua.keep/' => '.keep'
--- @param pathname string
--- @return string
function path.posix.extension(pathname)
	local basename = path.posix.basename(pathname)
	return match(basename, '[^%.](%.[^%.]*)$') or ''
end

--- Returns the relative path from `from` to `to`.
---
--- If `from` and `to` each resolve to the same path (after calling `resolve` on each), `"."` is returned.
--- @param from string
--- @param to string
--- @return string
function path.posix.relative(from, to)
	return relative_impl(path.posix, from, to)
end

--- Whether a path is absolute.
--- @param pathname string
--- @return boolean
function path.windows.isAbsolute(pathname)
	return find(pathname, '^(\\\\[^\\]+\\)') ~= nil
		or find(pathname, '^[a-zA-Z]:[\\/]') ~= nil
		or find(pathname, '^[\\/]') ~= nil
end

--- Whether a path is a directory (has a trailing separator).
--- @param pathname string
--- @return boolean
function path.windows.isDirectory(pathname)
	local last = sub(pathname, -1)
	return last == '/' or last == '\\'
end

--- Returns a new path with no empty or redundant components
--- @param pathname string
--- @return string
function path.windows.normalize(pathname)
	return path.windows.join(pathname)
end

--- Returns the root of the path, will be "." for relative paths.
--- @param pathname string
--- @return string
function path.windows.getRoot(pathname)
	local unc_host = match(pathname, '^(\\\\[^\\]+\\)')
	if unc_host then
		return unc_host
	end

	local drive_abs = match(pathname, '^([a-zA-Z]:)[\\/]')
	if drive_abs then
		return drive_abs .. '\\'
	end

	local drive_rel = match(pathname, '^([a-zA-Z]:)')
	if drive_rel then
		return drive_rel
	end

	local abs = find(pathname, '^[\\/]')
	if abs then
		return '\\'
	end

	return '.'
end

--- Joins a list of paths together, does not duplicate path separators.
--- @param ... string
--- @return string
function path.windows.join(...)
	local first = select(1, ...)
	if first == nil then
		return ''
	end

	local root = path.windows.getRoot(first)
	local parts, i = {}, 0

	local len = select('#', ...)
	for j = 1, len do
		local pathname = select(j, ...)
		i = append_parts(path.windows, parts, i, pathname)
	end

	local last = select(len, ...)
	if path.windows.isDirectory(last) and i > 0 then
		i = i + 1
		parts[i] = ''
	end

	local joined = concat(parts, '\\', 1, i)
	if root ~= '.' then
		return root .. joined
	else
		return joined
	end
end

--- Splits a path into its directory components.
--- @param pathname string
--- @return fun(): string|nil
function path.windows.split(pathname)
	local root = path.windows.getRoot(pathname)
	return gmatch(pathname:sub(#root + 1), '[^/\\]+')
end

--- This function takes a path and returns a absolute path.
---
--- If the path uses `..` segments on the root directory, they are discarded.
--- It also resolves `.` and `..` segments.
--- The result does not have a trailing separator
---
--- If the path is relative, it uses `parent` or the current working directory as a starting point
--- Note: This function may not be correct when used on symlinked paths, it will not follow symlinks.
--- @param pathname string
--- @param parent? string
--- @return string
function path.windows.resolve(pathname, parent)
	local parts, i = {}, 0
	local absolute = path.windows.isAbsolute(pathname)
	local root = absolute and path.windows.getRoot(pathname) or ''
	local min = 0

	if not absolute then
		local cwd_path = parent or luv.cwd() or '.'
		local cwd_root = path.windows.getRoot(cwd_path)
		local path_root = path.windows.getRoot(pathname)

		if find(path_root, '^[a-zA-Z]:$') then
			if lower(sub(cwd_root, 1, 2)) == lower(path_root) then
				absolute = true
				root = cwd_root
				i = append_parts(path.windows, parts, i, cwd_path)
			else
				absolute = true
				root = path_root .. '\\'
			end
		else
			root = cwd_root
			if root ~= '.' then
				absolute = true
				i = append_parts(path.windows, parts, i, cwd_path)
			else
				root = ''
			end
		end
	end

	if absolute and find(root, '^\\\\[^\\]+\\$') then
		-- Keep at least the UNC share component when resolving "..".
		min = 1
	end

	local pathstr = resolve_middle_impl(path.windows, parts, i, pathname, min)
	return resolve_finalize_impl(path.windows, pathname, pathstr, absolute, root)
end

--- Strip the last component from a path.
---
--- If the path is a file in the current directory (no directory component) or the root directory (just `/`)
--- Then this returns the empty string
--- @param pathname string
--- @return string
function path.windows.dirname(pathname)
	return match(pathname, '^(.+)[/\\][^/\\]+[/\\]*$') or ''
end

--- Returns the name of a file from a path.
---
--- If the path has trailing slashes, they are stripped off and ignored.
---
--- If `expected_ext` is true, this will always strip the extension from the name.
--- If `expected_ext` is a string, this will only strip that string from the end.
--- @param pathname string
--- @param expected_ext? string|true
--- @return string
function path.windows.basename(pathname, expected_ext)
	return basename_impl(pathname, expected_ext, '([^/\\]+)[/\\]*$')
end

--- Returns the extension of the file name (if any).
---
--- Files that end with a `.` are considered to have no extension.
--- Files that start with a `.` do not consider the first `.` as an extension.
---
--- Examples:
---    'init.lua' => '.lua'
---    'src/init.lua' => '.lua'
---    '.gitignore' => ''
---    'keep.' => '.'
---    'init.lua.keep' => '.keep'
---    'src/init.lua.keep/' => '.keep'
--- @param pathname string
--- @return string
function path.windows.extension(pathname)
	local basename = path.windows.basename(pathname)
	return match(basename, '[^%.](%.[^%.]*)$') or ''
end

--- Returns the relative path from `from` to `to`.
---
--- If `from` and `to` each resolve to the same path (after calling `resolve` on each), `"."` is returned.
--- @param from string
--- @param to string
--- @return string
function path.windows.relative(from, to)
	return relative_impl(path.windows, from, to)
end

-- These are provided for easy access to the current platform's path functions.

local is_windows = package.config:sub(1, 1) == '\\'
if is_windows then
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
