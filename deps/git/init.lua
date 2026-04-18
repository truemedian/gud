local git = {}

git.oid_type = require('git/oid_type')

git.identity = require('git/object/identity')
git.object = require('git/object')
git.tree = require('git/object/tree')
git.commit = require('git/object/commit')
git.tag = require('git/object/tag')

git.database = require('git/database')
git.refs = require('git/refs')
git.repository = require('git/repository')

return git
