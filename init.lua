local repository = require('git/repository')
local sshkey = require('sshkey')

local database = require('database')

local admin_key = sshkey.load_private(require('fs').readFileSync('teststuff/admin_ed25519'))
local db = database.new('test.git')
db.admin_key = admin_key

local key = sshkey.load_public(require('fs').readFileSync('teststuff/admin_ed25519.pub'))
local sig = sshkey.sign(admin_key, 'truemedian', 'lit-authenticate')

db:reauthenticate('truemedian', sig)