local miniz = require("miniz")

local filter = {}

function filter.deflate()
    local deflator = miniz.new_deflator()

    local finished = false
    return function(data)
        if data then
            return deflator:deflate(data)
        elseif finished then
            return nil
        else
            finished = true
            return deflator:deflate("", "finish")
        end
    end
end

function filter.inflate()
    local inflator = miniz.new_inflator()

    local finished = false
    return function(data)
        if data then
            return inflator:inflate(data)
        elseif finished then
            return nil
        else
            finished = true
            return inflator:inflate("", "finish")
        end
    end
end

return filter