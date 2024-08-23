local bit = require('bit')

local common = {}

function common.read_u32be(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset + 3)
    return bit.lshift(b1, 24) + bit.lshift(b2, 16) + bit.lshift(b3, 8) + b4
end

function common.read_u64be(data, offset)
    local high = common.read_u32be(data, offset)
    local low = common.read_u32be(data, offset + 4)
    return high * 0x100000000 + low
end

function common.write_u32be(value)
    local b1 = bit.band(bit.rshift(value, 24), 0xff)
    local b2 = bit.band(bit.rshift(value, 16), 0xff)
    local b3 = bit.band(bit.rshift(value, 8), 0xff)
    local b4 = bit.band(value, 0xff)

    return string.char(b1, b2, b3, b4)
end

function common.write_u64be(value)
    local high = math.floor(value / 0x100000000)
    local low = bit.band(value, 0xffffffff)

    return common.write_u32be(high) .. common.write_u32be(low)
end

return common
