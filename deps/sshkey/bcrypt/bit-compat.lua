local has_bitop, bitop = pcall(require, 'bit')
if has_bitop then
	bit.bxor3 = bit.bxor
	return bitop
end

local has_bit32, bit32 = pcall(require, 'bit32')
if has_bit32 then
	bit32.bxor3 = bit32.bxor
	return bit32
end

return load([[
local bit = {}
function bit.band(a, b)
    return a & b & 0xffffffff
end
function bit.bxor(a, b)
    return (a ~ b) & 0xffffffff
end
function bit.bxor3(a, b, c)
    return (a ~ b ~ c) & 0xffffffff
end
function bit.lshift(a, b)
    return (a << b) & 0xffffffff
end
function bit.rshift(a, b)
    return (a >> b) & 0xffffffff
end
return bit
]])()
