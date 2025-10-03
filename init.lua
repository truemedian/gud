local luv = require("luv")

-- seed the RNG
math.randomseed(os.time())

local target = import("target")
if target.os == "windows" then
	local sig = luv.new_signal()
	luv.signal_start(sig, "sigpipe")
	luv.unref(sig)
end

error("failed")