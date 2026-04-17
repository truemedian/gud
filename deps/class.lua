local class = {}

--- @generic T
--- @class std.class<T>
--- @field new fun(...): T

local class_meta = {}

function class_meta:__tostring()
	return string.format('class: %s', self.__name)
end

function class_meta:__call(...)
	return self.new(...)
end

--- @generic T
--- @param name `T`
--- @param base any
--- @return std.class<T>
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

	function cls.new(...)
		local instance = setmetatable({}, cls)
		if instance.init then
			instance:init(...)
		end
		return instance
	end

	return setmetatable(cls, class_meta)
end

function class.isinstanceof(obj, cls)
	local obj_cls = getmetatable(obj)
	while obj_cls do
		if obj_cls == cls then
			return true
		end
		obj_cls = obj_cls.__base
	end
	return false
end

return setmetatable(class, {
	__call = function(_, ...)
		return class.new(...)
	end,
})
