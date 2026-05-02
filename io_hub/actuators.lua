local M = {}

local states = {}
local EPSILON = 1.0e-9
local REDSTONE_SIDES = { "left", "right", "front", "back", "top", "bottom" }

local function now()
    if os and type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    if os and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

local function getState(name)
    if not states[name] then
        states[name] = {
            command = 0,
            exactOutput = 0,
            lower = 0,
            upper = 0,
            fraction = 0,
            accumulator = 0,
            output = 0,
            initialized = false,
            lastUpdate = 0
        }
    end
    return states[name]
end

local function pwmEnabled(spec, cfg)
    if spec.pwmEnabled ~= nil then
        return spec.pwmEnabled ~= false
    end
    return not (cfg.actuatorPwm and cfg.actuatorPwm.enabled == false)
end

local function pwmPeriod(spec, cfg)
    return tonumber(spec.pwmPeriod) or tonumber(cfg.actuatorPwm and cfg.actuatorPwm.period) or 0.05
end

local function wrap(spec)
    if type(peripheral) ~= "table" then
        return nil, "peripheral API is unavailable"
    end

    local peripheralType = spec.peripheralType or "redstone_relay"
    local name = spec.remoteName
    if type(name) == "string" and name ~= "" then
        local device = peripheral.wrap(name)
        if not device then
            return nil, "cannot wrap peripheral [" .. name .. "]"
        end

        if type(peripheral.getType) == "function" then
            local actualType = peripheral.getType(name)
            if actualType ~= peripheralType then
                return nil, "[" .. tostring(name) .. "] is [" .. tostring(actualType) ..
                    "], expected [" .. tostring(peripheralType) .. "]"
            end
        end

        return device, nil, name
    end

    if type(peripheralType) == "string" and peripheralType ~= "" then
        if type(peripheral.find) ~= "function" then
            return nil, "peripheral.find is unavailable"
        end

        local device = peripheral.find(peripheralType)
        if not device then
            return nil, "cannot find peripheral type [" .. peripheralType .. "]"
        end

        return device, nil, peripheralType
    end

    return nil, "remoteName and peripheralType are both empty"
end

local function setAnalog(device, side, value)
    if type(device.setAnalogOutput) == "function" then
        device.setAnalogOutput(side, value)
        return true
    end
    if type(device.setAnalogueOutput) == "function" then
        device.setAnalogueOutput(side, value)
        return true
    end
    return false, "device has no analog output method"
end

local function clearOtherSides(device, outputSide)
    for _, side in ipairs(REDSTONE_SIDES) do
        if side ~= outputSide then
            local ok, err = setAnalog(device, side, 0)
            if not ok then
                return nil, err
            end
        end
    end
    return true
end

local function getAnalog(device, side)
    if type(device.getAnalogOutput) == "function" then
        return device.getAnalogOutput(side)
    end
    if type(device.getAnalogueOutput) == "function" then
        return device.getAnalogueOutput(side)
    end
    return nil, "device has no analog input readback method"
end

local function setExactTarget(state, exact)
    local lower = math.floor(exact)
    local upper = math.ceil(exact)
    state.exactOutput = exact
    state.lower = lower
    state.upper = upper
    state.fraction = exact - lower
end

local function nextPwmOutput(state)
    if state.lower == state.upper or state.fraction <= 0 then
        state.accumulator = 0
        return state.lower
    end

    if state.fraction >= 1 then
        state.accumulator = 0
        return state.upper
    end

    state.accumulator = state.accumulator + state.fraction
    if state.accumulator + EPSILON >= 1 then
        state.accumulator = state.accumulator - 1
        if math.abs(state.accumulator) < EPSILON then
            state.accumulator = 0
        end
        return state.upper
    end

    return state.lower
end

function M.names(cfg)
    local names = {}
    local seen = {}

    for _, name in ipairs(cfg.actuatorOrder or {}) do
        local spec = cfg.actuators and cfg.actuators[name]
        if type(spec) == "table" and spec.enabled ~= false then
            names[#names + 1] = name
            seen[name] = true
        end
    end

    for name, spec in pairs(cfg.actuators or {}) do
        if not seen[name] and type(spec) == "table" and spec.enabled ~= false then
            names[#names + 1] = name
        end
    end

    return names
end

function M.setOutput(cfg, name, command)
    local spec = cfg.actuators and cfg.actuators[name]
    if type(spec) ~= "table" then
        return nil, "unknown actuator [" .. tostring(name) .. "]"
    end

    local value = tonumber(command)
    if value == nil then
        return nil, "invalid command"
    end

    local state = getState(name)
    local scale = tonumber(spec.scale) or 1
    local bias = tonumber(spec.bias) or 0
    local exact = clamp(value * scale + bias, tonumber(spec.outputMin), tonumber(spec.outputMax))

    state.command = value
    setExactTarget(state, exact)

    return M.update(cfg, name, true)
end

function M.update(cfg, name, force)
    local spec = cfg.actuators and cfg.actuators[name]
    if type(spec) ~= "table" or spec.enabled == false then
        return nil, "actuator disabled or missing"
    end

    local device, err, address = wrap(spec)
    if not device then
        return nil, err
    end

    local state = getState(name)
    local timestamp = now()
    local period = pwmPeriod(spec, cfg)
    if not force and state.initialized and timestamp - state.lastUpdate < period then
        return {
            name = name,
            command = state.command,
            output = state.output,
            exactOutput = state.exactOutput,
            skipped = true
        }
    end

    local output
    if pwmEnabled(spec, cfg) then
        output = nextPwmOutput(state)
    else
        output = math.floor(state.exactOutput + 0.5)
        state.accumulator = 0
    end

    output = clamp(output, tonumber(spec.outputMin), tonumber(spec.outputMax))
    local outputSide = spec.outputSide or "left"
    if spec.clearOtherSides == true then
        local clearOk, clearErr = clearOtherSides(device, outputSide)
        if not clearOk then
            return nil, clearErr
        end
    end

    local ok, setErr = setAnalog(device, outputSide, output)
    if not ok then
        return nil, setErr
    end

    state.output = output
    state.lastUpdate = timestamp
    state.initialized = true

    return {
        name = name,
        address = address,
        command = state.command,
        output = output,
        exactOutput = state.exactOutput,
        lowerOutput = state.lower,
        upperOutput = state.upper,
        pwmFraction = state.fraction,
        pwmAccumulator = state.accumulator,
        pwmPeriod = period
    }
end

function M.updateAll(cfg, force)
    local result = { order = {}, t = now() }
    for _, name in ipairs(M.names(cfg)) do
        result.order[#result.order + 1] = name
        local value, err = M.update(cfg, name, force)
        if value then
            result[name] = value.output
            result[name .. "Command"] = value.command
            result[name .. "ExactOutput"] = value.exactOutput
        else
            result[name] = nil
            result[name .. "Err"] = err
        end
    end
    return result
end

function M.runPwm(cfg, options)
    options = options or {}
    local period = tonumber(options.period)
    if period == nil then
        period = tonumber(cfg.actuatorPwm and cfg.actuatorPwm.period) or 0.05
    end
    if period <= 0 then
        period = 0.05
    end

    while true do
        M.updateAll(cfg)
        sleep(period)
    end
end

function M.readAll(cfg)
    local result = { order = {}, t = now() }
    for _, name in ipairs(M.names(cfg)) do
        result.order[#result.order + 1] = name
        local spec = cfg.actuators[name]
        local device, err, address = wrap(spec)
        if device then
            local value, readErr = getAnalog(device, spec.outputSide or "left")
            local state = getState(name)
            result[name] = value
            result[name .. "Address"] = address
            result[name .. "Command"] = state.command
            result[name .. "ExactOutput"] = state.exactOutput
            if readErr then
                result[name .. "Err"] = readErr
            end
        else
            result[name] = nil
            result[name .. "Err"] = err
        end
    end
    return result
end

function M.stopAll(cfg)
    local result = {}
    for _, name in ipairs(M.names(cfg)) do
        local spec = cfg.actuators[name]
        local failsafe = tonumber(spec.failsafe) or 0
        result[name] = M.setOutput(cfg, name, failsafe)
    end
    return result
end

return M
