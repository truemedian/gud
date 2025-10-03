local common = require("http/common.lua")

local client = {}
client.__index = client

---@class luvit.http.client.request
---@field private writable luvit.stream.writable
local request = {}
request.__index = request

function request.new(writable)
	local self = setmetatable({ writable = writable }, request)
	return self
end

function request:start(method, target, headers)
	self.writable:cork()

	local line = method .. " " .. target .. " HTTP/1.1\r\n"
	local _ = self.writable:write(line)

	if headers then
		for _, v in ipairs(headers) do
			_ = self.writable:write(v[1])
			_ = self.writable:write(": ")
			_ = self.writable:write(v[2])
			_ = self.writable:write("\r\n")
		end
	end

	_ = self.writable:write("\r\n")

	local ok, err = self.writable:uncork()
    if not ok then
		return error('failed to send request headers: ' .. err)
	end
end

local response = {}
response.__index = response
