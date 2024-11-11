local object = require('git/object')
local repository = require('git/repository')
local person = require('git/object/person')

return {
    object = object,
    repository = repository,
    person = person,
}