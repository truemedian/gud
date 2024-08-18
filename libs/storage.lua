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

---@class git.storage.fs
---@field access fun(path: string): boolean|nil, string|nil
---@field mkdirp fun(path: string): boolean|nil, string|nil
---@field open fun(path: string, flags: string, mode: number): number|nil, string|nil
---@field write fun(fd: number, data: string, offset: number): number|nil, string|nil
---@field read fun(fd: number, size: number, offset: number): string|nil, string|nil
---@field close fun(fd: number): boolean|nil, string|nil
---@field unlink fun(path: string): boolean|nil, string|nil
---@field rename fun(oldpath: string, newpath: string): boolean|nil, string|nil
---@field scandir fun(path: string): nil|fun(): nil|{name: string, type: string}
---@field fstat fun(fd: number): table|nil, string|nil
---@field rmdir fun(path: string): boolean|nil, string|nil
local _fs = {}

---@class git.storage
---@field fs git.storage.fs
local storage = {}

--- Performs an atomic write of `data` to the given `path`. If `exclusive` is true and the file already exists, an error is thrown.
--- @param path string
--- @param data string
--- @param exclusive? boolean
function storage:write(path, data, exclusive)
    -- check early to ensure we don't do extra work
    if exclusive and self.fs.access(path) then error('EEXIST: file already exists: ' .. path) end

    local parent = dirname(path)
    if parent then
        assert(self.fs.mkdirp(parent)) -- ensure the parent exists
    end

    local temp_path = os.tmpname() .. '-' .. basename(path)

    -- create file with 644 permissions (TODO: executable bit)
    local fd = assert(self.fs.open(temp_path, "wx", 420))
    local offset = 0

    while offset < #data do
        local chunk = data:sub(offset + 1)
        local nwritten, err = self.fs.write(fd, chunk, offset)
        if not nwritten then
            self.fs.close(fd) -- ensure the file is always closed
            error(err)
        end
        offset = offset + nwritten
    end
    self.fs.close(fd) -- close the file now that we're done writing

    -- check again to ensure nobody wrote the file in the meantime
    if exclusive and self.fs.access(path) then
        self.fs.unlink(temp_path) -- cleanup the temp file
        error('EEXIST: file already exists: ' .. path)
    end

    -- rename the file to the final path
    assert(self.fs.rename(temp_path, path))
end

--- Reads the contents of the file at the given `path`. If the file does not
--- exist, returns `nil`.
--- @param path string  
--- @return string|nil
function storage:read(path)
    local fd, err = self.fs.open(path, "r", 0)
    if not fd then
        if err and err:sub(1, #'ENOENT:') == 'ENOENT:' then return nil end
        error(err)
    end

    local stat = assert(self.fs.fstat(fd))
    local data = {}

    local size = stat.size
    local offset = 0
    while true do
        local chunk, read_err = self.fs.read(fd, size <= 0 and 8192 or size, offset)
        if not chunk then
            self.fs.close(fd)
            error(read_err)
        end

        if chunk == '' then break end
        if size <= 0 then size = size - #chunk end

        table.insert(data, chunk)
        offset = offset + #chunk
    end

    self.fs.close(fd)
    return table.concat(data)
end

--- Deletes the file at the given `path` and cleans up any empty parent directories.
--- @param path string
function storage:delete(path)
    assert(self.fs.unlink(path))
    local parent = dirname(path)

    -- remove parent directories if they are empty
    local success = true ---@type boolean|nil
    while success do
        success = self.fs.rmdir(parent)
        parent = dirname(parent)
    end
end

local function scandir_filter(self, path, filter)
    local iter = self.fs.scandir(path)
    if not iter then return function() end end

    return function()
        while true do
            local item = iter()
            if not item then return end
            if item.type == filter then return item.name end
        end
    end
end

function storage:nodes(path) return scandir_filter(self, path, 'directory') end

function storage:leaves(path) return scandir_filter(self, path, 'file') end

return function(fs)
    return setmetatable({fs = assert(fs)}, {__index = storage}) -- create wrapped storage
end
