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

local function runningDir()
    if type(shell) == "table" and type(shell.getRunningProgram) == "function" and
        type(fs) == "table" and type(fs.getDir) == "function" then
        local dir = fs.getDir(shell.getRunningProgram() or "")
        if dir and dir ~= "." then return dir end
    end
    return ""
end

local function joinPath(dir, name)
    if dir == nil or dir == "" then return name end
    if type(fs) == "table" and type(fs.combine) == "function" then
        return fs.combine(dir, name)
    end
    return dir .. "/" .. name
end

local function modulePaths(name)
    local path = joinPath(runningDir(), name)
    if path == name then return { name } end
    return { path, name }
end

local client = loadFirst(modulePaths("client.lua"))
local pid = loadFirst(modulePaths("pid.lua"))

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

local function pitchName(cfg)
    return cfg.sensors and cfg.sensors.pitch or "GimbalZAngle"
end

local function rollName(cfg)
    return cfg.sensors and cfg.sensors.roll or "GimbalXAngle"
end

local function actuatorNames(cfg)
    local a = cfg.actuators or {}
    return {
        a.tailLeft or "PropTailLeft",
        a.tailRight or "PropTailRight",
        a.noseLeft or "PropNoseLeft",
        a.noseRight or "PropNoseRight"
    }
end

local function availableNames(values)
    local names = {}
    if type(values) ~= "table" then
        return "none"
    end
    for _, name in ipairs(values.order or {}) do
        names[#names + 1] = tostring(name)
    end
    if #names == 0 then
        for key in pairs(values) do
            if type(key) == "string" and key ~= "order" and key ~= "t" and not key:find("Err$") then
                names[#names + 1] = key
            end
        end
        table.sort(names)
    end
    if #names == 0 then
        return "none"
    end
    return table.concat(names, ",")
end

local function tuningPath()
    return joinPath(runningDir(), "tuning.lua")
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
    if pidState.outputMin ~= nil then out.outputMin = pidState.outputMin end
    if pidState.outputMax ~= nil then out.outputMax = pidState.outputMax end
    return out
end

local function resetPid(state)
    pid.reset(state.pitchPid)
    pid.reset(state.rollPid)
end

local function applyPidTuning(pidState, tuning)
    if type(pidState) ~= "table" or type(tuning) ~= "table" then
        return
    end
    local numericKeys = {
        "kp", "ki", "kd", "bias", "outputMin", "outputMax",
        "integralMin", "integralMax", "integralZone", "integralLeak"
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

local function mergeControl(state, control)
    if type(control) ~= "table" then
        return nil, "invalid tuning payload"
    end
    if control.pitchEnabled ~= nil then state.pitchEnabled = control.pitchEnabled == true end
    if control.rollEnabled ~= nil then state.rollEnabled = control.rollEnabled == true end
    if control.targetPitch ~= nil then state.targetPitch = tonumber(control.targetPitch) or state.targetPitch end
    if control.targetRoll ~= nil then state.targetRoll = tonumber(control.targetRoll) or state.targetRoll end
    if control.pitchScale ~= nil then state.pitchScale = tonumber(control.pitchScale) or state.pitchScale end
    if control.rollScale ~= nil then state.rollScale = tonumber(control.rollScale) or state.rollScale end
    if control.angleFilterAlpha ~= nil then
        state.angleFilterAlpha = clamp(tonumber(control.angleFilterAlpha) or state.angleFilterAlpha, 0, 1)
    end
    if control.outputMin ~= nil then state.outputMin = tonumber(control.outputMin) or state.outputMin end
    if control.outputMax ~= nil then state.outputMax = tonumber(control.outputMax) or state.outputMax end
    if control.maxStep ~= nil then state.maxStep = tonumber(control.maxStep) end
    if type(control.pitchFeedforward) == "table" then
        for key, value in pairs(control.pitchFeedforward) do
            state.pitchFeedforward[key] = value
        end
    end
    if type(control.mixer) == "table" then
        for key, value in pairs(control.mixer) do
            state.mixer[key] = value
        end
    end
    if type(control.pitchPid) == "table" then applyPidTuning(state.pitchPid, control.pitchPid) end
    if type(control.rollPid) == "table" then applyPidTuning(state.rollPid, control.rollPid) end
    resetPid(state)
    state.filteredPitch = nil
    state.filteredRoll = nil
    state.status = "loaded tuning"
    state.lastErr = nil
    return true
end

function M.new(cfg, options)
    options = options or {}
    local control = cfg.controller or {}
    local state = {
        cfg = cfg,
        period = tonumber(options.period) or tonumber(control.period) or 0.1,
        pitchEnabled = options.pitchEnabled,
        rollEnabled = options.rollEnabled,
        targetPitch = tonumber(options.targetPitch) or tonumber(control.targetPitch) or 0,
        targetRoll = tonumber(options.targetRoll) or tonumber(control.targetRoll) or 0,
        pitchScale = tonumber(control.pitchScale) or 1,
        rollScale = tonumber(control.rollScale) or 1,
        angleFilterAlpha = clamp(tonumber(control.angleFilterAlpha) or 1, 0, 1),
        outputMin = tonumber(control.outputMin) or -128,
        outputMax = tonumber(control.outputMax) or 128,
        maxStep = tonumber(control.maxStep),
        pitchFeedforward = {},
        mixer = {},
        pitchPid = pid.new(control.pitchPid or {}),
        rollPid = pid.new(control.rollPid or {}),
        lastTime = nil,
        filteredPitch = nil,
        filteredRoll = nil,
        lastOutputs = {},
        pendingWrite = nil,
        pendingCommands = nil,
        zeroed = false,
        lastSnapshot = nil,
        hubConfig = nil,
        status = "init",
        lastErr = nil,
        pitch = {},
        roll = {},
        output = { commands = {} },
        history = {
            max = tonumber(cfg.display and cfg.display.historyMax) or 160,
            samples = {}
        }
    }
    if state.pitchEnabled == nil then state.pitchEnabled = control.pitchEnabled == true end
    if state.rollEnabled == nil then state.rollEnabled = control.rollEnabled == true end
    for key, value in pairs(control.pitchFeedforward or {}) do state.pitchFeedforward[key] = value end
    for key, value in pairs(control.mixer or {}) do state.mixer[key] = value end
    return state
end

local function propZeroMap(cfg)
    local values = {}
    for _, name in ipairs(actuatorNames(cfg)) do
        values[name] = 0
    end
    return values
end

local function writeProps(state, values)
    return client.writeActuators(state.cfg, values)
end

function M.zeroProps(state)
    local result, err = writeProps(state, propZeroMap(state.cfg))
    if result then
        state.lastOutputs = {}
        state.zeroed = true
    end
    return result, err
end

function M.setPitchEnabled(state, enabled)
    state.pitchEnabled = enabled == true
    pid.reset(state.pitchPid)
    state.status = state.pitchEnabled and "pitch enabled" or "pitch disabled"
    state.zeroed = false
end

function M.setRollEnabled(state, enabled)
    state.rollEnabled = enabled == true
    pid.reset(state.rollPid)
    state.status = state.rollEnabled and "roll enabled" or "roll disabled"
    state.zeroed = false
end

function M.reset(state)
    resetPid(state)
    state.filteredPitch = nil
    state.filteredRoll = nil
    state.lastOutputs = {}
    state.pendingWrite = nil
    state.pendingCommands = nil
    if type(state.history) == "table" then
        state.history.samples = {}
    end
    state.status = "reset"
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
    local control = payload and (payload.controller or payload)
    local applied, err = mergeControl(state, control)
    if not applied then
        state.status = "load failed"
        state.lastErr = err
        return nil, err
    end
    state.status = "loaded " .. target
    return true, target
end

function M.saveTuning(state, path)
    local target = path or tuningPath()
    local payload = {
        controller = {
            pitchEnabled = state.pitchEnabled == true,
            rollEnabled = state.rollEnabled == true,
            targetPitch = state.targetPitch,
            targetRoll = state.targetRoll,
            pitchScale = state.pitchScale,
            rollScale = state.rollScale,
            angleFilterAlpha = state.angleFilterAlpha,
            outputMin = state.outputMin,
            outputMax = state.outputMax,
            maxStep = state.maxStep,
            pitchFeedforward = state.pitchFeedforward,
            mixer = state.mixer,
            pitchPid = pidTuning(state.pitchPid),
            rollPid = pidTuning(state.rollPid)
        }
    }
    local content = "-- Generated by attitude_sas. Hardware config stays in IO Hub fleet_config.lua.\nreturn " ..
        serialize(payload, 0) .. "\n"
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

local function ensureHubConfig(state)
    if state.hubConfig ~= nil then
        return state.hubConfig
    end
    local cfg, err = client.getConfig(state.cfg)
    if not cfg then
        return nil, err
    end
    state.hubConfig = cfg
    return cfg
end

local function effects(state, name)
    local cfg, err = ensureHubConfig(state)
    if not cfg then
        return nil, nil, err
    end
    local spec = cfg.actuators and cfg.actuators[name]
    if type(spec) ~= "table" then
        return nil, nil, "IO Hub actuator missing [" .. tostring(name) .. "]"
    end
    local pitchEffect = tonumber(spec.pitchEffect)
    local rollEffect = tonumber(spec.rollEffect)
    if pitchEffect == nil or rollEffect == nil then
        state.hubConfig = nil
        return nil, nil,
            "IO Hub config lacks pitchEffect/rollEffect for [" .. tostring(name) ..
            "]; update io_hub/fleet_config.lua and restart IO Hub main.lua"
    end
    return pitchEffect, rollEffect
end

local function feedforwardSources(ff)
    local names = {}
    if type(ff.sourceActuators) == "table" then
        for _, name in ipairs(ff.sourceActuators) do
            if type(name) == "string" and name ~= "" then
                names[#names + 1] = name
            end
        end
    elseif type(ff.sourceActuator) == "string" and ff.sourceActuator ~= "" then
        names[#names + 1] = ff.sourceActuator
    end
    if #names == 0 then
        names[#names + 1] = "MainThrusterLeft"
        names[#names + 1] = "MainThrusterRight"
    end
    return names
end

local function actuatorSourceValue(actuators, name)
    if type(actuators) ~= "table" then
        return nil
    end
    return tonumber(actuators[name .. "Command"]) or
        tonumber(actuators[name .. "ExactOutput"]) or
        tonumber(actuators[name])
end

local function feedforward(state, actuators)
    local ff = state.pitchFeedforward or {}
    if ff.enabled == false then
        return 0, 0
    end
    local source = 0
    local count = 0
    for _, name in ipairs(feedforwardSources(ff)) do
        local value = actuatorSourceValue(actuators, name)
        if value ~= nil then
            source = source + value
            count = count + 1
        end
    end
    if count > 0 then
        source = source / count
    end
    local value = (tonumber(ff.bias) or 0) + (tonumber(ff.gain) or 0) * source
    value = clamp(value, tonumber(ff.outputMin), tonumber(ff.outputMax))
    return value, source
end

local function limitStep(state, name, value)
    local maxStep = tonumber(state.maxStep)
    if maxStep == nil then
        return value
    end
    local previous = state.lastOutputs[name]
    if previous == nil then
        return value
    end
    return clamp(value, previous - maxStep, previous + maxStep)
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
        pitch = state.pitch.current,
        pitchTarget = state.pitch.target,
        roll = state.roll.current,
        rollTarget = state.roll.target,
        pitchOutput = state.pitch.command,
        rollOutput = state.roll.command,
        feedforward = state.pitch.feedforward
    }
    local maxSamples = tonumber(history.max) or 160
    while #samples > maxSamples do
        table.remove(samples, 1)
    end
end

local function queueProps(state, values)
    state.pendingWrite = values
    state.pendingCommands = values
end

local function restorePending(state, values, commands)
    state.pendingWrite = values
    state.pendingCommands = commands
end

local function writeError(state, writes)
    writes = writes or {}
    for _, name in ipairs(actuatorNames(state.cfg)) do
        if writes[name .. "Err"] then
            return writes[name .. "Err"]
        end
    end
    return nil
end

function M.step(state)
    local pName = pitchName(state.cfg)
    local rName = rollName(state.cfg)
    local actuatorReads = {}
    local ffConfig = state.pitchFeedforward or {}
    if ffConfig.enabled ~= false then
        for _, name in ipairs(feedforwardSources(ffConfig)) do
            actuatorReads[#actuatorReads + 1] = name
        end
    end

    local sentWrite = state.pendingWrite
    local sentCommands = state.pendingCommands
    state.pendingWrite = nil
    state.pendingCommands = nil

    local snap, snapErr = client.exchange(state.cfg, {
        readSensors = { pName, rName },
        readActuators = actuatorReads,
        writeActuators = sentWrite
    })
    local timestamp = now()
    state.lastSnapshot = snap
    if not snap then
        if sentWrite then
            restorePending(state, sentWrite, sentCommands)
        elseif state.pitchEnabled or state.rollEnabled then
            queueProps(state, propZeroMap(state.cfg))
        end
        state.status = tostring(snapErr)
        state.lastErr = snapErr
        return nil, snapErr
    end

    local appliedWriteErr = writeError(state, snap.writes)
    if sentWrite and not appliedWriteErr then
        state.lastOutputs = {}
        local allZero = true
        for name, value in pairs(sentCommands or sentWrite) do
            state.lastOutputs[name] = value
            if value ~= 0 then allZero = false end
        end
        state.zeroed = allZero
    end

    local dt = state.period
    if state.lastTime ~= nil then
        dt = timestamp - state.lastTime
        if dt <= 0 then dt = state.period end
    end
    state.lastTime = timestamp

    local sensors = snap.sensors or {}
    local actuators = snap.actuators or {}
    local rawPitch = tonumber(sensors[pName])
    local rawRoll = tonumber(sensors[rName])
    local sensorErr = sensors[pName .. "Err"] or sensors[rName .. "Err"]
    if rawPitch == nil or rawRoll == nil or sensorErr then
        local err = sensorErr or ("missing pitch/roll sensor; need [" ..
            tostring(pName) .. "," .. tostring(rName) ..
            "], have [" .. availableNames(sensors) .. "]")
        state.status = tostring(err)
        state.lastErr = err
        if state.pitchEnabled or state.rollEnabled then queueProps(state, propZeroMap(state.cfg)) end
        return nil, err
    end

    local pitchAngle = rawPitch * state.pitchScale
    local rollAngle = rawRoll * state.rollScale
    local alpha = clamp(tonumber(state.angleFilterAlpha) or 1, 0, 1)
    if state.filteredPitch == nil then
        state.filteredPitch = pitchAngle
    else
        state.filteredPitch = state.filteredPitch + alpha * (pitchAngle - state.filteredPitch)
    end
    if state.filteredRoll == nil then
        state.filteredRoll = rollAngle
    else
        state.filteredRoll = state.filteredRoll + alpha * (rollAngle - state.filteredRoll)
    end
    pitchAngle = state.filteredPitch
    rollAngle = state.filteredRoll

    local pitchOut = 0
    local rollOut = 0
    local pitchInfo = { error = state.targetPitch - pitchAngle, integral = state.pitchPid.integral, derivative = 0 }
    local rollInfo = { error = state.targetRoll - rollAngle, integral = state.rollPid.integral, derivative = 0 }
    if state.pitchEnabled then
        local value, info = pid.update(state.pitchPid, state.targetPitch, pitchAngle, dt)
        if type(value) ~= "number" then
            state.status = tostring(info)
            state.lastErr = info
            queueProps(state, propZeroMap(state.cfg))
            return nil, info
        end
        pitchOut = value
        pitchInfo = info
    end
    if state.rollEnabled then
        local value, info = pid.update(state.rollPid, state.targetRoll, rollAngle, dt)
        if type(value) ~= "number" then
            state.status = tostring(info)
            state.lastErr = info
            queueProps(state, propZeroMap(state.cfg))
            return nil, info
        end
        rollOut = value
        rollInfo = info
    end

    local ff, ffSource = feedforward(state, actuators)
    local pitchCommand = state.pitchEnabled and (pitchOut + ff) or 0
    local rollCommand = state.rollEnabled and rollOut or 0
    pitchCommand = (tonumber(state.mixer.pitchScale) or 1) * pitchCommand
    rollCommand = (tonumber(state.mixer.rollScale) or 1) * rollCommand
    local neutral = tonumber(state.mixer.neutral) or 0

    local values = {}
    local commands = {}
    for _, name in ipairs(actuatorNames(state.cfg)) do
        local pe, re, effectErr = effects(state, name)
        if not pe then
            state.status = tostring(effectErr)
            state.lastErr = effectErr
            queueProps(state, propZeroMap(state.cfg))
            return nil, effectErr
        end
        local value = neutral + pitchCommand * pe + rollCommand * re
        value = clamp(value, state.outputMin, state.outputMax)
        value = limitStep(state, name, value)
        values[name] = value
        commands[name] = value
    end

    local writeResult = snap.writes
    local writeErr = appliedWriteErr
    if state.pitchEnabled or state.rollEnabled then
        queueProps(state, values)
        state.zeroed = false
    else
        commands = propZeroMap(state.cfg)
        if not state.zeroed then
            queueProps(state, commands)
        end
    end

    state.pitch = {
        current = pitchAngle,
        raw = rawPitch,
        target = state.targetPitch,
        error = state.targetPitch - pitchAngle,
        pidOutput = pitchOut,
        feedforward = ff,
        feedforwardSource = ffSource,
        command = pitchCommand,
        pid = pitchInfo
    }
    state.roll = {
        current = rollAngle,
        raw = rawRoll,
        target = state.targetRoll,
        error = state.targetRoll - rollAngle,
        pidOutput = rollOut,
        command = rollCommand,
        pid = rollInfo
    }
    state.output = {
        commands = commands,
        write = writeResult,
        writeErr = writeErr
    }
    state.status = writeErr or ((state.pitchEnabled or state.rollEnabled) and "ok" or "disabled")
    state.lastErr = writeErr
    pushHistory(state, timestamp)
    return state
end

function M.summary(state)
    return string.format(
        "pitch=%s %.2f/%.2f out=%.2f roll=%s %.2f/%.2f out=%.2f ff=%.2f status=%s",
        tostring(state.pitchEnabled),
        tonumber(state.pitch.current) or 0,
        tonumber(state.pitch.target) or 0,
        tonumber(state.pitch.command) or 0,
        tostring(state.rollEnabled),
        tonumber(state.roll.current) or 0,
        tonumber(state.roll.target) or 0,
        tonumber(state.roll.command) or 0,
        tonumber(state.pitch.feedforward) or 0,
        tostring(state.status)
    )
end

return M
