local M = {}

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

local function copyPoints(levels)
    if type(levels) ~= "table" then
        return {}
    end
    local points = {}
    for _, item in ipairs(levels) do
        local altitude = tonumber(item.altitude or item[1])
        local level = tonumber(item.level or item.value or item[2])
        if altitude ~= nil and level ~= nil then
            points[#points + 1] = { altitude = altitude, level = level }
        end
    end
    table.sort(points, function(left, right)
        return left.altitude < right.altitude
    end)
    return points
end

function M.new(cfg)
    cfg = cfg or {}
    return {
        enabled = cfg.enabled ~= false,
        source = cfg.source or "target",
        points = copyPoints(cfg.levels or cfg.levelPoints),
        outputMin = tonumber(cfg.outputMin) or 0,
        outputMax = tonumber(cfg.outputMax) or 15
    }
end

function M.evaluate(model, altitude)
    if type(model) ~= "table" or model.enabled == false then
        return { level = 0, source = "disabled" }
    end

    local h = tonumber(altitude)
    if h == nil then
        return nil, "invalid feedforward altitude"
    end

    local points = model.points or {}
    if #points == 0 then
        return { level = 0, source = "empty" }
    end
    if #points == 1 then
        return {
            level = clamp(points[1].level, model.outputMin, model.outputMax),
            source = "single"
        }
    end

    local left = points[1]
    local right = points[2]
    if h >= points[#points].altitude then
        left = points[#points - 1]
        right = points[#points]
    else
        for index = 2, #points do
            if h <= points[index].altitude then
                left = points[index - 1]
                right = points[index]
                break
            end
        end
    end

    local span = right.altitude - left.altitude
    local level = left.level
    if span ~= 0 then
        local ratio = (h - left.altitude) / span
        level = left.level + (right.level - left.level) * ratio
    end

    return {
        level = clamp(level, model.outputMin, model.outputMax),
        source = "table"
    }
end

return M
