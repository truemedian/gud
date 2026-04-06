local class = require('class')

--- @type std.reader
local reader = require('reader')

local timer = require('timer')
local utility = require('utility')

--- @class std.net.tcp.reader : std.reader
--- @field socket uv_tcp_t
--- @field timeout std.timer
local reader_tcp = class('std.net.tcp.reader', reader)

function reader_tcp:init(socket)
	reader.init(self)
	self.socket = socket
	self.timeout = timer()
end

function reader_tcp:fill(_, timeout)
	local thread = coroutine.running()
	local done = false

	local function finish(nread, err)
		if done then
			return
		end

		done = true
		self.timeout:stop()
		self.socket:read_stop()
		return utility.assertresume(thread, nread, err)
	end

	self.socket:read_start(function(err, chunk)
		if err then
			self.socket:close()
			return finish(0, err)
		elseif not chunk then
			return finish(0)
		end

		self.buffer:write(chunk)
		return finish(#chunk)
	end)

	if timeout then
		self.timeout:delayed(timeout, function()
			self.socket:close()
			return finish(0, 'timeout')
		end)
	end

	return coroutine.yield()
end

return reader_tcp
