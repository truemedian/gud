local class = require('class')

--- @type std.writer
local writer = require('writer')

--- @class std.net.tls.writer : std.writer
--- @field writer std.writer
--- @field bio openssl.bio
--- @field ssl openssl.ssl
local writer_tls = class('std.net.tls.writer', writer)

function writer_tls:init(writer_out, bio, ssl)
	writer.init(self)
	self.writer = writer_out
	self.bio = bio
	self.ssl = ssl
end

function writer_tls:flush(timeout)
	local plain = self.buffer:chunk()
	if plain then
		self.ssl:write(plain)
	end

	while self.bio:pending() > 0 do
		local chunk = self.bio:read()

		local success, err = self.writer:write(chunk, timeout)
		if not success then
			return 0, err
		end
	end

	return plain and #plain or 0
end

--- @param timeout? integer
function writer_tls:flushAll(timeout)
	local success, err = writer.flushAll(self, timeout)
	if not success then
		return false, err
	end

	success, err = self.writer:flushAll(timeout)
	return success, err
end

return writer_tls
