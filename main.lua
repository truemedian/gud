local luv = require("luv")

-- bootstrap the import system
local module
do
	local luvi = require("luvi")
	luvi.bundle.register("bundle:path", "deps/path.lua")
	luvi.bundle.register("bundle:import", "deps/import.lua")

	local import0 = require("bundle:import")
	module = import0.new("/", true)

	package.loaded["bundle:path"] = nil
	package.loaded["bundle:import"] = nil

	module:import("import", import0)
end

-- seed the RNG
math.randomseed(os.time())

local target = module:import("target")
if target.os == "windows" then
	local sig = luv.new_signal()
	luv.signal_start(sig, "sigpipe")
	luv.unref(sig)
end

-- load pretty print
module:import("pretty")

local utility = module:import("utility")

local success, err = xpcall(function(...)
	local coro = coroutine.create(function(...)
		module:import("init.lua", ...)
	end)

	utility.assertresume(coro, ...)

	luv.run()
end, function(err)
	if getmetatable(err) == utility.exception then
		print(err:traceback())
	else
		print(err)
	end

	luv.run()
end, ...)
