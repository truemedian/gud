local class = require('class')
local fs = require('fs')

--- @class std.git.lock : std.class<std.git.lock>
--- @field dest_path string
--- @field lock_path string
--- @field handle integer|nil
local lock = class.new('std.git.lock')

--- @param path string
function lock:init(path)
	self.dest_path = path
	self.lock_path = path .. '.lock'
end

--- Acquire the lock by creating the lock file. This will fail if the lock file already exists.
--- @return boolean success
--- @return string|nil error
function lock:acquire()
	local handle, err = fs.open(self.lock_path, 'wx')
	if not handle then
		return false, err
	end

	self.handle = handle
	return true
end

--- Write data to the lock file. This will fail if the lock was not acquired or if the write operation fails.
--- @param data string
--- @return boolean success
--- @return string|nil error
function lock:write(data)
	if not self.handle then
		return false, 'lock not acquired'
	end

	while true do
		local written, err = fs.write(self.handle, data)
		if not written then
			return false, err
		end

		if written == #data then
			break
		end

		data = data:sub(written + 1)
	end

	return true
end

--- Commit the lock by fsyncing and closing the file handle, then renaming the lock file to the destination path.
---
--- This will fail if the lock was not acquired or if any of the file operations fail.
--- @return boolean success
--- @return string|nil error
function lock:commit()
	if not self.handle then
		return false, 'lock not acquired'
	end

	local success, err = fs.fsync(self.handle)
	if not success then
		return false, err
	end

	success, err = fs.close(self.handle)
	if not success then
		return false, err
	end

	self.handle = nil
	success, err = fs.rename(self.lock_path, self.dest_path)
	if not success then
		return false, err
	end

	return true
end

--- Release the lock by closing the file handle (if it exists) and deleting the lock file.
--- @return boolean success
--- @return string|nil error
function lock:release()
	if not self.handle then
		return false, 'lock not acquired'
	end

	local success, err = fs.close(self.handle)
	if not success then
		return false, err
	end

	self.handle = nil
	success, err = fs.unlink(self.lock_path)
	if not success then
		return false, err
	end

	return true
end

return lock
