
local readable = require("stream/readable.lua")
local writable = require("stream/writable.lua")
local filter = require("stream/filter.lua")

local a = readable.file.open("test.lua", "r")
local b = writable.stream.new(require('pretty-print').stdout)
local c = writable.filter.new(b, filter.deflate())

a:pump(c, true)
