local uv = require("uv")

local path, fs
if import then
	fs = import("fs")
	path = import("path")
else
	path = require("bundle:path")
end

local has_luvi, luvi = pcall(require, "luvi")

local _, bootstrap = ...
local import = bootstrap
if not import then
	import = {}
	import.stat_cache = {}
	import.module_cache = {}
	import.loaders = {}
end

function import.loaders.lua(name, file, content, env, ...)
	local fn, syntax_err = load(content, "@" .. file, "t", env)
	assert(fn, string.format("error loading module %q from file %q:\n\t%s", name, file, syntax_err), 3)

	return fn(name, ...)
end

local function statFile(key, full_path, bundled, attempts)
	if import.stat_cache[key] ~= nil then
		return true
	end

	if bundled then
		local stat = luvi.bundle.stat(full_path)
		if not stat then
			attempts[#attempts + 1] = string.format("no file %q", key)

			return false
		end

		import.stat_cache[key] = stat
	else
		local stat = uv.fs_stat(full_path)
		if not stat then
			attempts[#attempts + 1] = string.format("no file %q", key)

			return false
		end

		import.stat_cache[key] = stat
	end

	return true
end

---Note: A `nil` error with a missing key and path indicates file not found
---@return string|nil cache_key
---@return string|nil full_path
---@return boolean|nil has_root
local function resolvePackageInner(base_key, base_path, bundled, attempts)
	local key_single = base_key .. ".lua"
	local full_path_single = base_path .. ".lua"

	if statFile(key_single, full_path_single, bundled, attempts) then
		return key_single, full_path_single, false
	end

	local key_multi = path.join(base_key, "init.lua")
	local full_path_multi = path.join(base_path, "init.lua")

	if statFile(key_multi, full_path_multi, bundled, attempts) then
		return key_multi, full_path_multi, true
	end
end

---Note: A `nil` error with a missing key and path indicates file not found
---@return string|nil cache_key
---@return string|nil full_path
---@return boolean|nil has_root
local function resolvePackage(module, name, attempts)
	local normalized_name = path.resolve(name, "")

	if not module.bundled then
		if path.extension(name) ~= "" then
			return nil, nil, nil
		end

		local full_path = path.join(module.project, "deps", normalized_name)
		local key = "fs:" .. full_path

		local cache_key, found_path, has_root = resolvePackageInner(key, full_path, false, attempts)
		if cache_key then
			return cache_key, found_path, has_root
		end
	end

	if not module.bundled then
		if import.global_package_cache == nil then
			import.global_package_cache = os.getenv("LUVIT_PACKAGE_DIR") or false
		end

		if import.global_package_cache then
			local global_full_path = path.join(import.global_package_cache, normalized_name)
			local global_key = "fs:" .. global_full_path

			local cache_key, found_path, has_root = resolvePackageInner(global_key, global_full_path, false, attempts)
			if cache_key then
				return cache_key, found_path, has_root
			end
		end
	end

	if not has_luvi or path.posix.extension(name) ~= "" then
		return nil, nil, nil
	end

	-- always attempt to load packages from the bundle, but don't allow imports to escape the bundle once they enter.

	-- bundled deps should always be at the top
	local full_path = "/" .. path.posix.join("deps", normalized_name)
	local key = "bundle:" .. full_path

	local cache_key, found_path, has_root = resolvePackageInner(key, full_path, true, attempts)
	if cache_key then
		return cache_key, found_path, has_root
	end

	return nil, nil, nil
end

---Note: A `nil` error with a missing key and path indicates file not found
---@return nil|string err
---@return string|nil cache_key
---@return string|nil full_path
local function resolveRelative(module, name, attempts)
	if module.root == nil then
		return "single file packages cannot import relative modules", nil, nil
	end

	if module.bundled then
		assert(has_luvi)

		if path.posix.extension(name) == "" then
			return nil, nil, nil
		end

		local full_path = path.posix.resolve(name, module.dir)
		local relative_to_root = path.posix.relative(module.root, full_path)
		if relative_to_root:sub(1, 2) == ".." then
			return "import of file outside outside of package path", nil, nil
		end

		local key = "bundle:" .. full_path
		if statFile(key, full_path, true, attempts) then
			return nil, key, full_path
		end

		return nil, nil, nil
	end

	if path.extension(name) == "" then
		return nil, nil, nil
	end

	local full_path = path.resolve(name, module.dir)

	local relative_to_root = path.relative(module.root, full_path)

	if relative_to_root:sub(1, 2) == ".." then
		return "import of file outside outside of package path", nil, nil
	end

	local key = "fs:" .. full_path

	if statFile(key, full_path, false, attempts) then
		return nil, key, full_path
	end

	return nil, nil, nil
end

local Module = {}
local Module_meta = { __index = Module }
local env_meta = { __index = _G }

---@return string|nil cache_key
---@return string|nil full_path
---@return nil|string err
---@return boolean is_package
---@return boolean|nil package_has_root
---@return table attempts
function Module:resolve(name)
	local attempts = {}

	local key, full_path, package_has_root = resolvePackage(self, name, attempts)
	if key then
		return key, full_path, nil, true, package_has_root, attempts
	end

	local err
	err, key, full_path = resolveRelative(self, name, attempts)
	return key, full_path, err, false, package_has_root, attempts
end

function Module:import(name, ...)
	local key, full_path, err, is_package, package_has_root, attempts = self:resolve(name)

	if not key or not full_path then
		local attempt_str = table.concat(attempts, "\n\t")

		if err then -- something else went wrong
			error(string.format("module %q not found: %s\n\t%s", name, err, attempt_str))
		end

		-- the file was not found
		error(string.format("module %q not found:\n\t%s", name, attempt_str))
	end

	if import.module_cache[key] ~= nil then
		return import.module_cache[key].exports
	end

	local full_path_extension = path.extension(full_path)
	local loader = import.loaders[full_path_extension:sub(2)]

	if not loader then
		error(
			string.format(
				"error loading module %q from file %q: no import loader for %q files",
				name,
				key,
				full_path_extension
			),
			2
		)
	end

	local is_bundled = key:sub(1, 7) == "bundle:"

	local new_dir = path.dirname(full_path)
	local new_root, new_project

	if is_bundled then
		new_project = nil
	else
		new_project = self.project
	end

	if is_package then
		if package_has_root then
			new_root = new_dir
		end
	else
		new_root = self.root
	end

	local new_module = setmetatable({
		bundled = is_bundled,
		file = full_path,
		dir = new_dir,
		root = new_root,
		project = new_project,
		exports = {},
	}, Module_meta)

	local content
	if is_bundled then
		content = assert(luvi.bundle.readfile(full_path))
	else
		assert(fs, "attempt to use filesystem while bootstrapping import")
		content = assert(fs.readFile(full_path))
	end

	local env = setmetatable({
		module = new_module,
		exports = new_module.exports,
		import = function(...)
			return new_module:import(...)
		end,
	}, env_meta)

	local ret = loader(name, key, content, env, ...)

	import.module_cache[key] = new_module

	if ret ~= nil then
		new_module.exports = ret
	end

	return new_module.exports
end

function import.new(entrypoint, is_bundled)
	local dirname
	if is_bundled then
		assert(has_luvi)

		entrypoint = path.posix.resolve(entrypoint, "/")
		dirname = path.posix.dirname(entrypoint)
	else
		entrypoint = path.resolve(entrypoint)
		dirname = path.dirname(entrypoint)
	end

	local new_module = setmetatable({
		bundled = is_bundled,
		file = entrypoint,
		dir = dirname,
		root = dirname,
		project = dirname,
	}, Module_meta)

	return new_module
end

return import
