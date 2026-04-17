local floor, ceil, random, min = math.floor, math.ceil, math.random, math.min
local sub, byte, rep, char, find, match = string.sub, string.byte, string.rep, string.char, string.find, string.match
local concat = table.concat

--- Returns true if `str` starts with `prefix`.
--- @param str string
--- @param prefix string
--- @param plain? boolean
--- @return boolean
function string.startswith(str, prefix, plain)
	if plain then
		return sub(str, 1, #prefix) == prefix
	end

	return find(str, '^' .. prefix) == 1
end

--- Returns true if `str` ends with `suffix`.
--- @param str string
--- @param suffix string
--- @param plain? boolean
--- @return boolean
function string.endswith(str, suffix, plain)
	if plain then
		return sub(str, -#suffix) == suffix
	end

	local _, j = find(str, suffix .. '$')
	return j == #str
end

--- Returns a new string with all leading and trailing occurrences of the pattern removed.
---
--- The pattern should consist of a single pattern item.
---
--- By default, the pattern is `%s`, which will trim all whitespace.
--- @param str string
--- @param pattern? string
--- @return string
function string.trim(str, pattern)
	pattern = pattern or '%s'
	assert(#pattern > 0)

	return match(str, '^' .. pattern .. '*(.-)' .. pattern .. '*$')
end

--- Returns a new string with the left padded with `pattern` or spaces until the string is `final_len` characters long.
---
--- Multi-byte padding will overshoot `final_len`.
--- @param str string
--- @param final_len number
--- @param pattern? string
--- @return string
function string.rjust(str, final_len, pattern)
	pattern = pattern or ' '
	return rep(pattern, floor((final_len - #str) / #pattern)) .. str
end

--- Returns a new string with both sides padded with `pattern` or spaces until the string is `final_len` characters long.
---
--- Multi-byte padding will overshoot `final_len`.
--- @param str string
--- @param final_len number
--- @param pattern? string
--- @return string
function string.cjust(str, final_len, pattern)
	pattern = pattern or ' '
	local pad = 0.5 * (final_len - #str) / #pattern
	return rep(pattern, floor(pad)) .. str .. rep(pattern, ceil(pad))
end

--- Returns a new string with the right padded with `pattern` or spaces until the string is `final_len` characters long.
---
--- Multi-byte padding will overshoot `final_len`.
--- @param str string
--- @param final_len number
--- @param pattern? string
--- @return string
function string.ljust(str, final_len, pattern)
	pattern = pattern or ' '
	return str .. rep(pattern, floor((final_len - #str) / #pattern))
end

--- Returns a string of `len` random characters in the byte-range of `[mn, mx]`.
--- @param len number
--- @param mn? number The minimum byte value. Defaults to 0.
--- @param mx? number The maximum byte value. Defaults to 255.
--- @return string
function string.random(len, mn, mx)
	local ret = {}
	mn = mn or 0
	mx = mx or 255

	for n = 1, len do
		ret[n] = char(random(mn, mx))
	end

	return concat(ret)
end

--- Returns an iterator that splits `str` by `delim`. If `plain` is true, `delim` is interpreted as a plain string
--- instead of a pattern.
--- @param str string
--- @param delim string
--- @param plain? boolean
--- @return fun(): string|nil, integer|nil, integer|nil iterator
function string.split(str, delim, plain)
	assert(#delim > 0, 'delimiter must not be empty')

	local i = 1
	return function()
		local j, k = find(str, delim, i, plain)
		if j then
			local start, finish = i, j - 1

			local part = str:sub(start, finish)
			i = k + 1

			return part, start, i
		elseif i <= #str then
			local start = i

			local part = str:sub(start)
			i = #str + 1

			return part, start, i
		end
	end
end

--- Computes the Levenshtein distance between two strings. This is the minimum number of single-character edits
--- (insertions, deletions or substitutions) required to change one string into the other.
--- @param a string
--- @param b string
--- @return integer
function string.levenshtein(a, b)
	local m, n = #a, #b
	if a == b then
		return 0
	elseif m == 0 then
		return n
	elseif n == 0 then
		return m
	end

	local prev, curr = {}, {}
	for j = 0, n do
		prev[j] = j
	end

	for i = 1, m do
		curr[0] = i
		local a_byte = byte(a, i, i)

		for j = 1, n do
			local cost = a_byte == byte(b, j, j) and 0 or 1

			curr[j] = min(
				prev[j] + 1, -- deletion
				curr[j - 1] + 1, -- insertion
				prev[j - 1] + cost -- substitution
			)
		end

		prev, curr = curr, prev
	end

	return prev[n]
end
