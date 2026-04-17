--- Iterates over the values of the given table, returning each value and its corresponding key.
---
--- Like `pairs`, but returns `v, k` instead of `k, v`.
--- @generic K, V
--- @param tbl table<K, V>
--- @return fun(): V, K
function _G.vpairs(tbl)
	local key
	return function()
		local value
		key, value = next(tbl, key)
		if key ~= nil then
			return value, key
		end
	end
end

--- Iterates over the values of the given sequence, returning each value and its corresponding key.
---
--- Like `ipairs`, but returns `v, k` instead of `k, v`.
--- @generic V
--- @param tbl table<integer, V>
--- @return fun(): V, integer
function _G.ivpairs(tbl)
	local i = 0
	return function()
		i = i + 1
		local value = tbl[i]
		if value ~= nil then
			return value, i
		end
	end
end

--- Iterates over the values of the given table, returning each value and its corresponding key, in an order defined by
--- the given comparator.
--- @generic K, V
--- @param tbl table<K, V>
--- @param cmp? fun(a: K, b: K): boolean
--- @return fun(): K, V
function _G.spairs(tbl, cmp)
	local keys = table.keys(tbl)
	table.sort(keys, cmp)

	local i = 0
	return function()
		i = i + 1
		local key = keys[i]
		if key ~= nil then
			return key, tbl[key]
		end
	end
end
