local class = require('class')

--- @type std.writer
local writer = require('writer')

local timer = require('timer')
local utility = require('utility')

--- @class std.net.tcp.writer : std.writer
--- @field socket uv.uv_tcp_t
--- @field timeout std.timer
--- @field waiting thread|boolean|nil
--- @field _err string|nil
--- @field _onwrite fun(err: string?)
--- @field _ontimeout fun()
local writer_tcp = class('std.net.tcp.writer', writer)

function writer_tcp:init(socket)
	writer.init(self)
	self.socket = socket
	self.timeout = timer()
	self.waiting = nil
	self._err = nil

	function self._onwrite(err)
		self.timeout:stop()

		if self.waiting then
			if err then
				self.socket:shutdown()
				return utility.assertresume(self.waiting, 0, err)
			end

			return utility.assertresume(self.waiting, #self.buffer)
		elseif err then
			self._err = err
			return self.socket:shutdown()
		end

		self.waiting = true
	end

	function self._ontimeout()
		self.socket:shutdown()
		return utility.assertresume(self.waiting, 0, 'timeout')
	end
end

function writer_tcp:flush(timeout)
	local parts = self.buffer:parts()

	local thread = coroutine.running()
	local pending = #self.buffer

	local req, write_err = self.socket:write(parts, self._onwrite)
	if not req then
		self.socket:shutdown()
		return 0, write_err
	end

	if timeout then
		self.timeout:delayed(timeout, self._ontimeout)
	end

	if self.waiting then
		self.waiting = nil

		if self._err then
			local err = self._err
			self._err = nil
			return 0, err
		end

		return pending
	end

	self.waiting = thread
	return coroutine.yield()
end

return writer_tcp
