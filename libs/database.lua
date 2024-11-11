local git = require('git')
local git_repository = require('git/repository')
local sshkey = require('sshkey')

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

function database:add_signing_key(name, pubkey)
	local fingerprint = sshkey.fingerprint(pubkey)
	local serialized_key = sshkey.save_public(pubkey)

	local blob, tree, commit

	local parent_commit = self.repository:fetch_reference('refs/heads/keys/' .. name)
	if parent_commit then
		local parent_tree = parent_commit.commit.tree
		local authorized_keys = parent_tree.tree:get_file('authorized_keys')

		blob = git.object.new_blob(authorized_keys.object.blob .. '\n' .. serialized_key)

		tree = git.object.new_tree()
		tree.tree:add_file('authorized_keys', blob)

		self.admin_user.time = os.time()
		commit = git.object.new_commit(tree, self.admin_user, self.admin_user, 'add key ' .. fingerprint)
		table.insert(commit.commit.parents, parent_commit)
	else
		blob = git.object.new_blob(serialized_key)

		tree = git.object.new_tree()
		tree.tree:add_file('authorized_keys', blob)

		self.admin_user.time = os.time()
		commit = git.object.new_commit(tree, self.admin_user, self.admin_user, 'add key ' .. fingerprint)
	end

	local success, err = commit.commit:sign(self.repository, self.admin_key, 'keys/*')
	if not success then
		return false, err
	end

	local success, err = self.repository:store(blob)
	if not success then
		return false, err
	end

	local success, err = self.repository:store(tree)
	if not success then
		return false, err
	end

	local success, err = self.repository:store(commit)
	if not success then
		return false, err
	end

	local oid, err = self.repository:update_reference('refs/heads/keys/' .. name, commit)
	if not oid then
		return false, err
	end

	return true
end

return database