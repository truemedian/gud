local luv = require("luv")

local readable = import("stream/readable")
local writable = import("stream/writable")

---@class std.process
local process = {}

local original_env = luv.os_environ()

local env_meta = {}
function env_meta:__index(key)
	return os.getenv(key)
end

function env_meta:__newindex(key, value)
	if value then
		local success, err = luv.os_setenv(key, value)
		if success then
			original_env[key] = value
		else
			error(err)
		end
	else
		local success, err = luv.os_unsetenv(key)
		if success then
			original_env[key] = nil
		else
			error(err)
		end
	end
end

function env_meta:__pairs()
	local last
	return function()
		local k, v = next(original_env, last)
		last = k

		return k, v
	end
end

process.env = setmetatable({}, env_meta)

process.pid = luv.os_getpid()
process.ppid = luv.os_getppid()

local uname = luv.os_uname()
process.os = { release = uname.release, arch = uname.machine, name = uname.sysname }

if uname.sysname == "Windows_NT" or uname.sysname:sub(1, 10) == "MINGW32_NT" then
	process.os.name = "Windows"

	if uname.machine == "ia64" then
		process.os.arch = "x86_64"
	end
end

if luv.guess_handle(0) == "file" then
	process.stdin = readable.file(0)
	process.stdin.is_tty = false
elseif luv.guess_handle(0) == "tty" then
	local stream = luv.new_tty(0, true)
	process.stdin = readable.stream(stream)
	process.stdin.is_tty = true
else
	local stream = luv.new_pipe(false)
	luv.pipe_open(stream, 0)
	process.stdin = readable.stream(stream)
	process.stdin.is_tty = false
end

if luv.guess_handle(1) == "file" then
	process.stdout = writable.file(1)
	process.stdout.is_tty = false
elseif luv.guess_handle(1) == "tty" then
	local stream = luv.new_tty(1, false)
	process.stdout = writable.stream(stream)
	process.stdout.is_tty = true
else
	local stream = luv.new_pipe(false)
	luv.pipe_open(stream, 1)
	process.stdout = writable.stream(stream)
	process.stdout.is_tty = false
end

if luv.guess_handle(2) == "file" then
	process.stderr = writable.file(2)
	process.stderr.is_tty = false
elseif luv.guess_handle(2) == "tty" then
	local stream = luv.new_tty(2, false)
	process.stderr = writable.stream(stream)
	process.stderr.is_tty = true
else
	local stream = luv.new_pipe(false)
	luv.pipe_open(stream, 2)
	process.stderr = writable.stream(stream)
	process.stderr.is_tty = false
end

---Returns the current working directory of the process.
---
---@return path_t
function process.getCwd()
	return luv.cwd()
end

---Sets the current working directory of the process.
---
---@param new_cwd path_t
---@return boolean success
---@return string | nil error
---@return string | nil errno
function process.setCwd(new_cwd)
	local ret, err, errno = luv.chdir(new_cwd)
	return ret == 0, err, errno
end

---Returns the path to the current executable.
---
---@return path_t
function process.getSelfExePath()
	return luv.exepath()
end

---Kills the process with the specified PID.
---
---@param pid integer
---@param signal string
---@return boolean success
---@return string | nil error
---@return string | nil errno
function process.kill(pid, signal)
	local ret, err, errno = luv.kill(pid, signal)
	return ret == 0, err, errno
end

---Exits the process with the specified exit code.
---
---@param code integer
function process.exit(code)
	-- TODO: clean up stdio

	os.exit(code)
end

---Returns the current memory usage of the process.
---
---@return { total: integer, free: integer, constrained: integer, rss: integer, heap: number }
function process.memoryUsage()
	return {
		total = luv.get_total_memory(),
		free = luv.get_free_memory(),
		constrained = luv.get_constrained_memory(),
		rss = luv.resident_set_memory(),
		heap = collectgarbage("count") * 1024,
	}
end

---Returns the current resource usage of the process.
---
---@return { user_time: number, system_time: number, max_resident_memory: integer, minor_page_fault: integer, major_page_fault: integer, file_input: integer, file_output: integer, voluntary_context_switch: integer, involuntary_context_switch: integer }
function process.cpuUsage()
	local usage = luv.getrusage()

	return {
		user_time = usage.utime.sec + usage.utime.usec / 1e6,
		system_time = usage.stime.sec + usage.stime.usec / 1e6,
		max_resident_memory = usage.maxrss,
		minor_page_fault = usage.minflt,
		major_page_fault = usage.majflt,
		file_input = usage.inblock,
		file_output = usage.oublock,
		voluntary_context_switch = usage.nvcsw,
		involuntary_context_switch = usage.nivcsw,
	}
end

return process
