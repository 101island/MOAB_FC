local function loadFirst(paths)
    for _, path in ipairs(paths) do
        if not fs or fs.exists(path) then
            local ok, mod = pcall(dofile, path)
            if ok then
                return mod
            end
        end
    end
    error("cannot load module: " .. table.concat(paths, ", "))
end

local client = loadFirst({ "altitude_controller/client.lua", "client.lua" })
local pid = loadFirst({ "altitude_controller/pid.lua", "pid.lua" })
local feedforward = loadFirst({ "altitude_controller/feedforward.lua", "feedforward.lua" })

local M = {}

local function now()
    if type(os) == "table" and type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    if type(os) == "table" and type(os.clock) == "function" then
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

local function validMode(value)
    if value == "speed" or value == "feedforward" then
        return value
    end
    return "cascade"
end

local function actuatorName(cfg)
    return cfg.actuator and cfg.actuator.steamVent or "SteamVent"
end

local function altitudeName(cfg)
    return cfg.sensors and cfg.sensors.altitude or "Altitude"
end

local function speedName(cfg)
    return cfg.sensors and cfg.sensors.verticalSpeed or "VerticalSpeed"
end

local function tuningPath()
    if type(fs) == "table" and type(fs.exists) == "function" and fs.exists("altitude_controller") then
        if type(fs.isDir) ~= "function" or fs.isDir("altitude_controller") then
            return "altitude_controller/tuning.lua"
        end
    end
    return "tuning.lua"
end

local function orderedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)
    return keys
end

local function quote(value)
    return string.format("%q", tostring(value))
end

local function isArray(value)
    local max = 0
    local count = 0
    for key in pairs(value or {}) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false, 0
        end
        if key > max then
            max = key
        end
        count = count + 1
    end
    return max == count, max
end

local function serialize(value, indent)
    indent = indent or 0
    local kind = type(value)
    if kind == "number" or kind == "boolean" then
        return tostring(value)
    end
    if kind == "string" then
        return quote(value)
    end
    if kind ~= "table" then
        return "nil"
    end

    local pad = string.rep(" ", indent)
    local childPad = string.rep(" ", indent + 4)
    local array, max = isArray(value)
    local lines = { "{" }
    if array then
        for index = 1, max do
            lines[#lines + 1] = childPad .. serialize(value[index], indent + 4) .. ","
        end
    else
        for _, key in ipairs(orderedKeys(value)) do
            local keyText
            if type(key) == "string" and key:match("^[%a_][%w_]*$") then
                keyText = key
            else
                keyText = "[" .. serialize(key, 0) .. "]"
            end
            lines[#lines + 1] = childPad .. keyText .. " = " .. serialize(value[key], indent + 4) .. ","
        end
    end
    lines[#lines + 1] = pad .. "}"
    return table.concat(lines, "\n")
end

local function pidTuning(pidState)
    local out = {
        kp = pidState.kp,
        ki = pidState.ki,
        kd = pidState.kd,
        bias = pidState.bias,
        integralMin = pidState.integralMin,
        integralMax = pidState.integralMax,
        integralZone = pidState.integralZone,
        integralLeak = pidState.integralLeak,
        resetIntegralOnErrorSignChange = pidState.resetIntegralOnErrorSignChange
    }
    if pidState.outputMin ~= nil then
        out.outputMin = pidState.outputMin
    end
    if pidState.outputMax ~= nil then
        out.outputMax = pidState.outputMax
    end
    return out
end

local function feedforwardLevels(state)
    local levels = {}
    local points = state.feedforward and state.feedforward.points or {}
    for _, point in ipairs(points) do
        levels[#levels + 1] = {
            altitude = point.altitude,
            level = point.level
        }
    end
    return levels
end

local function resetPid(state)
    pid.reset(state.outerPid)
    pid.reset(state.innerPid)
end

function M.new(cfg, options)
    options = options or {}
    local control = cfg.controller or {}
    local targetAltitude = tonumber(options.targetAltitude) or tonumber(control.targetAltitude) or 100

    local state = {
        cfg = cfg,
        enabled = options.enabled
    }
    if state.enabled == nil then
        state.enabled = control.enabled == true
    end

    state.mode = validMode(options.mode or control.mode)
    state.period = tonumber(options.period) or tonumber(control.period) or 0.2
    state.targetAltitude = targetAltitude
    state.manualSpeedTarget = tonumber(options.speedTarget) or tonumber(control.manualSpeedTarget) or 0
    state.pidOutputEnabled = control.pidOutputEnabled ~= false
    state.verticalSpeedScale = tonumber(control.verticalSpeedScale) or 1
    state.speedFilterAlpha = tonumber(control.speedFilterAlpha) or 1
    state.outputMin = tonumber(control.outputMin) or 0
    state.outputMax = tonumber(control.outputMax) or 15
    state.maxStep = tonumber(control.maxStep)
    state.outerPid = pid.new(control.outerPid or {})
    state.innerPid = pid.new(control.innerPid or {})
    state.feedforward = feedforward.new(control.feedforward or {})
    state.lastTime = nil
    state.lastOutput = nil
    state.filteredSpeed = nil
    state.status = "init"
    state.lastSnapshot = nil
    state.lastWrite = nil
    state.lastErr = nil
    state.history = {
        max = tonumber(cfg.display and cfg.display.historyMax) or 160,
        samples = {}
    }
    state.position = {}
    state.speed = {}
    state.output = {}
    return state
end

function M.setEnabled(state, enabled)
    state.enabled = enabled == true
    if not state.enabled then
        resetPid(state)
        state.lastOutput = nil
        local ok, err = client.stopAll(state.cfg)
        state.lastErr = err
        state.status = ok and "disabled" or tostring(err)
    else
        resetPid(state)
        state.lastTime = nil
        state.status = "enabled"
    end
end

function M.adjustTarget(state, delta)
    state.targetAltitude = (tonumber(state.targetAltitude) or 0) + delta
    resetPid(state)
end

function M.adjustManualSpeed(state, delta)
    state.manualSpeedTarget = (tonumber(state.manualSpeedTarget) or 0) + delta
    pid.reset(state.innerPid)
end

function M.cycleMode(state)
    if state.mode == "cascade" then
        state.mode = "speed"
    elseif state.mode == "speed" then
        state.mode = "feedforward"
    else
        state.mode = "cascade"
    end
    resetPid(state)
end

function M.setPidOutputEnabled(state, enabled)
    state.pidOutputEnabled = enabled == true
    resetPid(state)
    state.status = state.pidOutputEnabled and "pid output enabled" or "pid output disabled"
end

local function applyPidTuning(pidState, tuning)
    if type(pidState) ~= "table" or type(tuning) ~= "table" then
        return
    end
    local numericKeys = {
        "kp",
        "ki",
        "kd",
        "bias",
        "outputMin",
        "outputMax",
        "integralMin",
        "integralMax",
        "integralZone",
        "integralLeak"
    }
    for _, key in ipairs(numericKeys) do
        if tuning[key] ~= nil then
            pidState[key] = tonumber(tuning[key])
        end
    end
    if tuning.resetIntegralOnErrorSignChange ~= nil then
        pidState.resetIntegralOnErrorSignChange = tuning.resetIntegralOnErrorSignChange == true
    end
    pid.reset(pidState)
end

local function applyControllerTuning(state, tuning)
    local control = tuning and tuning.controller or tuning
    if type(control) ~= "table" then
        return nil, "invalid tuning payload"
    end

    if control.mode ~= nil then
        state.mode = validMode(control.mode)
    end
    if control.targetAltitude ~= nil then
        state.targetAltitude = tonumber(control.targetAltitude) or state.targetAltitude
    end
    if control.manualSpeedTarget ~= nil then
        state.manualSpeedTarget = tonumber(control.manualSpeedTarget) or state.manualSpeedTarget
    end
    if control.pidOutputEnabled ~= nil then
        state.pidOutputEnabled = control.pidOutputEnabled ~= false
    end
    if control.speedFilterAlpha ~= nil then
        state.speedFilterAlpha = clamp(tonumber(control.speedFilterAlpha) or state.speedFilterAlpha, 0, 1)
    end
    if control.outputMin ~= nil then
        state.outputMin = tonumber(control.outputMin) or state.outputMin
    end
    if control.outputMax ~= nil then
        state.outputMax = tonumber(control.outputMax) or state.outputMax
    end
    if control.maxStep ~= nil then
        state.maxStep = tonumber(control.maxStep)
    end
    if type(control.outerPid) == "table" then
        applyPidTuning(state.outerPid, control.outerPid)
    end
    if type(control.innerPid) == "table" then
        applyPidTuning(state.innerPid, control.innerPid)
    end
    if type(control.feedforward) == "table" then
        state.feedforward = feedforward.new(control.feedforward)
    end

    resetPid(state)
    state.lastOutput = nil
    state.filteredSpeed = nil
    state.status = "loaded tuning"
    state.lastErr = nil
    return true
end

function M.loadTuning(state, path)
    local target = path or tuningPath()
    if type(fs) == "table" and type(fs.exists) == "function" and not fs.exists(target) then
        state.status = "load missing"
        state.lastErr = target .. " not found"
        return nil, state.lastErr
    end

    local ok, payload = pcall(dofile, target)
    if not ok then
        state.status = "load failed"
        state.lastErr = payload
        return nil, payload
    end

    local applied, err = applyControllerTuning(state, payload)
    if not applied then
        state.status = "load failed"
        state.lastErr = err
        return nil, err
    end
    state.status = "loaded " .. target
    state.lastErr = nil
    return true, target
end

function M.saveTuning(state, path)
    local target = path or tuningPath()
    local payload = {
        controller = {
            mode = state.mode,
            targetAltitude = state.targetAltitude,
            manualSpeedTarget = state.manualSpeedTarget,
            pidOutputEnabled = state.pidOutputEnabled,
            speedFilterAlpha = state.speedFilterAlpha,
            outputMin = state.outputMin,
            outputMax = state.outputMax,
            maxStep = state.maxStep,
            outerPid = pidTuning(state.outerPid),
            innerPid = pidTuning(state.innerPid),
            feedforward = {
                enabled = state.feedforward and state.feedforward.enabled ~= false,
                source = state.feedforward and state.feedforward.source or "target",
                outputMin = state.feedforward and state.feedforward.outputMin or 0,
                outputMax = state.feedforward and state.feedforward.outputMax or 15,
                levels = feedforwardLevels(state)
            }
        }
    }
    local content = "-- Generated by altitude_controller. Hardware config stays in config.lua.\nreturn " .. serialize(payload, 0) .. "\n"
    if type(fs) ~= "table" or type(fs.open) ~= "function" then
        state.status = "save failed"
        state.lastErr = "fs API unavailable"
        return nil, state.lastErr
    end
    local handle, err = fs.open(target, "w")
    if not handle then
        state.status = "save failed"
        state.lastErr = err
        return nil, err
    end
    handle.write(content)
    handle.close()
    state.status = "saved " .. target
    state.lastErr = nil
    return true, target
end

function M.reset(state)
    resetPid(state)
    state.lastOutput = nil
    state.filteredSpeed = nil
    if type(state.history) == "table" then
        state.history.samples = {}
    end
    state.status = "reset"
end

local function pushHistory(state, timestamp)
    local history = state.history
    if type(history) ~= "table" then
        return
    end
    if type(history.samples) ~= "table" then
        history.samples = {}
    end

    local samples = history.samples
    samples[#samples + 1] = {
        t = timestamp,
        altitude = state.position.current,
        altitudeTarget = state.position.target,
        speed = state.speed.current,
        speedTarget = state.speed.target,
        output = state.output.command,
        feedforward = state.output.feedforward,
        correction = state.output.correction,
        status = state.status
    }

    local maxSamples = tonumber(history.max) or 160
    while #samples > maxSamples do
        table.remove(samples, 1)
    end
end

function M.step(state)
    local cfg = state.cfg
    local snap, snapErr = client.snapshot(cfg)
    local timestamp = now()
    state.lastSnapshot = snap

    if not snap then
        state.status = tostring(snapErr)
        state.lastErr = snapErr
        if state.enabled then
            client.stopAll(cfg)
        end
        return nil, snapErr
    end

    local dt = state.period
    if state.lastTime ~= nil then
        dt = timestamp - state.lastTime
        if dt <= 0 then
            dt = state.period
        end
    end
    state.lastTime = timestamp

    local sensors = snap.sensors or {}
    local actuators = snap.actuators or {}
    local hName = altitudeName(cfg)
    local vName = speedName(cfg)
    local aName = actuatorName(cfg)

    local altitude = tonumber(sensors[hName])
    local rawSpeed = tonumber(sensors[vName])
    local sensorErr = sensors[hName .. "Err"] or sensors[vName .. "Err"]
    if altitude == nil or rawSpeed == nil or sensorErr then
        local err = sensorErr or "missing altitude/speed"
        state.status = tostring(err)
        state.lastErr = err
        if state.enabled then
            client.stopAll(cfg)
        end
        return nil, err
    end

    local speed = rawSpeed * state.verticalSpeedScale
    local alpha = clamp(tonumber(state.speedFilterAlpha) or 1, 0, 1)
    if state.filteredSpeed == nil then
        state.filteredSpeed = speed
    else
        state.filteredSpeed = state.filteredSpeed + alpha * (speed - state.filteredSpeed)
    end
    speed = state.filteredSpeed

    local speedTarget = state.manualSpeedTarget
    local pidOutputEnabled = state.pidOutputEnabled ~= false
    local outerInfo = { error = state.targetAltitude - altitude, integral = state.outerPid.integral, derivative = 0 }
    if state.mode == "cascade" and pidOutputEnabled then
        local outerOut, outerErr = pid.update(state.outerPid, state.targetAltitude, altitude, dt, -speed)
        if type(outerOut) ~= "number" then
            state.status = tostring(outerErr)
            return nil, outerErr
        end
        speedTarget = outerOut
        outerInfo = outerErr
    elseif state.mode == "feedforward" then
        speedTarget = 0
    end

    local ffAltitude = state.targetAltitude
    local ff, ffErr = feedforward.evaluate(state.feedforward, ffAltitude)
    if not ff then
        ff = { level = 0 }
    end

    local correction = 0
    local innerInfo = { error = speedTarget - speed, integral = state.innerPid.integral, derivative = 0 }
    if state.mode ~= "feedforward" and pidOutputEnabled then
        local innerOut, innerErr = pid.update(state.innerPid, speedTarget, speed, dt)
        if type(innerOut) ~= "number" then
            state.status = tostring(innerErr)
            return nil, innerErr
        end
        correction = innerOut
        innerInfo = innerErr
    end

    local requested = (tonumber(ff.level) or 0) + correction
    local command = clamp(requested, state.outputMin, state.outputMax)
    if state.maxStep ~= nil and state.lastOutput ~= nil then
        command = clamp(command, state.lastOutput - state.maxStep, state.lastOutput + state.maxStep)
    end

    local writeResult = nil
    local writeErr = nil
    if state.enabled then
        writeResult, writeErr = client.writeActuator(cfg, aName, command)
        state.lastOutput = command
    else
        command = 0
        if state.lastOutput ~= 0 then
            client.stopAll(cfg)
            state.lastOutput = 0
        end
    end

    state.position = {
        current = altitude,
        target = state.targetAltitude,
        error = state.targetAltitude - altitude,
        pid = outerInfo
    }
    state.speed = {
        current = speed,
        raw = rawSpeed,
        target = speedTarget,
        error = speedTarget - speed,
        pid = innerInfo
    }
    state.output = {
        command = command,
        requested = requested,
        feedforward = ff.level,
        correction = correction,
        pidOutputEnabled = pidOutputEnabled,
        write = writeResult,
        readback = actuators[aName],
        exact = actuators[aName .. "ExactOutput"],
        writeErr = writeErr,
        feedforwardErr = ffErr
    }
    state.status = writeErr or ffErr or (state.enabled and "ok" or "disabled")
    state.lastErr = writeErr or ffErr
    pushHistory(state, timestamp)
    return state
end

function M.summary(state)
    return string.format(
        "mode=%s pid=%s en=%s alt=%.3f/%.3f vs=%.3f/%.3f ff=%.3f corr=%.3f out=%.3f status=%s",
        tostring(state.mode),
        tostring(state.pidOutputEnabled),
        tostring(state.enabled),
        tonumber(state.position.current) or 0,
        tonumber(state.position.target) or 0,
        tonumber(state.speed.current) or 0,
        tonumber(state.speed.target) or 0,
        tonumber(state.output.feedforward) or 0,
        tonumber(state.output.correction) or 0,
        tonumber(state.output.command) or 0,
        tostring(state.status)
    )
end

return M
