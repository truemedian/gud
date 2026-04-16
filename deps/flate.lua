local miniz = require('miniz')

local class = require('class')
local reader = require('reader')
local writer = require('writer')

local flate = {}

function flate.compress(data)
	return miniz.deflate(data, 0)
end

function flate.decompress(data)
	return miniz.inflate(data, 0)
end

--- @class std.flate.writer : std.writer
--- @field underlying std.writer
--- @field state userdata
--- @field adler integer|nil
flate.writer = class('std.flate.writer', writer)

function flate.writer:init(underlying, compute_adler)
	self.underlying = underlying
	self.state = miniz.new_deflator()
	self.adler = compute_adler and 1 or nil
end

function flate.writer:flush(timeout)
	local parts = self.buffer:parts()
	local written = 0

	for _, part in ipairs(parts) do
		local compressed, compress_err = self.state:deflate(part)
		if not compressed then
			return written, compress_err
		end

		if #compressed > 0 then
			local write_ok, write_err = self.underlying:write(compressed, timeout)
			if not write_ok then
				return written, write_err
			end
		end

		if self.adler then
			self.adler = miniz.adler32(self.adler, part)
		end

		written = written + #part
	end

	return written
end

function flate.writer:finish(timeout)
	local ok, err = self:flushAll(timeout)
	if not ok then
		return false, err
	end

	local compressed, compress_err = self.state:deflate('', 'finish')
	if not compressed then
		return false, compress_err
	end

	if #compressed > 0 then
		local write_ok, write_err = self.underlying:write(compressed, timeout)
		if not write_ok then
			return false, write_err
		end
	end

	return true
end

--- @class std.flate.reader : std.reader
--- @field underlying std.reader
--- @field state userdata
--- @field adler integer|nil
flate.reader = class('std.flate.reader', reader)

function flate.reader:init(underlying, compute_adler)
	self.underlying = underlying
	self.state = miniz.new_inflator()
	self.adler = compute_adler and 1 or nil
end

function flate.reader:fill(n, timeout)
	while true do
		local compressed, read_err = self.underlying:readAtLeast(1, timeout)
		if not compressed then
			return 0, read_err
		end

		local decompressed, decompress_err = self.state:inflate(compressed)
		if not decompressed then
			return 0, decompress_err
		end

		if #decompressed > 0 then
			if self.adler then
				self.adler = miniz.adler32(self.adler, decompressed)
			end

			self.buffer:write(decompressed)
			return #decompressed
		end
	end
end

flate.zlib = {}

function flate.zlib.compress(data)
	return miniz.deflate(data, 0x1000)
end

function flate.zlib.decompress(data)
	return miniz.inflate(data, 1)
end

--- @class std.flate.zlib.writer : std.flate.writer
flate.zlib.writer = class('std.flate.zlib.writer', flate.writer)

function flate.zlib.writer:init(underlying)
	flate.writer.init(self, underlying, true)

	local corked = self.underlying.corked
	self.underlying.corked = true
	self.underlying:write('\x78\x9c')
	self.underlying.corked = corked
end

function flate.zlib.writer:finish(timeout)
	local ok, err = flate.writer.finish(self, timeout)
	if not ok then
		return false, err
	end

	local adler_bytes = string.pack('>I4', self.adler)
	local write_ok, write_err = self.underlying:write(adler_bytes, timeout)
	if not write_ok then
		return false, write_err
	end

	return true
end

--- @class std.flate.zlib.reader : std.flate.reader
flate.zlib.reader = class('std.flate.zlib.reader', flate.reader)

function flate.zlib.reader:init(underlying)
	flate.reader.init(self, underlying, true)
end

function flate.zlib.reader:prepare(timeout)
	local header, read_err = self.underlying:readExact(2, timeout)
	if not header then
		return false, read_err
	end

	local cmf, flg = string.byte(header, 1, 2)
	if cmf % 0x10 ~= 0x8 then
		return false, 'invalid zlib header'
	end

	if (cmf * 256 + flg) % 31 ~= 0 then
		return false, 'invalid zlib header'
	end

	if math.floor(flg / 0x20) % 2 ~= 0 then
		return false, 'invalid zlib header'
	end

	return true
end

function flate.zlib.reader:finish(timeout)
	local adler_bytes, read_err = self.underlying:readExact(4, timeout)
	if not adler_bytes then
		return false, read_err
	end

	local expected_adler = string.unpack('>I4', adler_bytes)
	if self.adler ~= expected_adler then
		return false, 'adler checksum mismatch'
	end

	return true
end

return flate
