local common = require("http/common.lua")

local Client = {}
Client.__index = Client

function Client.new(options)
	local self = setmetatable({}, Client)
end

function Client:request(method, target, headers)
	
end