local class = require('class')
local luv = require('luv')

local utility = require('utility')

--- @class std.timer
--- @field private handle uv.uv_timer_t
---
--- A simple timer utility for scheduling functions to be called after a delay or periodically.
local timer = class('std.timer')

--- Start or restart the timer. If the timer is already running, it is stopped and restarted with the new parameters.
---
--- @param delay number The initial delay in milliseconds before the timer first triggers.
--- @param interval number The interval in milliseconds for periodic triggering. A value of `0` means never.
--- @param callback fun(...: any) The function to call when the timer triggers.
--- @param ... any Additional arguments to pass to the callback function.
function timer:start(delay, interval, callback, ...)
	if not self.handle then
		self.handle = assert(luv.new_timer())
	end

	local bound = utility.bind(callback, ...)
	return assert(luv.timer_start(self.handle, delay, interval, bound))
end

--- Convenience method to start a one-time timer.
---
--- @param delay number The delay in milliseconds before the timer triggers.
--- @param callback fun(...: any) The function to call when the timer triggers.
--- @param ... any Additional arguments to pass to the callback function.
function timer:delayed(delay, callback, ...)
	return self:start(delay, 0, callback, ...)
end

--- Convenience method to start a periodic timer.
---
--- @param interval number The interval in milliseconds for periodic triggering.
--- @param callback fun(...: any) The function to call when the timer triggers.
--- @param ... any Additional arguments to pass to the callback function.
function timer:periodic(interval, callback, ...)
	return self:start(interval, interval, callback, ...)
end

--- Stop the timer if it is running. This function is idempotent.
function timer:stop()
	if self.handle then
		return assert(luv.timer_stop(self.handle))
	end
end

--- Restart the timer with the repeat interval as the initial delay. This is useful for periodic timers to reset the
--- timer without changing the interval.
function timer:again()
	if self.handle then
		return assert(luv.timer_again(self.handle))
	end
end

--- Close the timer and release its resources. The timer cannot be used after being closed.
function timer:close()
	if self.handle then
		local handle = self.handle
		self.handle = nil

		return luv.close(handle)
	end
end

--- Pause the current coroutine for at least `milliseconds` milliseconds.
---
--- @param milliseconds number
function timer.sleep(milliseconds)
	local co, main = coroutine.running()
	assert(not main, 'timer.sleep cannot be called from the main thread')

	local obj = timer()
	obj:delayed(milliseconds, function()
		obj:close()
		return coroutine.assertresume(co)
	end)

	return coroutine.yield()
end

--- Call `callback` after at least `delay` milliseconds.
---
--- @param delay number
--- @param callback fun(...: any)
--- @param ... any Arguments to pass to `callback`
--- @return std.timer
function timer.delay(delay, callback, ...)
	local obj = timer()
	obj:delayed(delay, callback, ...)
	return obj
end

--- Call `callback` every at least `delay` milliseconds.
--- @param delay number
--- @param callback fun(...: any)
--- @param ... any Arguments to pass to `callback`
--- @return std.timer
function timer.periodically(delay, callback, ...)
	local obj = timer()
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

--- Call `callback` on the next event loop tick.
--- @param callback fun(...: any)
--- @param ... any Arguments to pass to `callback`
function timer.immediately(callback, ...)
	if #immediate_queue == 0 then
		assert(luv.idle_start(immediate_idle, onImmediate))
	end

	immediate_queue[#immediate_queue + 1] = utility.bind(callback, ...)
end

return timer
