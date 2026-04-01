local class = require('class')
local writer = require('writer')

local timer = require('timer')
local utility = require('utility')

--- @class std.stream.tcp.writer : std.writer
--- @field socket uv_tcp_t
--- @field timeout std.timer
local writer_tcp = class('stream.tcp.writer', writer)

function writer_tcp:init(socket)
	writer.init(self)
	self.socket = socket
	self.timeout = timer()
end

function writer_tcp:flush(timeout)
	local parts = self.buffer:parts()

	local nwritten, tw_err = self.socket:try_write(parts)
	if tw_err then
		return 0, tw_err
	end

	if nwritten > 0 then
		return nwritten
	end

	local thread = coroutine.running()
	local pending = #self.buffer
	local done = false

	local function finish(nwritten, err)
		if done then
			return
		end

		done = true
		self.timeout:stop()
		return utility.assertresume(thread, nwritten, err)
	end

	local req, write_err = self.socket:write(parts, function(err)
		if err then
			self.socket:shutdown()
			return finish(0, err)
		end

		return finish(pending)
	end)

	if not req then
		self.socket:shutdown()
		return 0, write_err
	end

	if timeout then
		self.timeout:delayed(timeout, function()
			self.socket:shutdown()
			return finish(0, 'timeout')
		end)
	end

	return coroutine.yield()
end

return writer_tcp
