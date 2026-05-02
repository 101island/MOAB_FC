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

function M.new(cfg)
    cfg = cfg or {}
    return {
        kp = tonumber(cfg.kp) or 0,
        ki = tonumber(cfg.ki) or 0,
        kd = tonumber(cfg.kd) or 0,
        bias = tonumber(cfg.bias) or 0,
        outputMin = tonumber(cfg.outputMin),
        outputMax = tonumber(cfg.outputMax),
        integralMin = tonumber(cfg.integralMin),
        integralMax = tonumber(cfg.integralMax),
        integralZone = tonumber(cfg.integralZone),
        integralLeak = tonumber(cfg.integralLeak),
        resetIntegralOnErrorSignChange = cfg.resetIntegralOnErrorSignChange == true,
        integral = 0,
        previousError = nil,
        previousIntegralError = nil
    }
end

function M.reset(state)
    if type(state) ~= "table" then
        return
    end
    state.integral = 0
    state.previousError = nil
    state.previousIntegralError = nil
end

function M.update(state, setpoint, measurement, dt, derivative)
    if type(state) ~= "table" then
        return nil, "missing PID state"
    end

    local elapsed = tonumber(dt)
    local target = tonumber(setpoint)
    local current = tonumber(measurement)
    if elapsed == nil or elapsed <= 0 then
        return nil, "invalid dt"
    end
    if target == nil then
        return nil, "invalid setpoint"
    end
    if current == nil then
        return nil, "invalid measurement"
    end

    local err = target - current
    local shouldIntegrate = true
    if state.integralZone ~= nil and math.abs(err) > state.integralZone then
        shouldIntegrate = false
    end
    if state.resetIntegralOnErrorSignChange and
        state.previousIntegralError ~= nil and
        err * state.previousIntegralError < 0 then
        state.integral = 0
    end

    if shouldIntegrate then
        state.integral = clamp(state.integral + err * elapsed, state.integralMin, state.integralMax)
    else
        local leak = state.integralLeak
        if leak ~= nil and leak >= 0 and leak <= 1 then
            state.integral = state.integral * leak
        end
    end
    state.previousIntegralError = err

    local d = tonumber(derivative)
    if d == nil then
        d = 0
        if state.previousError ~= nil then
            d = (err - state.previousError) / elapsed
        end
    end
    state.previousError = err

    local output = state.bias + state.kp * err + state.ki * state.integral + state.kd * d
    output = clamp(output, state.outputMin, state.outputMax)

    return output, {
        error = err,
        integral = state.integral,
        derivative = d
    }
end

return M
