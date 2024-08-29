--[[ Wraps a coro-fs-like `fs` provider into the necessary functions used in this library.

storage:write(path, data, exclusive)  Write `data` to the given `path`, optionally ensuring the
                                      file does not already exist.
storage:read(path)                    Read the contents of the file at the given `path` or `nil` if
                                      the file does not exist.
storage:delete(path)                  Delete the file at the given `path` and clean up any empty
                                      parent directories. The file must exist.
storage:nodes(path)                   Returns an iterator over the directories in the given `path`.
storage:leaves(path)                  Returns an iterator over the files in the given `path`.


The `fs` provider must implement the following functions:


success = fs.access(path)                  Check if the file at the given `path` exists.
success, err = fs.mkdirp(path)             Create the directory at the given `path`, including any
                                           necessary parent directories.
fd, err = fs.open(path, flags, mode)       Open the file at the given `path` with the given `flags` and `mode`.
success, err = fs.write(fd, data, offset)  Write `data` to the file descriptor `fd` at the given `offset`.
data, err = fs.read(fd, size, offset)      Read `size` bytes from the file descriptor `fd` at the given `offset`.
success, err = fs.close(fd)                Close the file descriptor `fd`.
success, err = fs.unlink(path)             Delete the file at the given `path`.
iter, dir = fs.scandir(path)               Returns an iterator over the entries in the given `path`.

fs.read and fs.write may support partial reads and writes.

]] --
local function dirname(path) return path:match('^(.*)[/\\][^/\\]*$') end
local function basename(path) return path:match('.+[/\\]([^/\\]*)$') or path end

local fs = require('fs')
local posix_path = require('path/base').posix

---@class git.storage
---@field chroot string
local storage = {}

local function normalize(path) return posix_path:normalize(path) end

local function resolve(chroot, path)
    assert(path:sub(1, 3) ~= '../', 'path attempted to escape chroot: ' .. path)
    return chroot .. '/' .. path
end

function storage:access(path)
    path = normalize(path)
    local real_path = resolve(self.chroot, path)

    return fs.accessSync(real_path)
end

function storage:mkdirp(path)
    path = normalize(path)
    local real_path = resolve(self.chroot, path)

    local success, errmsg, errno = fs.mkdirSync(real_path, 493) -- 755
    if success or errno == 'EEXIST' then return true end
    if errno == 'ENOENT' then
        success, errmsg, errno = self:mkdirp(dirname(path))
        if not success then return false, errmsg, errno end

        success, errmsg, errno = fs.mkdirSync(real_path, 493) -- 755
        if errno == 'EEXIST' then return true end -- always a filesystem race
    end

    return success, errmsg, errno
end

--- Performs an atomic write of `data` to the given `path`. If `exclusive` is true and the file already exists, an error is thrown.
--- @param path string
--- @param data string
--- @param exclusive? boolean
function storage:write(path, data, exclusive)
    path = normalize(path)
    local real_path = resolve(self.chroot, path)

    -- check early to ensure we don't do extra work
    if exclusive and fs.accessSync(real_path) then error('EEXIST: file already exists: ' .. real_path) end

    local temp_path = os.tmpname() .. '-' .. basename(path)
    local fd, errmsg, errno = fs.openSync(temp_path, 'wx', 420) -- 644
    if not fd and errno == 'ENOENT' then
        local success
        success, errmsg = self:mkdirp(dirname(path))
        if not success then return false, errmsg end

        fd, errmsg, errno = fs.openSync(temp_path, 'wx', 420) -- 644
    end
    assert(fd, errmsg)

    local offset = 0
    while offset < #data do
        local chunk, nwritten = data:sub(offset + 1)
        nwritten, errno = fs.writeSync(fd, chunk, offset)
        if not nwritten then
            fs.unlinkSync(temp_path) -- cleanup the temp file
            fs.closeSync(fd) -- ensure the file is always closed
            error(errno)
        end
        offset = offset + nwritten
    end
    fs.closeSync(fd) -- close the file now that we're done writing

    -- check again to ensure nobody wrote the file in the meantime
    if exclusive and fs.accessSync(real_path) then
        fs.unlinkSync(temp_path) -- cleanup the temp file
        error('EEXIST: file already exists: ' .. real_path)
    end

    -- rename the file to the final path
    assert(fs.renameSync(temp_path, real_path))
end

--- Reads the contents of the file at the given `path`. If the file does not
--- exist, returns `nil`.
--- @param path string  
--- @return string|nil
function storage:read(path)
    path = normalize(path)
    local real_path = resolve(self.chroot, path)

    local fd, errmsg, errno = fs.openSync(real_path, "r", 0)
    if not fd then
        if errno == 'ENOENT' then return nil end
        error(errmsg)
    end

    local stat
    stat, errmsg, errno = fs.fstatSync(fd)
    if not stat then
        fs.closeSync(fd)
        error(errmsg)
    end

    local data = {}

    local size = stat.size
    local offset = 0
    while true do
        local chunk
        chunk, errmsg, errno = fs.readSync(fd, size <= 0 and 8192 or size, offset)
        if not chunk then
            fs.closeSync(fd)
            error(errmsg)
        end

        if chunk == '' then break end
        if size > 0 then size = size - #chunk end

        table.insert(data, chunk)
        offset = offset + #chunk
    end

    fs.closeSync(fd)
    return table.concat(data)
end

--- Deletes the file at the given `path` and cleans up any empty parent directories.
--- @param path string
function storage:delete(path)
    path = normalize(path)
    local real_path = resolve(self.chroot, path)

    assert(fs.unlinkSync(real_path))
    local parent = dirname(path)

    -- remove parent directories if they are empty
    local success = true ---@type boolean|nil
    while success and parent do
        real_path = self.chroot .. '/' .. parent

        success = fs.rmdirSync(real_path)
        parent = dirname(parent)
    end
end

function storage:nodes(path)
    path = normalize(path)
    local real_path = resolve(self.chroot, path)

    local function iterate()
        for name, kind in fs.scandirSync(real_path) do
            if kind == 'directory' then -- only yield directories
                coroutine.yield(name)
            end
        end
    end

    return coroutine.wrap(iterate)
end

function storage:leaves(path)
    path = normalize(path)
    local real_path = resolve(self.chroot, path)

    local function iterate()
        for name, kind in fs.scandirSync(real_path) do
            if kind == 'file' then -- only yield files
                coroutine.yield(name)
            end
        end
    end

    return coroutine.wrap(iterate)
end

function storage:scandir(path)
    path = normalize(path)
    local real_path = resolve(self.chroot, path)

    return fs.scandirSync(real_path)
end

return function(chroot)
    return setmetatable({chroot = assert(chroot)}, {__index = storage}) -- create wrapped storage
end
