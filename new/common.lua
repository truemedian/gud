-- local bit = require('bit')
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

function common.read_pack_varsize(data, offset)
    --[[
    local byte = data:byte(offset)
    local result = bit.band(byte, 0x7f)
    local shift = 7
    offset = offset + 1

    while bit.band(byte, 0x80) > 0 do
        byte = data:byte(offset)
        local value = bit.band(byte, 0x7f) * 2 ^ shift
        result = result + value

        shift = shift + 7
        offset = offset + 1
    end

    return result, offset
    ]]

    local b1, b2, b3, b4, b5, b6, b7, b8 = data:byte(offset, offset + 7)
    if b1 < 0x80 then return b1, offset + 1 end

    if b2 < 0x80 then return -0x80 + b1 + b2 * 0x80, offset + 2 end

    if b3 < 0x80 then return -0x4080 + b1 + b2 * 0x80 + b3 * 0x4000, offset + 3 end

    if b4 < 0x80 then return -0x204080 + b1 + b2 * 0x80 + b3 * 0x4000 + b4 * 0x200000, offset + 4 end

    if b5 < 0x80 then return -0x10204080 + b1 + b2 * 0x80 + b3 * 0x4000 + b4 * 0x200000 + b5 * 0x10000000, offset + 5 end

    if b6 < 0x80 then
        return -0x810204080 + b1 + b2 * 0x80 + b3 * 0x4000 + b4 * 0x200000 + b5 * 0x10000000 + b6 * 0x800000000,
               offset + 6
    end

    if b7 < 0x80 then
        return
            -0x40810204080 + b1 + b2 * 0x80 + b3 * 0x4000 + b4 * 0x200000 + b5 * 0x10000000 + b6 * 0x800000000 + b7 *
                0x40000000000, offset + 7
    end

    if b8 < 0x80 then
        return
            -0x2040810204080 + b1 + b2 * 0x80 + b3 * 0x4000 + b4 * 0x200000 + b5 * 0x10000000 + b6 * 0x800000000 + b7 *
                0x40000000000 + b8 * 0x2000000000000, offset + 8
    end

    error('variable length size too large')
end

function common.read_pack_varoffset(data, offset)
    --[[
    local byte = data:byte(offset)
    local result = bit.band(byte, 0x7f)
    offset = offset + 1

    while bit.band(byte, 0x80) > 0 do
        byte = data:byte(offset)

        result = (result + 1) * 0x80 + bit.band(byte, 0x7f)
        offset = offset + 1
    end

    return result, offset
    ]]

    local b1, b2, b3, b4, b5, b6, b7, b8 = data:byte(offset, offset + 7)
    if b1 < 0x80 then return b1, offset + 1 end

    if b2 < 0x80 then return -0x3f80 + b1 * 0x80 + b2, offset + 2 end

    if b3 < 0x80 then return -0x1fbf80 + b1 * 0x4000 + b2 * 0x80 + b3, offset + 3 end

    if b4 < 0x80 then return -0xfdfbf80 + b1 * 0x200000 + b2 * 0x4000 + b3 * 0x80 + b4, offset + 4 end

    if b5 < 0x80 then
        return -0x7efdfbf80 + b1 * 0x10000000 + b2 * 0x200000 + b3 * 0x4000 + b4 * 0x80 + b5, offset + 5
    end

    if b6 < 0x80 then
        return -0x3f7efdfbf80 + b1 * 0x800000000 + b2 * 0x10000000 + b3 * 0x200000 + b4 * 0x4000 + b5 * 0x80 + b6,
               offset + 6
    end

    if b7 < 0x80 then
        return
            -0x1fbf7efdfbf80 + b1 * 0x40000000000 + b2 * 0x800000000 + b3 * 0x10000000 + b4 * 0x200000 + b5 * 0x4000 +
                b6 * 0x80 + b7, offset + 7
    end

    if b8 < 0x80 then
        return
            -0xfdfbf7efdfbf80 + b1 * 0x2000000000000 + b2 * 0x40000000000 + b3 * 0x800000000 + b4 * 0x10000000 + b5 *
                0x200000 + b6 * 0x4000 + b7 * 0x80 + b8, offset + 8
    end

    error('variable length offset too large')
end

return common
