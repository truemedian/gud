local floor = math.floor

--- A value not equal to any other numeric value, including itself.
math.nan = 0 / 0

--- A value larger than any other numeric value.
math.inf = math.huge

if 2 ^ 32 + 1 == 2 ^ 32 then
	math.significand_bits = 23
	math.exponent_bits = 8
	math.exponent_bias = 127
else
	math.significand_bits = 52
	math.exponent_bits = 11
	math.exponent_bias = 1023
end

--- The smallest positive normal number such that 1.0 + epsilon != 1.0.
math.epsilon = 2 ^ -math.significand_bits

--- The largest representable finite number.
math.max_normal = 2 ^ ((2 ^ math.exponent_bits - 1) - math.exponent_bias) * (2 - math.epsilon)

--- The smallest representable positive normal number.
math.min_normal = 2 ^ (1 - math.exponent_bias)

--- The smallest representable positive subnormal number.
math.min_subnormal = 2 ^ (1 - math.exponent_bias - math.significand_bits)

if not math.maxinteger or not math.mininteger then
	--- The largest representable integer such that `math.maxinteger + 1 == math.maxinteger`.
	math.maxinteger = 2 ^ (math.significand_bits + 1) - 1

	--- The smallest representable integer such that `math.mininteger - 1 == math.mininteger`.
	math.mininteger = -math.maxinteger
end

--- Clamps `x` to the range `[min, max]`.
--- @param x number
--- @param min number
--- @param max number
--- @return number
function math.clamp(x, min, max)
	return x < min and min or (x > max and max or x)
end

--- Rounds `x` to the nearest integer. If `precision` is given, rounds to the nearest multiple of `10 ^ -precision`.
---
--- Ties are rounded away from zero, so `math.round(0.5)` is 1, and `math.round(-0.5)` is -1.
--- @param x number
--- @param precision? integer
--- @return number
function math.round(x, precision)
	precision = 10 ^ (precision or 0)
	local s = math.sign(x)
	return s * floor(s * x * precision + 0.5) / precision
end

--- Rounds `x` to the nearest integer. If `precision` is given, rounds to the nearest multiple of `10 ^ -precision`.
---
--- Always rounds towards zero, so `math.trunc(0.5)` is 0, and `math.trunc(-0.5)` is 0.
--- @param x number
--- @param precision? integer
--- @return number
function math.trunc(x, precision)
	precision = 10 ^ (precision or 0)
	local s = math.sign(x)
	return s * floor(s * x * precision) / precision
end

--- Returns the sign of `x`, which is 1 if `x` is positive, -1 if `x` is negative, and 0 if `x` is zero.
--- @param x number
--- @return integer
function math.sign(x)
	return x > 0 and 1 or (x < 0 and -1 or 0)
end

--- Returns true if `x` is nan, and false otherwise.
--- @param x number
--- @return boolean
function math.isnan(x)
	return x ~= x and type(x) == 'number'
end

--- Returns true if `x` is infinite, and false otherwise.
--- @param x number
--- @return boolean
function math.isinf(x)
	return x == math.huge or x == -math.huge
end

--- Returns the greatest common divisor of `a` and `b`.
--- @param a integer
--- @param b integer
--- @return integer
function math.gcd(a, b)
	while b ~= 0 do
		a, b = b, a % b
	end

	return math.abs(a)
end

if not math.tointeger then
	--- @param x number
	--- @return integer|nil
	function math.tointeger(x)
		if type(x) == 'number' and floor(x) == x and x >= math.mininteger and x <= math.maxinteger then
			return x
		else
			return nil
		end
	end
end

if not math.type then
	--- @param x number
	--- @return 'float'|nil
	function math.type(x)
		if type(x) ~= 'number' then
			return nil
		end

		return 'float'
	end
end

if not math.ult then
	--- @param m number
	--- @param n number
	--- @return boolean
	function math.ult(m, n)
		m = assert(math.tointeger(m), 'bad argument #1 to math.ult (integer expected, got ' .. type(m) .. ')')
		n = assert(math.tointeger(n), 'bad argument #2 to math.ult (integer expected, got ' .. type(n) .. ')')

		if m < 0 then
			m = m + 2 ^ 64
		end

		if n < 0 then
			n = n + 2 ^ 64
		end

		return m < n
	end
end
