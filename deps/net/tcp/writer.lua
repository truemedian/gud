local class = require('class')

--- @type std.writer
local writer = require('writer')

local timer = require('timer')

--- @class std.net.tcp.writer : std.class<std.net.tcp.writer>, std.writer
--- @field socket uv.uv_tcp_t
--- @field timeout std.timer
--- @field waiting thread|nil
--- @field early boolean
--- @field _err string|nil
--- @field _onwrite fun(err: string?)
--- @field _ontimeout fun()
local writer_tcp = class.new('std.net.tcp.writer', writer)

function writer_tcp:init(socket)
	writer.init(self)
	self.socket = socket
	self.timeout = timer.new()
	self.waiting = nil
	self.early = false
	self._err = nil

	function self._onwrite(err)
		self.timeout:stop()

		if self.waiting then
			if err then
				self.socket:shutdown()
				return coroutine.assertresume(self.waiting, 0, err)
			end

			return coroutine.assertresume(self.waiting, #self.buffer)
		elseif err then
			self._err = err
			return self.socket:shutdown()
		end

		self.early = true
	end

	function self._ontimeout()
		self.socket:shutdown()
		return coroutine.assertresume(self.waiting, 0, 'timeout')
	end
end

function writer_tcp:flush(timeout)
	local parts = self.buffer:parts()

	local thread = coroutine.running()
	local pending = #self.buffer

	self.early = false
	local req, write_err = self.socket:write(parts, self._onwrite)
	if not req then
		self.socket:shutdown()
		return 0, write_err
	end

	if self.early then
		if self._err then
			local err = self._err
			self._err = nil
			return 0, err
		end

		return pending
	end

	if timeout then
		self.timeout:delayed(timeout, self._ontimeout)
	end

	self.waiting = thread
	return coroutine.yield()
end

return writer_tcp
