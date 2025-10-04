local class = {}

---@class luvit.class<T>
---@field init fun(self: `T`, ...)
---@field __call fun(...): `T`

function class.new(name, base)
	local cls = {}
	if base then
		for k, v in pairs(base) do
			cls[k] = v
		end
	end

	cls.__base = base
	cls.__index = cls
	cls.__name = name

	function cls:__tostring()
		return string.format("%s: %p", self.__name, self)
	end

	function cls:__call(...)
		local obj = setmetatable({}, cls)
		obj:init(...)
		return obj
	end

	return cls
end

function class.is(obj, cls)
	local mt = getmetatable(obj)
	while mt do
		if mt == cls then
			return true
		end
		mt = mt.__base
	end
	return false
end

setmetatable(class, {
	__call = function(_, ...)
		return class.new(...)
	end,
})

return class
