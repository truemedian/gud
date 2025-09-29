local readable = require("stream-ng/readable.lua")
local writable = require("stream-ng/writable.lua")
local filter = require("stream-ng/filter.lua")

local a = readable.string.new("Hello, World!")
local b = readable.filter.new(a, filter.deflate())

local z = writable.string.new()
local y = writable.filter.new(z, filter.inflate())

while true do
    local chunk, err = b:readAtMost(4)
    if not chunk then break end
    y:write(chunk)
end

y:finish()
p(z:out())