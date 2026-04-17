local class = require('class')

local object = require('git/object')

--- @class std.git.object.blob : std.git.object, std.class<std.git.object.blob>
--- @field data string
local blob = class.new('std.git.object.blob', object)
blob.kind = 'blob'

--- @param data string
function blob:init(data)
	self.data = data
end

--- @param data string
--- @return std.git.object.blob
function blob.parse(data)
	return blob.new(data)
end

--- @return string
function blob:serialize()
	return self.data
end

return blob
