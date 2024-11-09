local fs = require('fs')

local common = require('git/common')

---@class git.refdb.files
---@field repository_dir string
local refdb_files = {}
local refdb_files_mt = { __index = refdb_files }

---@param repository_dir string
function refdb_files.load(repository_dir)
	return setmetatable({
		repository_dir = assert(repository_dir, 'missing repository directory'),
	}, refdb_files_mt)
end

--- Reads an prefixed reference. Must begin with `refs/`.
---@param ref string
function refdb_files:read(ref)
	assert(ref:sub(1, 5) == 'refs/', 'reference must start with refs/')
	assert(ref:find('../', 1, true) == nil, 'reference cannot contain extraneous path components')

	local ref_file = common.read_file(self.repository_dir .. '/' .. ref)
	if ref_file then
		if ref_file:sub(1, 4) == 'ref:' then
			local actual = ref_file:match('^ref:%s*(%S+)%s*$')
			return self:read(actual)
		else
			return ref_file:match('^([0-9a-f]+)%s*$')
		end
	end

	local packed_refs = common.read_file(self.repository_dir .. '/packed-refs')
	if packed_refs then
		local ref_line = packed_refs:match('([0-9a-f]+)%s+' .. ref .. '\n')
		if ref_line then
			return ref_line
		end
	end
end

--- Reads an unprefixed reference. May be either a tag or a branch head.
---@param ref string
function refdb_files:read_any(ref)
	assert(ref:find('../', 1, true) == nil, 'reference cannot contain extraneous path components')

	return self:read('refs/heads/' .. ref) or self:read('refs/tags/' .. ref)
end

local function iterate_refs(self, prefix)
	local function iterate_packed()
		local packed_refs = common.read_file(self.repository_dir .. '/packed-refs')
		if packed_refs then
			local packed_pattern = '(%x+) ' .. prefix .. '(%S+)\n'
			local pos = 1
			while true do
				local start, stop, hash, name = packed_refs:find(packed_pattern, pos)
				if not start then
					break
				end

				coroutine.yield(name, hash)
				pos = stop + 1
			end
		end
	end

	local function iterate_dir(parts, i)
		local path = table.concat(parts)

		if fs.accessSync(path) then
			for name, kind in fs.scandirSync(path) do
				if kind == 'file' then
					parts[i] = name

					local ref_name = table.concat(parts, '/', 2, i)
					coroutine.yield(ref_name, self:read(prefix .. ref_name))
				elseif kind == 'directory' then
					parts[i] = name
					iterate_dir(parts, i + 1)
				end
			end
		end
	end

	local function iterate()
		iterate_dir({ self.repository_dir, prefix }, 3)
		iterate_packed()
	end

	return coroutine.wrap(iterate)
end

function refdb_files:tags()
	return iterate_refs(self, 'refs/tags/')
end

function refdb_files:branches()
	return iterate_refs(self, 'refs/heads/')
end

function refdb_files:remotes()
	return iterate_refs(self, 'refs/remotes/')
end

return refdb_files
