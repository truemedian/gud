local class = require('class')

local utility = require('utility')

--- @class std.await
local await = class('std.await')

function await:wait()
	assert(self.waiter == nil, 'already waiting')

	self.waiter = coroutine.running()
	return coroutine.yield()
end

function await:signal(...)
	assert(self.waiter ~= nil, 'not waiting')

	local waiter = self.waiter
	self.waiter = nil

	return utility.assertresume(waiter, ...)
end

function await:callback()
	return function(...)
		return self:signal(...)
	end
end

return await
