local class = require('class')

local openssl = require('openssl')

--- @class std.git.oid : string
--- @class std.git.oid.binary : string

--- @class std.git.oid_type : std.class<std.git.oid_type>
local oid_type = class.new('std.git.oid_type')

function oid_type:init(alg)
	if alg == 'sha1' then
		self.alg = 'sha1'
		self.binsize = 20
		self.hexsize = 40
	elseif alg == 'sha256' then
		self.alg = 'sha256'
		self.binsize = 32
		self.hexsize = 64
	else
		error('unsupported oid type: ' .. tostring(alg))
	end
end

--- Compute the digest of the given data using this OID type.
--- @param data string
--- @param hex boolean
--- @return string digest
function oid_type:digest(data, hex)
	return openssl.digest.digest(self.alg, data, hex)
end

--- Compute the digest of the given data in git form using this OID type.
--- @param data string
--- @param kind string
--- @param hex boolean
--- @return std.git.oid|std.git.oid.binary digest
function oid_type:oid(data, kind, hex)
	local digest = openssl.digest.new(self.alg)
	digest:update(kind .. ' ' .. tostring(#data) .. '\x00')
	return digest:final(data, not hex)
end

--- Convert a hexadecimal OID to its binary form.
--- @param hex std.git.oid
--- @return std.git.oid.binary oid
function oid_type:hex2bin(hex)
	assert(self:check_hex(hex))
	return openssl.hex(hex, false)
end

--- Convert a binary OID to its hexadecimal form.
--- @param bin std.git.oid.binary
--- @return std.git.oid oid
function oid_type:bin2hex(bin)
	assert(self:check_bin(bin))
	return openssl.hex(bin, true)
end

--- Check if the given binary OID is valid.
--- @param oid std.git.oid.binary
--- @return boolean is_valid
--- @return string|nil err
function oid_type:check_bin(oid)
	if type(oid) ~= 'string' then
		return false, 'binary oid must be a string'
	elseif #oid ~= self.binsize then
		return false, 'binary oid must be ' .. self.binsize .. ' characters'
	end

	return true
end

--- Check if the given hexadecimal OID is valid.
--- @param oid std.git.oid
--- @return boolean is_valid
--- @return string|nil err
function oid_type:check_hex(oid)
	if type(oid) ~= 'string' then
		return false, 'oid must be a string'
	elseif #oid ~= self.hexsize then
		return false, 'oid must be ' .. self.hexsize .. ' characters'
	elseif oid:find('[^0-9a-f]') then
		return false, 'oid contains invalid characters'
	end

	return true
end

return oid_type
