local class = {}

local class_meta = {}

function class_meta:__tostring()
	return string.format('class: %s', self.__name)
end

function class_meta:__call(...)
	local instance = setmetatable({}, self)
	if instance.init then
		instance:init(...)
	end
	return instance
end

function class.new(name, base)
	local cls = {}

	if base then
		for k, v in pairs(base) do
			cls[k] = v
		end
	end

	cls.__index = cls
	cls.__name = name
	cls.__base = base

	function cls:__tostring()
		return string.format('%s: %p', self.__name, self)
	end

	return setmetatable(cls, class_meta)
end

return setmetatable(class, {
	__call = function(_, ...)
		return class.new(...)
	end,
})
