local luv = require('luv')

local tonumber, type = tonumber, type
local concat, max = table.concat, math.max
local O_WRONLY = luv.constants.O_WRONLY
local O_CREAT = luv.constants.O_CREAT
local O_TRUNC = luv.constants.O_TRUNC

--- @class fd_t : integer

--- @class std.fs
local fs = {}

--- @param mode integer|string|nil
--- @param default_mode? integer
--- @return integer
local function normalize_mode(mode, default_mode)
	if mode == nil and default_mode then
		return default_mode
	end

	if type(mode) == 'number' then
		return mode
	elseif type(mode) == 'string' then
		return tonumber(mode, 8)
	end

	error('invalid mode')
end

--- The default permissions for a new directory.
fs.mode_directory = tonumber('755', 8)

--- The default permissions for a new file.
fs.mode_file = tonumber('644', 8)

------------------------------------------------------------------------------------------------------------------------
---                                       Functions that operate on file paths                                       ---
------------------------------------------------------------------------------------------------------------------------

--- Checks whether the current process has the requested permissions for the file at `path`.
---
--- Equivalent to [`access(2)`](https://man7.org/linux/man-pages/man2/access.2.html) in Posix.
--- @param path string
--- @param flags "R"|"W"|"X"
--- @return boolean|nil allowed
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.access(path, flags)
	return luv.fs_access(path, flags)
end

--- Changes the permissions of the file at `path`.
---
--- If `mode` is a string, it is interpreted as octal digits.
---
--- Equivalent to [`chmod(2)`](https://man7.org/linux/man-pages/man2/chmod.2.html) in Posix.
--- @param path string
--- @param mode integer
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.chmod(path, mode)
	return luv.fs_chmod(path, normalize_mode(mode))
end

--- Changes the ownership of the file at `path`.
---
--- Equivalent to [`chown(2)`](https://man7.org/linux/man-pages/man2/chown.2.html) in Posix.
--- @param path string
--- @param uid integer
--- @param gid integer
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.chown(path, uid, gid)
	return luv.fs_chown(path, uid, gid)
end

--- Copies a file from `path` to `new_path`.
---
--- If `mode` is provided, it is a table with the following fields:
---
--- * `excl`: The operation will fail if `new_path` already exists.
--- * `ficlone`: The operation will create a copy-on-write reflink. Ignored if the operation is not supported.
--- * `ficlone_force`: The operation will create a copy-on-write reflink. Fails if the operation is not supported.
--- @param path string
--- @param new_path string
--- @param mode? { excl: boolean, ficlone: boolean, ficlone_force: boolean }
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.copyfile(path, new_path, mode)
	return luv.fs_copyfile(path, new_path, mode)
end

--- Creates a hard link from `path` to `new_path`.
---
--- Equivalent to [`link(2)`](https://man7.org/linux/man-pages/man2/link.2.html) in Posix.
--- @param path string
--- @param new_path string
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.link(path, new_path)
	return luv.fs_link(path, new_path)
end

--- Returns information about the file at `path`. If `path` is a symbolic link, returns information about the link.
---
--- Equivalent to [`lstat(2)`](https://man7.org/linux/man-pages/man2/lstat.2.html) in Posix.
--- @param path string
--- @return uv.fs_stat.result|nil info
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.lstat(path)
	return luv.fs_lstat(path)
end

--- Creates a new directory with the given permissions. The default permissions are described in `fs.mode_directory`.
---
--- Equivalent to [`mkdir(2)`](https://man7.org/linux/man-pages/man2/mkdir.2.html) in Posix.
--- @param path string
--- @param mode? integer
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.mkdir(path, mode)
	return luv.fs_mkdir(path, normalize_mode(mode, fs.mode_directory))
end

--- Creates a unique temporary directory with the given template. There template must end with `'XXXXXX'`.
---
--- Equivalent to [`mkdtemp(3)`](https://man7.org/linux/man-pages/man3/mkdtemp.3.html) in Posix.
--- @param template string
--- @return string|nil temp_path
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.mkdtemp(template)
	return luv.fs_mkdtemp(template)
end

--- Returns a table of file entries for the provided directory.
--- @param path string
--- @return ({name: string, type: string}[])|nil entries
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.readdir(path)
	local iterator, state_or_err, errno = fs.scandir(path)
	if iterator == nil then
		local err = type(state_or_err) == 'string' and state_or_err or nil
		return nil, err, errno
	end

	local res, n = {}, 0
	for name, typ in iterator, state_or_err do
		n = n + 1
		res[n] = { name = name, type = typ }
	end

	return res
end

--- Returns the target of a symbolic link.
---
--- Equivalent to [`readlink(2)`](https://man7.org/linux/man-pages/man2/readlink.2.html) in Posix.
--- @param path string
--- @return string|nil target_path
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.readlink(path)
	return luv.fs_readlink(path)
end

--- Returns the canonicalized absolute pathname of `path`. This function has many problems, especially on windows, and
--- should be avoided for most use cases.
---
--- Equivalent to [`realpath(3)`](https://man7.org/linux/man-pages/man3/realpath.3.html) in Posix.
--- @param path string
--- @return string|nil real_path
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.realpath(path)
	return luv.fs_realpath(path)
end

--- Changes the name of a the given file, moving it between directories if necessary.
---
--- Equivalent to [`rename(2)`](https://man7.org/linux/man-pages/man2/rename.2.html) in Posix.
--- @param path string
--- @param new_path string
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.rename(path, new_path)
	return luv.fs_rename(path, new_path)
end

--- Deletes an empty directory.
---
--- Equivalent to [`rmdir(2)`](https://man7.org/linux/man-pages/man2/rmdir.2.html) in Posix.
--- @param path string
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.rmdir(path)
	return luv.fs_rmdir(path)
end

--- Returns a function that can be used to iterate over the entries in a directory.
---
--- Equivalent to [`scandir(3)`](https://man7.org/linux/man-pages/man3/scandir.3.html) in Posix.
--- @param path string
--- @return (fun(): string|nil, string)|nil iterator
--- @return uv.uv_fs_t|string|nil state
--- @return string|nil errno
--- @nodiscard
function fs.scandir(path)
	local req, err, errno = luv.fs_scandir(path)
	if not req then
		return nil, err, errno
	end

	return luv.fs_scandir_next, req
end

--- Returns information about the file at `path`.
---
--- Equivalent to [`stat(2)`](https://man7.org/linux/man-pages/man2/stat.2.html) in Posix.
--- @param path string
--- @return uv.fs_stat.result|nil info
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.stat(path)
	return luv.fs_stat(path)
end

--- Creates a symbolic link from `path` to `new_path`.
---
--- On windows `flags` can be provided, it is a table with the following fields:
---
--- * `dir`: If true, indicates that `path` points to a directory.
--- * `junction`: If true, requests that the symlink is created using junction points.
---
--- Equivalent to [`symlink(2)`](https://man7.org/linux/man-pages/man2/symlink.2.html) in Posix.
--- @param path string
--- @param new_path string
--- @param flags? { dir: boolean, junction: boolean }
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.symlink(path, new_path, flags)
	return luv.fs_symlink(path, new_path, flags)
end

--- Deletes a name from the filesystem. This also deletes the file if it is the last name referring to the file.
---
--- Equivalent to [`unlink(2)`](https://man7.org/linux/man-pages/man2/unlink.2.html) in Posix.
--- @param path string
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.unlink(path)
	return luv.fs_unlink(path)
end

--- Changes the last access and modification times of the file at `path`.
---
--- Equivalent to [`utime(2)`](https://man7.org/linux/man-pages/man2/utime.2.html) in Posix.
--- @param path string
--- @param atime number
--- @param mtime number
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.utime(path, atime, mtime)
	return luv.fs_utime(path, atime, mtime)
end

------------------------------------------------------------------------------------------------------------------------
---                                    Functions that operate on file descriptors                                    ---
------------------------------------------------------------------------------------------------------------------------

--- Opens and possibly creates a file at `path`. The default permissions for a new file are described in `fs.mode_file`.
---
--- The characters in `flags` have the following meanings:
---
--- | Flags | Read | Write | Create | Truncate | Excl | Sync | Cursor |
--- |-------|------|-------|--------|----------|------|------|--------|
--- | `r`   | x    |       |        |          |      |      | Front  |
--- | `r+`  | x    | x     |        |          |	  |      | Front  |
--- | `rs`  | x    |       |        |          |      | x    | Front  |
--- | `rs+` | x    | x     |        |          |      | x    | Front  |
--- | `w`   |      | x     | x      | x        |      |      | Front  |
--- | `w+`  | x    | x     | x      | x        |      |      | Front  |
--- | `wx`  |      | x     | x      | x        | x    |      | Front  |
--- | `wx+` | x    | x     | x      | x        | x    |      | Front  |
--- | `a`   |      | x     | x      |          |      |      | End    |
--- | `a+`  | x    | x     | x      |          |	  |      | End    |
--- | `ax`  |      | x     | x      |          | x    |      | End    |
--- | `ax+` | x    | x     | x      |          | x    |      | End    |
---
--- * Read: The file is opened for reading.
--- * Write: The file is opened for writing.
--- * Create: The file is created if it does not exist.
--- * Truncate: The file is truncated to zero length if it already exists.
--- * Excl: The operation fails if the file already exists.
--- * Sync: Write operations will operate synchronously, as if `fsync` was called after each write.
--- * Cursor: Whether the stream cursor is at the front or end of the file.
---
--- If `mode` is a string, it is interpreted as octal digits.
---
--- Equivalent to [`open(2)`](https://man7.org/linux/man-pages/man2/open.2.html) in Posix.
--- @param path string
--- @param flags "r"|"r+"|"rs"|"rs+"|"w"|"w+"|"wx"|"wx+"|"a"|"a+"|"ax"|"ax+"|integer
--- @param mode? integer|string
--- @return fd_t|nil file_descriptor
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.open(path, flags, mode)
	---@diagnostic disable-next-line: return-type-mismatch
	return luv.fs_open(path, flags, normalize_mode(mode, fs.mode_file))
end

--- Closes a file descriptor.
---
--- Equivalent to [`close(2)`](https://man7.org/linux/man-pages/man2/close.2.html) in Posix.
--- @param fd fd_t
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.close(fd)
	return luv.fs_close(fd)
end

--- Changes the permissions of the file descriptor.
---
--- If `mode` is a string, it is interpreted as octal digits.
---
--- Equivalent to [`fchmod(2)`](https://man7.org/linux/man-pages/man2/fchmod.2.html) in Posix.
--- @param fd fd_t
--- @param mode integer|string
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.fchmod(fd, mode)
	---@diagnostic disable-next-line: return-type-mismatch
	return luv.fs_fchmod(fd, normalize_mode(mode))
end

--- Changes the ownership of the file descriptor.
---
--- Equivalent to [`fchown(2)`](https://man7.org/linux/man-pages/man2/fchown.2.html) in Posix.
--- @param fd fd_t
--- @param uid integer
--- @param gid integer
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.fchown(fd, uid, gid)
	return luv.fs_fchown(fd, uid, gid)
end

--- Flushes all modified data to disk, any only enough metadata to allow the operating system to access the file.
---
--- Equivalent to [`fdatasync(2)`](https://man7.org/linux/man-pages/man2/fdatasync.2.html) in Posix.
--- @param fd fd_t
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.fdatasync(fd)
	return luv.fs_fdatasync(fd)
end

--- Returns information about the file descriptor.
---
--- Equivalent to [`fstat(2)`](https://man7.org/linux/man-pages/man2/fstat.2.html) in Posix.
--- @param fd fd_t
--- @return uv.fs_stat.result|nil info
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.fstat(fd)
	return luv.fs_fstat(fd)
end

--- Flushes all modified data to disk, including metadata.
---
--- Equivalent to [`fsync(2)`](https://man7.org/linux/man-pages/man2/fsync.2.html) in Posix.
--- @param fd fd_t
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.fsync(fd)
	return luv.fs_fsync(fd)
end

--- Truncates, or extends, a file to a specified length.
---
--- Equivalent to [`ftruncate(2)`](https://man7.org/linux/man-pages/man2/ftruncate.2.html) in Posix.
--- @param fd fd_t
--- @param offset integer
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.ftruncate(fd, offset)
	return luv.fs_ftruncate(fd, offset)
end

--- Updates the access and modification times of a file descriptor.
---
--- Equivalent to [`futime(2)`](https://man7.org/linux/man-pages/man2/futime.2.html) in Posix.
--- @param fd fd_t
--- @param atime number
--- @param mtime number
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.futime(fd, atime, mtime)
	return luv.fs_futime(fd, atime, mtime)
end

--- Reads data from a file descriptor at the specified offset. It is not an error to return less than `size` bytes.
---
--- Equivalent to [`pread(2)`](https://man7.org/linux/man-pages/man2/pread.2.html) in Posix.
---
--- Size defaults to 4096.
--- @param fd fd_t
--- @param size? integer
--- @param offset? integer
--- @return string|nil data
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.read(fd, size, offset)
	if size == nil then
		size = 4096
	end

	return luv.fs_read(fd, size, offset)
end

--- Transfers data from one file descriptor to another. It is not an error if not all data is transferred.
---
--- Equivalent to [`sendfile(2)`](https://man7.org/linux/man-pages/man2/sendfile.2.html) in Posix.
--- @param out_fd fd_t
--- @param in_fd fd_t
--- @param in_offset integer
--- @param length integer
--- @return integer|nil bytes_written
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.sendfile(out_fd, in_fd, in_offset, length)
	return luv.fs_sendfile(out_fd, in_fd, in_offset, length)
end

--- Writes data to a file descriptor at the specified offset. It is not an error if not all data is written.
---
--- Equivalent to [`pwrite(2)`](https://man7.org/linux/man-pages/man2/pwrite.2.html) in Posix.
--- @param fd fd_t
--- @param data string
--- @param offset? integer
--- @return integer|nil bytes_written
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.write(fd, data, offset)
	return luv.fs_write(fd, data, offset)
end

--- Functions to provide easier API

--- Returns whether a file or directory exists at `path`. The user may not be able to access it.
--- @param path string
--- @return boolean exists
--- @nodiscard
function fs.exists(path)
	return fs.stat(path) ~= nil
end

--- Reads an entire file and returns its contents.
--- @param path string
--- @param size? integer
--- @param offset? integer
--- @return string|nil data
--- @return string|nil error
--- @return string|nil errno
--- @nodiscard
function fs.readFile(path, size, offset)
	local fd, err, errno = fs.open(path, 'r')
	if fd == nil then
		return nil, err, errno
	end

	if size == nil then
		local stat = fs.fstat(fd)
		size = stat and stat.size or 0
	end

	if offset == nil then
		offset = 0
	end

	local remaining = size

	local buf, n = {}, 0
	while true do
		local chunk_size = max(8192, remaining)

		local chunk
		chunk, err, errno = fs.read(fd, chunk_size, offset)
		if chunk == nil then
			fs.close(fd)
			return nil, err, errno
		end

		if #chunk == 0 then
			break
		end

		n = n + 1
		buf[n] = chunk

		if offset ~= -1 then
			offset = offset + #chunk
		end

		remaining = max(remaining - #chunk, 0)
	end

	fs.close(fd)
	return concat(buf)
end

--- Writes all of `data` to `path`.
---
--- If offset is provided, the file is not truncated and the data is written at the offset.
--- @async
--- @param path string
--- @param data string
--- @param offset? integer
--- @return boolean|nil success
--- @return string|nil error
--- @return string|nil errno
function fs.writeFile(path, data, offset)
	local flag = O_WRONLY + O_CREAT
	if offset == nil then
		offset = 0
		flag = flag + O_TRUNC
	end

	local fd, err, errno = fs.open(path, flag, '644')
	if fd == nil then
		return nil, err, errno
	end

	local index = 1
	local data_len = #data
	while index <= data_len do
		local written
		written, err, errno = fs.write(fd, data:sub(index), offset)
		if written == nil then
			fs.close(fd)
			return nil, err, errno
		end
		if written <= 0 then
			fs.close(fd)
			return nil, 'write returned zero bytes', 'EIO'
		end

		index = index + written
		if offset ~= -1 then
			offset = offset + written
		end
	end

	fs.close(fd)
	return true
end

return fs
