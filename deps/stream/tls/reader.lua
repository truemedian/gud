local class = require('class')
local reader = require('reader')

--- @class std.stream.tls.reader : std.reader
--- @field reader std.reader
--- @field bio openssl.bio
--- @field ssl openssl.ssl
local reader_tls = class('stream.tls.reader', reader)

function reader_tls:init(reader_in, bio, ssl)
	reader.init(self)
	self.reader = reader_in
	self.bio = bio
	self.ssl = ssl
end

function reader_tls:fill(n, timeout)
	while true do
		local plain, ssl_err = self.ssl:read()

		if plain then
			self.buffer:write(plain)
			return #plain
		elseif ssl_err ~= 'want_read' then
			return 0, 'unexpected SSL read error: ' .. ssl_err
		end

		local data, err = self.reader:readAtLeast(1, timeout)
		if not data or err then
			return 0, err
		end

		self.bio:write(data)
	end
end

return reader_tls
