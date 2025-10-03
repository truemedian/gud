local luv = require("luv")

local function get_os_name()
	-- shortcuts for luajit if available
	local has_jit, jit = pcall(require, "jit")
	if has_jit and jit and jit.os then
		return jit.os
	end

	local has_ffi, ffi = pcall(require, "ffi")
	if has_ffi and ffi and ffi.os then
		return ffi.os
	end

	-- Handles windows
	if os and os.getenv then
		if os.getenv("OS") then
			return os.getenv("OS")
		end
	end

	-- use libuv provided uname if possible, but it's not always available
	if luv.os_uname then
		local info = luv.os_uname()
		if info then
			return info.sysname
		end
	end

	return "other"
end

local function get_arch_name()
	-- shortcuts for luajit if available
	local has_jit, jit = pcall(require, "jit")
	if has_jit and jit and jit.arch then
		return jit.arch
	end

	local has_ffi, ffi = pcall(require, "ffi")
	if has_ffi and ffi and ffi.arch then
		return ffi.arch
	end

	-- use libuv provided uname if possible, but it's not always available
	if luv.os_uname then
		local info = luv.os_uname()
		if info then
			return info.machine
		end
	end

	return "other"
end

local os_patterns = {
	["windows"] = "windows",
	["linux"] = "linux",
	["mac"] = "darwin",
	["darwin"] = "darwin",
	["^mingw"] = "windows",
	["^msys"] = "windows",
	["^cygwin"] = "windows",
	["bsd$"] = "bsd",
	["posix"] = "posix",
}

local machine_patterns = {
	["^x86$"] = "x86",
	["^i[%d]86$"] = "x86",
	["^amd64$"] = "x64",
	["^x86_64$"] = "x64",
	["^aarch64$"] = "arm64",
	["^armv[%d]l$"] = "arm",
	["^armv[%d]hf$"] = "arm",
	["^arm$"] = "arm",
	["^ppc$"] = "ppc",
	["^ppc64$"] = "ppc64",
	["^mips$"] = "mips",
	["^mipsel$"] = "mipsel",
}

local os_name = string.lower(get_os_name())
for pattern, name in pairs(os_patterns) do
	if os_name:find(pattern) then
		os_name = name
		break
	end
end

local arch_name = string.lower(get_arch_name())
for pattern, name in pairs(machine_patterns) do
	if arch_name:find(pattern) then
		arch_name = name
		break
	end
end

return {
	os = os_name,
	arch = arch_name,
}
