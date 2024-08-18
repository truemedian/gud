local repository = require('repository')
local storage = require('storage')

local fs = require('coro-fs').chroot('/code/repositories/github/truemedian/hzzp/.git')
local this_storage = storage(fs)
local repo = repository(this_storage)

p(repo:getReference('0.1.0'))