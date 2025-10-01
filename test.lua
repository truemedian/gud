
local readable = require("stream/readable.lua")
local writable = require("stream/writable.lua")
local filter = require("stream/filter.lua")

local a = readable.string.new("Hello, World!\r\na")

p(a:readUntil(","))
p(a:readLine(14))
p(a:readUInt8())
p(a:readUInt8())


-- local b = readable.filter.new(a, filter.deflate())

-- local z = writable.string.new()
-- local y = writable.filter.new(z, filter.inflate())

-- while true do
--     local chunk, err = b:readAtMost(4)
--     if not chunk then break end
--     y:write(chunk)
-- end

-- y:finish()
-- p(z:out())