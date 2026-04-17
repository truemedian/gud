local class = require('class')

--- @type std.reader
local reader = require('reader')
local timer = require('timer')

--- @class std.net.tcp.reader : std.reader
--- @field socket uv.uv_tcp_t
--- @field timeout std.timer
--- @field waiting thread
--- @field _onread fun(err: string?, chunk: string?)
--- @field _ontimeout fun()
local reader_tcp = class('std.net.tcp.reader', reader)

function reader_tcp:init(socket)
	reader.init(self)
	self.socket = socket
	self.timeout = timer()
	self.waiting = nil

	local function finish(n, err)
		if self.waiting then
			self.timeout:stop()

			local waiting = self.waiting
			self.waiting = nil
			return coroutine.assertresume(waiting, n, err)
		end

		if err then
			self.closed = true
		elseif #self.buffer > 8192 then
			-- wait for the buffer to be consumed before reading more data
			return self.socket:read_stop()
		end
	end

	function self._onread(err, chunk)
		if err then
			self.socket:close()
			return finish(0, err)
		elseif not chunk then
			return finish(0)
		end

		self.buffer:write(chunk)
		return finish(#chunk)
	end

	function self._ontimeout()
		self.socket:read_stop()
		self.socket:close()

		local waiting = assert(self.waiting)
		self.waiting = nil
		return coroutine.assertresume(waiting, 0, 'timeout')
	end
end

function reader_tcp:fill(_, timeout)
	local thread = coroutine.running()

	if timeout then
		self.timeout:delayed(timeout, self._ontimeout)
	end

	if self.waiting then
		return 0, 'already waiting'
	end

	self.waiting = thread
	self.socket:read_start(self._onread)

	return coroutine.yield()
end

return reader_tcp
