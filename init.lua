local repository = require('git/repository')
local sshkey = require('sshkey')

local database = require('database')

local admin_key = sshkey.load_private(require('fs').readFileSync('/home/nameless/.ssh/id_ed25519'))
local db = database.new('test.git')
db.admin_key = admin_key

local key = sshkey.load_public(require('fs').readFileSync('/home/nameless/.ssh/id_ed25519.pub'))

db:add_signing_key('nameless', key)