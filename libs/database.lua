local git = require('git')
local git_repository = require('git/repository')
local sshkey = require('sshkey')

local http = require('coro-http')

---@class database
---@field repository git.repository
---@field admin_user git.object.person
---@field admin_key sshkey.key
local database = {}
local database_mt = { __index = database }

function database.new(directory)
	local my_repository = git_repository.new(directory)
	my_repository:init()
	my_repository:init_loose()

	return setmetatable({
		repository = my_repository,
		admin_user = git.person.new('admin', 'maintainer@email.email'),
	}, database_mt)
end

function database:keys_is_authorized(username, fingerprint)
	local commit = self.repository:fetch_reference('refs/heads/keys/' .. username)
	if not commit then
		return false
	end

	if commit.kind ~= 'commit' then
		return false
	end

	local tree = commit.commit.tree
	if tree.kind ~= 'tree' then
		return false
	end

	local file = tree:tree_get_file('authorized_keys')
	if not file or file.kind ~= 'blob' then
		return false
	end

	local authorized_keys = file:blob_get()
	for line in authorized_keys:gmatch('[^\r\n]+') do
		local pubkey = sshkey.load_public(line)
		if pubkey then
			if sshkey.fingerprint(pubkey) == fingerprint then
				return true
			end
		end
	end

	return false
end

function database:keys_reauthenticate(username)
	local parent = self.repository:fetch_reference('refs/heads/keys/' .. username)
	local etag

	if parent then
		do
			if parent.kind ~= 'commit' or parent.commit.tree.kind ~= 'tree' then
				goto bad
			end

			local tree = parent.commit.tree
			local auth_blob = tree:tree_get_file('authorized_keys.etag')
			if not auth_blob then
				goto bad
			end

			local etag_blob = tree:tree_get_file('authorized_keys.etag')
			if not etag_blob then
				goto bad
			end

			etag = etag_blob:blob_get()
		end

		::bad::
		parent = nil
	end

	-- local fetch_success, fetch_head, fetch_body = http.request('GET', 'https://github.com/' .. name .. '.keys')
	-- if not fetch_success or fetch_head.status ~= 200 or not fetch_body then
	-- 	return false, 'failed to fetch authorized keys from github.com'
	-- end
	local fetch_head = { status = 304 }
	local fetch_body = require('fs').readFileSync('teststuff/' .. username .. '.keys')

	return false
end

---Try to authenticate a user against their github.com reported authorized keys.
---
---When successful, the user's list of authorized keys is stored in the `keys/{username}` branch.
---@param username string
---@param signature string
function database:reauthenticate(username, signature)
	-- local fetch_success, fetch_head, fetch_body = http.request('GET', 'https://github.com/' .. name .. '.keys')
	-- if not fetch_success or fetch_head.status ~= 200 or not fetch_body then
	-- 	return false, 'failed to fetch authorized keys from github.com'
	-- end
	local fetch_body = require('fs').readFileSync('teststuff/' .. username .. '.keys')

	local parent_commit = self.repository:fetch_reference('refs/heads/keys/' .. username)
	if parent_commit then
		local current_authorized_keys = parent_commit.commit.tree:tree_get_file('authorized_keys')
		if current_authorized_keys and current_authorized_keys:blob_get() == fetch_body then
			return false, 'authorized keys are already up to date'
		end
	end

	local verified = nil
	for line in fetch_body:gmatch('[^\r\n]+') do
		local pubkey = sshkey.load_public(line)
		if pubkey then
			if sshkey.verify(pubkey, signature, username, 'lit-authenticate') then
				verified = pubkey
				break
			end
		end
	end

	if not verified then
		return false, 'failed to verify signature with any authorized keys'
	end

	local blob = git.object.new_blob(fetch_body)

	local tree = git.object.new_tree()
	tree:tree_add_file('authorized_keys', blob)

	self.admin_user.time = os.time()
	local commit = git.object.new_commit(
		tree,
		self.admin_user,
		self.admin_user,
		'reauthenticate ' .. username .. ' with ' .. sshkey.fingerprint(verified)
	)

	if parent_commit then
		commit:commit_add_parent(parent_commit)
	end

	local success, err = commit:commit_sign(self.repository, self.admin_key, 'keys/*')
	if not success then
		return false, err
	end

	success, err = self.repository:store_all(blob, tree, commit)
	if not success then
		return false, err
	end

	success, err = self.repository:update_reference('refs/heads/keys/' .. username, commit)
	if not success then
		return false, err
	end

	return true
end

return database
