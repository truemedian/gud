--- @class std.http
local http = {}

http.parser = require('http/parser')
http.protocol = require('http/protocol')
http.client = require('http/client')
http.server = require('http/server')

return http
