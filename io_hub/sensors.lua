local M = {}

local previous = {}

local function now()
    if os and type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    if os and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

local function wrap(spec)
    if type(peripheral) ~= "table" then
        return nil, "peripheral API is unavailable"
    end

    local name = spec.remoteName
    if type(name) == "string" and name ~= "" then
        local device = peripheral.wrap(name)
        if not device then
            return nil, "cannot wrap peripheral [" .. name .. "]"
        end

        return device
    end

    local peripheralType = spec.peripheralType
    if type(peripheralType) == "string" and peripheralType ~= "" then
        if type(peripheral.find) ~= "function" then
            return nil, "peripheral.find is unavailable"
        end

        local device = peripheral.find(peripheralType)
        if not device then
            return nil, "cannot find peripheral type [" .. peripheralType .. "]"
        end

        return device
    end

    return nil, "remoteName and peripheralType are both empty"
end

local function selectValue(raw, spec)
    if type(raw) == "number" then
        return raw
    end

    if type(raw) ~= "table" then
        return nil, "method returned " .. type(raw)
    end

    if spec.field ~= nil and raw[spec.field] ~= nil then
        return raw[spec.field]
    end

    if spec.axis ~= nil and raw[spec.axis] ~= nil then
        return raw[spec.axis]
    end

    if spec.index ~= nil and raw[spec.index] ~= nil then
        return raw[spec.index]
    end

    return nil, "table result has no configured axis/index"
end

local function applyScale(value, spec)
    return value * (tonumber(spec.scale) or 1) + (tonumber(spec.bias) or 0)
end

local function readMethod(name, spec)
    local device, err = wrap(spec)
    if not device then
        return nil, err
    end

    local methodName = spec.method
    if type(methodName) ~= "string" or methodName == "" then
        return nil, "method is empty"
    end

    local method = device[methodName]
    if type(method) ~= "function" then
        return nil, "configured peripheral has no method [" .. methodName .. "]"
    end

    local returns = { pcall(method) }
    if not returns[1] then
        return nil, returns[2]
    end

    local raw
    if #returns == 2 then
        raw = returns[2]
    else
        raw = {}
        for i = 2, #returns do
            raw[i - 1] = returns[i]
        end
    end

    local value, selectErr = selectValue(raw, spec)
    if value == nil then
        return nil, selectErr
    end

    return applyScale(value, spec)
end

local function readDerivedDelta(name, spec, values, timestamp)
    local sourceName = spec.source
    local source = values[sourceName]
    if source == nil then
        return nil, "source [" .. tostring(sourceName) .. "] is unavailable"
    end

    local old = previous[name]
    previous[name] = {
        t = timestamp,
        value = source
    }

    if not old then
        return 0
    end

    local dt = timestamp - old.t
    if dt <= 0 then
        return nil, "non-positive dt"
    end

    return applyScale((source - old.value) / dt, spec)
end

function M.names(cfg)
    local names = {}
    local seen = {}

    for _, name in ipairs(cfg.sensorOrder or {}) do
        local spec = cfg.sensors and cfg.sensors[name]
        if type(spec) == "table" and spec.enabled ~= false then
            names[#names + 1] = name
            seen[name] = true
        end
    end

    for name, spec in pairs(cfg.sensors or {}) do
        if not seen[name] and type(spec) == "table" and spec.enabled ~= false then
            names[#names + 1] = name
        end
    end

    return names
end

function M.readAll(cfg)
    local result = {
        order = {},
        t = now()
    }

    for _, name in ipairs(M.names(cfg)) do
        local spec = cfg.sensors[name]
        local value, err
        if spec.driver == "derived_delta" then
            value, err = readDerivedDelta(name, spec, result, result.t)
        else
            value, err = readMethod(name, spec)
        end

        result.order[#result.order + 1] = name
        result[name] = value
        if err then
            result[name .. "Err"] = err
        end
    end

    return result
end

function M.readSome(cfg, names)
    local result = {
        order = {},
        t = now()
    }

    for _, name in ipairs(names or {}) do
        local spec = cfg.sensors and cfg.sensors[name]
        result.order[#result.order + 1] = name
        if type(spec) ~= "table" or spec.enabled == false then
            result[name] = nil
            result[name .. "Err"] = "sensor disabled or missing"
        else
            local value, err
            if spec.driver == "derived_delta" then
                value, err = readDerivedDelta(name, spec, result, result.t)
            else
                value, err = readMethod(name, spec)
            end

            result[name] = value
            if err then
                result[name .. "Err"] = err
            end
        end
    end

    return result
end

return M
