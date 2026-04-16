local unpack = table.unpack or unpack

local utility = {}

local function assertresume_aux(success, ...)
	if success then
		return ...
	else
		return error(..., 1)
	end
end

function utility.assertresume(co, ...)
	return assertresume_aux(coroutine.resume(co, ...))
end

function utility.bind1(fn, a)
	return function(...)
		return fn(a, ...)
	end
end

function utility.bind2(fn, a, b)
	return function(...)
		return fn(a, b, ...)
	end
end

function utility.bind3(fn, a, b, c)
	return function(...)
		return fn(a, b, c, ...)
	end
end

function utility.bind4(fn, a, b, c, d)
	return function(...)
		return fn(a, b, c, d, ...)
	end
end

function utility.bind(fn, ...)
	local bound_len = select('#', ...)
	if bound_len == 0 then
		return fn
	elseif bound_len == 1 then
		return utility.bind1(fn, ...)
	elseif bound_len == 2 then
		return utility.bind2(fn, ...)
	elseif bound_len == 3 then
		return utility.bind3(fn, ...)
	elseif bound_len == 4 then
		return utility.bind4(fn, ...)
	else
		local bound_args = { ... }
		local info = debug.getinfo(fn, 'u')
		local nparams = info.isvararg and math.huge or info.nparams or math.huge
		local left = nparams - bound_len

		if left <= 0 then
			return function()
				return fn(unpack(bound_args, 1, nparams))
			end
		end

		return function(...)
			local n = math.min(select('#', ...), left)
			for i = 1, n do
				bound_args[bound_len + i] = select(i, ...)
			end

			return fn(unpack(bound_args, 1, bound_len + n))
		end
	end
end

function utility.sortedpairs(tbl, cmp)
	local keys, n = {}, 0
	for k in pairs(tbl) do
		n = n + 1
		keys[n] = k
	end

	table.sort(keys, cmp)

	local i = 0
	return function()
		i = i + 1
		local k = keys[i]
		if k then
			return k, tbl[k]
		end
	end
end

return utility
