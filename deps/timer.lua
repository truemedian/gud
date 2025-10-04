local luv = require("luv")

local class = import("class")
local utility = import("utility")

---@class uv_timer_t : userdata

---@class luvit.Timer
---@field private handle uv_timer_t
---
--- A simple timer utility for scheduling functions to be called after a delay or periodically.
local Timer = class("Timer")

---@protected
function Timer:init() end

--- Start or restart the timer. If the timer is already running, it will be stopped and restarted with the new parameters.
---
---@param delay number # The initial delay in milliseconds before the timer first triggers.
---@param interval number # The interval in milliseconds for periodic triggering. If `0`, the timer will only trigger once.
---@param callback fun(...: any) # The function to call when the timer triggers.
---@param ... any # Additional arguments to pass to the callback function.
function Timer:start(delay, interval, callback, ...)
	if not self.handle then
		---@diagnostic disable-next-line: assign-type-mismatch
		self.handle = assert(luv.new_timer())
	end

	local count = select("#", ...)
	if count == 0 then
		assert(luv.timer_start(self.handle, delay, interval, callback))
	else
		local args = { ... }
		assert(luv.timer_start(self.handle, delay, interval, function()
			return callback(unpack(args, 1, count))
		end))
	end
end

--- Convenience method to start a one-time timer.
---
---@param delay number # The delay in milliseconds before the timer triggers.
---@param callback fun(...: any) # The function to call when the timer triggers.
---@param ... any # Additional arguments to pass to the callback function.
function Timer:delayed(delay, callback, ...)
	self:start(delay, 0, callback, ...)
end

--- Convenience method to start a periodic timer.
---
---@param interval number # The interval in milliseconds for periodic triggering.
---@param callback fun(...: any) # The function to call when the timer triggers.
---@param ... any # Additional arguments to pass to the callback function.
function Timer:periodic(interval, callback, ...)
	self:start(interval, interval, callback, ...)
end

--- Stop the timer if it is running. This function is idempotent.
function Timer:stop()
	if self.handle then
		assert(luv.timer_stop(self.handle))
	end
end

--- Close the timer and release its resources. The timer cannot be used after being closed.
function Timer:close()
	if self.handle then
		assert(luv.close(self.handle))
		self.handle = nil
	end
end

---@class luvit.timer
local timer = {}
timer.Timer = Timer

--- Pause the current coroutine for at least `milliseconds` milliseconds.
---
---@param milliseconds number
function timer.sleep(milliseconds)
	local co, main = coroutine.running()
	assert(not main, "timer.sleep cannot be called from the main thread")

	local obj = Timer()
	obj:delayed(milliseconds, function()
		obj:close()
		return utility.assertresume(co)
	end)

	return coroutine.yield()
end

--- Call `callback` after at least `delay` milliseconds.
---
---@param delay number
---@param callback fun(...: any)
---@param ... any Arguments to pass to `callback`
---@return uv_timer_t
function timer.delay(delay, callback, ...)
	local obj = Timer()
	obj:delayed(delay, callback, ...)
	return obj
end

---Call `callback` every at least `delay` milliseconds.
---@param delay number
---@param callback fun(...: any)
---@param ... any Arguments to pass to `callback`
---@return uv_timer_t
function timer.periodically(delay, callback, ...)
	local obj = Timer()
	obj:periodic(delay, callback, ...)
	return obj
end

local immediate_queue = {}
local immediate_idle = luv.new_idle()
local function onImmediate()
	local queue = immediate_queue
	immediate_queue = {}

	for i = 1, #queue do
		queue[i]()
	end

	if #immediate_queue == 0 then
		assert(luv.idle_stop(immediate_idle))
	end
end

---Call `callback` on the next event loop tick.
---@param callback fun(...: any)
---@param ... any Arguments to pass to `callback`
function timer.immediately(callback, ...)
	if #immediate_queue == 0 then
		assert(luv.idle_start(immediate_idle, onImmediate))
	end

	immediate_queue[#immediate_queue + 1] = utility.bind(callback, ...)
end

return timer
