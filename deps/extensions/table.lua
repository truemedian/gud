--- @alias table.filter<K, V> fun(value: V, key: K): boolean
--- @alias table.mapper<K, V, NK, NV> fun(value: V, key: K): new_value: NV, new_key: NK
--- @alias table.comparator<K> fun(a: K, b: K): boolean

local floor, random = math.floor, math.random

table.unpack = table.unpack or unpack

table.pack = table.pack or function(...)
	return { n = select('#', ...), ... }
end

--- Returns a shallow copy of `tbl`.
--- @generic K, V
--- @param tbl table<K, V>
--- @return table<K, V>
function table.copy(tbl)
	local copy = {}

	for k, v in pairs(tbl) do
		copy[k] = v
	end

	return copy
end

--- Returns a deep copy of `tbl`.
--- @generic K, V
--- @param tbl table<K, V>
--- @param seen? table<V, table<K, V>>
--- @return table<K, V>
function table.deepcopy(tbl, seen)
	seen = seen or {}
	if seen[tbl] then
		return seen[tbl]
	end

	local copy = {}
	seen[tbl] = copy

	for k, v in pairs(tbl) do
		if type(v) == 'table' then
			v = table.deepcopy(v)
		end

		copy[k] = v
	end

	return copy
end

--- Returns a new table containing the results of applying `mapper` to each entry of `tbl`.
--- @generic K, V, NK, NV
--- @param tbl table<K, V>
--- @param mapper table.mapper<K, V, NK, NV>
--- @return table<NK, NV>
function table.map(tbl, mapper)
	local mapped = {}

	for k, v in pairs(tbl) do
		local new_v, new_k = mapper(v, k)

		if new_k == nil then
			new_k = k
		end

		mapped[new_k] = new_v
	end

	return mapped
end

--- Returns a new table containing only the entries of `tbl` for which `predicate` returns true.
--- @generic K, V
--- @param tbl table<K, V>
--- @param predicate table.filter<K, V>
--- @return table<K, V>
function table.filter(tbl, predicate)
	local filtered = {}

	for k, v in pairs(tbl) do
		if predicate(v, k) then
			filtered[k] = v
		end
	end

	return filtered
end

--- Shuffles the elements of sequence `tbl` in place.
--- @generic V
--- @param tbl V[]
--- @return V[]
function table.shuffle(tbl)
	for i = #tbl, 2, -1 do
		local j = random(i)
		tbl[i], tbl[j] = tbl[j], tbl[i]
	end

	return tbl
end

--- Removes and returns the value associated with `key` in `tbl`, replacing it with the last element in the sequence.
---
--- Assumes that `tbl` is a sequence (i.e. there exists exactly one border). Does not preserve the order of the elements.
--- @generic K, V
--- @param tbl table<K, V>
--- @param i integer
--- @return V
function table.swapremove(tbl, i)
	local value = tbl[i]
	tbl[i] = table.remove(tbl)
	return value
end

--- Returns the key of the first occurrence of `value` in `tbl`, or nil if not found.
--- @generic K, V
--- @param tbl table<K, V>
--- @param value V
--- @param eq? fun(a: V, b: V): boolean
--- @return K|nil
function table.find(tbl, value, eq)
	if eq then
		for k, v in pairs(tbl) do
			if eq(v, value) then
				return k
			end
		end
	else
		for k, v in pairs(tbl) do
			if v == value then
				return k
			end
		end
	end

	return nil
end

--- Returns the index of the first element in sorted `tbl` that is not less than `value` according to `less`, or `#tbl + 1` if there is no such element.
--- @generic V
--- @param tbl V[]
--- @param value V
--- @param less table.comparator<V>
--- @return integer
function table.lower_bound(tbl, value, less)
	local low, high = 1, #tbl + 1

	while low < high do
		local mid = floor((low + high) / 2)
		if less(tbl[mid], value) then
			low = mid + 1
		else
			high = mid
		end
	end

	return low
end

--- Returns the index of the first element in sorted `tbl` that is greater than `value` according to `less`, or
--- `#tbl + 1` if there is no such element.
--- @generic V
--- @param tbl V[]
--- @param value V
--- @param less table.comparator<V>
--- @return integer
function table.upper_bound(tbl, value, less)
	local low, high = 1, #tbl + 1

	while low < high do
		local mid = floor((low + high) / 2)
		if less(value, tbl[mid]) then
			high = mid
		else
			low = mid + 1
		end
	end

	return low
end

--- Inserts `value` into sorted `tbl` according to `less`, and returns the index at which it was inserted.
--- @generic V
--- @param tbl V[]
--- @param value V
--- @param less table.comparator<V>
--- @return integer
function table.insert_sorted(tbl, value, less)
	local i = table.lower_bound(tbl, value, less)
	table.insert(tbl, i, value)
	return i
end

--- Removes the first occurrence of `value` from sorted `tbl` according to `less`, and returns true if it was removed,
--- or false if it was not found.
--- @generic V
--- @param tbl V[]
--- @param value V
--- @param less table.comparator<V>
--- @return boolean
function table.remove_sorted(tbl, value, less)
	local i = table.lower_bound(tbl, value, less)
	if i <= #tbl and not less(value, tbl[i]) and not less(tbl[i], value) then
		table.remove(tbl, i)
		return true
	else
		return false
	end
end

--- Returns the index of the first occurrence of `value` in sorted `tbl` according to `less`, or nil if not found.
---
--- This function operates in logarithmic time, so it is more efficient than `table.find` for large sorted tables.
--- @generic V
--- @param tbl V[]
--- @param value V
--- @param less table.comparator<V>
--- @return integer|nil
function table.find_sorted(tbl, value, less)
	local i = table.lower_bound(tbl, value, less)
	if i <= #tbl and not less(value, tbl[i]) and not less(tbl[i], value) then
		return i
	else
		return nil
	end
end

--- Returns true if `tbl` has no entries, false otherwise.
--- @param tbl table
--- @return boolean
function table.isempty(tbl)
	return next(tbl) == nil
end

--- Returns the number of entries in `tbl`.
--- @param tbl table
--- @return integer
function table.size(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end

	return count
end

--- Returns true if `predicate` returns true for any entry of `tbl`, false otherwise.
--- @generic K, V
--- @param tbl table<K, V>
--- @param predicate table.filter<K, V>
--- @return boolean
function table.any(tbl, predicate)
	for k, v in pairs(tbl) do
		if predicate(v, k) then
			return true
		end
	end

	return false
end

--- Returns true if `predicate` returns true for all entries of `tbl`, false otherwise.
--- @generic K, V
--- @param tbl table<K, V>
--- @param predicate table.filter<K, V>
--- @return boolean
function table.all(tbl, predicate)
	for k, v in pairs(tbl) do
		if not predicate(v, k) then
			return false
		end
	end

	return true
end

--- Returns a new sequence containing the keys of `tbl`.
--- @generic K, V
--- @param tbl table<K, V>
--- @return K[]
function table.keys(tbl)
	local keys, n = {}, 0

	for k in pairs(tbl) do
		n = n + 1
		keys[n] = k
	end

	return keys
end

--- Returns a new sequence containing the values of `tbl`.
--- @generic K, V
--- @param tbl table<K, V>
--- @return V[]
function table.values(tbl)
	local values, n = {}, 0

	for k, v in pairs(tbl) do
		n = n + 1
		values[n] = v
	end

	return values
end

--- Returns a new table with the keys and values of `tbl` swapped. If there are duplicate values in `tbl`, only one of the corresponding keys will be preserved in the output.
--- @generic K, V
--- @param tbl table<K, V>
--- @return table<V, K>
function table.transpose(tbl)
	local transposed = {}

	for k, v in pairs(tbl) do
		transposed[v] = k
	end

	return transposed
end

--- Collects the values returned by `iter` into a new sequence.
--- @generic V
--- @param iter fun(): V
--- @return V[]
function table.collect(iter)
	local collected, n = {}, 0
	for v in iter do
		n = n + 1
		collected[n] = v
	end

	return collected
end

--- Iterates all `n`-permutations of the elements of `tbl`.
--- @generic V
--- @param tbl table<integer, V>
--- @param n integer
--- @return fun(): V[]
--- @return integer
function table.permutations(tbl, n)
	local r = {}

	local function permute(i)
		if i > n then
			coroutine.yield(r)
		else
			for j = i, #tbl do
				tbl[i], tbl[j] = tbl[j], tbl[i]
				r[i] = tbl[i]
				permute(i + 1)
				tbl[i], tbl[j] = tbl[j], tbl[i]
			end
		end
	end

	return coroutine.wrap(permute), 1
end

--- Iterates all `n`-combinations of the elements of `tbl`.
--- @generic V
--- @param tbl table<integer, V>
--- @param n integer
--- @return fun(): V[]
--- @return integer
--- @return integer
function table.combinations(tbl, n)
	local r = {}

	local function combine(i, j)
		if i > n then
			coroutine.yield(r)
		else
			for k = j, #tbl do
				r[i] = tbl[k]
				combine(i + 1, k + 1)
			end
		end
	end

	return coroutine.wrap(combine), 1, 1
end

pcall(require, 'table.clear')
if not table.clear then
	function table.clear(tbl)
		for k in pairs(tbl) do
			tbl[k] = nil
		end
	end
end
