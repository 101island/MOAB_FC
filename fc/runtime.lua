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

local client = loadFirst({ "fc/client.lua", "client.lua" })
local pid = loadFirst({ "fc/pid.lua", "pid.lua" })

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
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

local function sensorName(cfg)
    return cfg.sensors and cfg.sensors.forwardSpeed or "ForwardSpeed"
end

local function leftName(cfg)
    return cfg.actuators and cfg.actuators.leftMain or "MainThrusterLeft"
end

local function rightName(cfg)
    return cfg.actuators and cfg.actuators.rightMain or "MainThrusterRight"
end

local function tuningPath()
    if type(fs) == "table" and type(fs.exists) == "function" and fs.exists("fc") then
        if type(fs.isDir) ~= "function" or fs.isDir("fc") then
            return "fc/tuning.lua"
        end
    end
    return "fc_tuning.lua"
end

local function orderedKeys(map)
    local keys = {}
    for key in pairs(map or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

local function quote(value)
    return string.format("%q", tostring(value))
end

local function isArray(value)
    local max = 0
    local count = 0
    for key in pairs(value or {}) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false, 0 end
        if key > max then max = key end
        count = count + 1
    end
    return max == count, max
end

local function serialize(value, indent)
    indent = indent or 0
    local kind = type(value)
    if kind == "number" or kind == "boolean" then return tostring(value) end
    if kind == "string" then return quote(value) end
    if kind ~= "table" then return "nil" end

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
            local keyText = tostring(key)
            if type(key) ~= "string" or not key:match("^[%a_][%w_]*$") then
                keyText = "[" .. serialize(key, 0) .. "]"
            end
            lines[#lines + 1] = childPad .. keyText .. " = " .. serialize(value[key], indent + 4) .. ","
        end
    end
    lines[#lines + 1] = pad .. "}"
    return table.concat(lines, "\n")
end

local function pidTuning(p)
    local out = {
        kp = p.kp,
        ki = p.ki,
        kd = p.kd,
        bias = p.bias,
        integralMin = p.integralMin,
        integralMax = p.integralMax,
        integralZone = p.integralZone,
        integralLeak = p.integralLeak,
        resetIntegralOnErrorSignChange = p.resetIntegralOnErrorSignChange
    }
    if p.outputMin ~= nil then out.outputMin = p.outputMin end
    if p.outputMax ~= nil then out.outputMax = p.outputMax end
    return out
end

local function applyPidTuning(p, tuning)
    if type(p) ~= "table" or type(tuning) ~= "table" then return end
    local numericKeys = {
        "kp", "ki", "kd", "bias", "outputMin", "outputMax",
        "integralMin", "integralMax", "integralZone", "integralLeak"
    }
    for _, key in ipairs(numericKeys) do
        if tuning[key] ~= nil then p[key] = tonumber(tuning[key]) end
    end
    if tuning.resetIntegralOnErrorSignChange ~= nil then
        p.resetIntegralOnErrorSignChange = tuning.resetIntegralOnErrorSignChange == true
    end
    pid.reset(p)
end

local function resetPid(state)
    pid.reset(state.forwardPid)
end

local function actuatorMap(state, left, right)
    local values = {}
    values[leftName(state.cfg)] = left
    values[rightName(state.cfg)] = right
    return values
end

local function writeMain(state, left, right)
    return client.writeActuators(state.cfg, actuatorMap(state, left, right))
end

function M.new(cfg, options)
    options = options or {}
    local control = cfg.controller or {}
    local state = {
        cfg = cfg,
        period = tonumber(options.period) or tonumber(control.period) or 0.1,
        enabled = options.enabled,
        targetSpeed = tonumber(options.targetSpeed) or tonumber(control.targetSpeed) or 0,
        turnCommand = tonumber(options.turnCommand) or tonumber(control.turnCommand) or 0,
        speedScale = tonumber(control.speedScale) or 1,
        speedFilterAlpha = clamp(tonumber(control.speedFilterAlpha) or 1, 0, 1),
        outputMin = tonumber(control.outputMin) or -256,
        outputMax = tonumber(control.outputMax) or 256,
        maxStep = tonumber(control.maxStep),
        mixer = {},
        forwardPid = pid.new(control.forwardPid or {}),
        lastTime = nil,
        filteredSpeed = nil,
        lastLeft = nil,
        lastRight = nil,
        pendingWrite = nil,
        pendingLeft = nil,
        pendingRight = nil,
        zeroed = false,
        status = "init",
        lastErr = nil,
        lastSnapshot = nil,
        speed = {},
        output = {}
    }
    if state.enabled == nil then state.enabled = control.enabled == true end
    for key, value in pairs(control.mixer or {}) do state.mixer[key] = value end
    return state
end

function M.setEnabled(state, enabled)
    state.enabled = enabled == true
    resetPid(state)
    state.filteredSpeed = nil
    state.zeroed = false
    state.status = state.enabled and "enabled" or "disabled"
end

function M.adjustTarget(state, delta)
    state.targetSpeed = (tonumber(state.targetSpeed) or 0) + (tonumber(delta) or 0)
    resetPid(state)
    state.status = "target speed"
end

function M.adjustTurn(state, delta)
    state.turnCommand = (tonumber(state.turnCommand) or 0) + (tonumber(delta) or 0)
    state.status = "turn command"
end

function M.centerTurn(state)
    state.turnCommand = 0
    state.status = "turn centered"
end

function M.reset(state)
    resetPid(state)
    state.filteredSpeed = nil
    state.lastLeft = nil
    state.lastRight = nil
    state.pendingWrite = nil
    state.pendingLeft = nil
    state.pendingRight = nil
    state.status = "reset"
end

local function limitStep(state, previous, value)
    local maxStep = tonumber(state.maxStep)
    if maxStep == nil or previous == nil then return value end
    return clamp(value, previous - maxStep, previous + maxStep)
end

local function applyControllerTuning(state, payload)
    local control = payload and (payload.controller or payload)
    if type(control) ~= "table" then return nil, "invalid tuning payload" end
    if control.enabled ~= nil then state.enabled = control.enabled == true end
    if control.targetSpeed ~= nil then state.targetSpeed = tonumber(control.targetSpeed) or state.targetSpeed end
    if control.turnCommand ~= nil then state.turnCommand = tonumber(control.turnCommand) or state.turnCommand end
    if control.speedScale ~= nil then state.speedScale = tonumber(control.speedScale) or state.speedScale end
    if control.speedFilterAlpha ~= nil then
        state.speedFilterAlpha = clamp(tonumber(control.speedFilterAlpha) or state.speedFilterAlpha, 0, 1)
    end
    if control.outputMin ~= nil then state.outputMin = tonumber(control.outputMin) or state.outputMin end
    if control.outputMax ~= nil then state.outputMax = tonumber(control.outputMax) or state.outputMax end
    if control.maxStep ~= nil then state.maxStep = tonumber(control.maxStep) end
    if type(control.mixer) == "table" then
        for key, value in pairs(control.mixer) do state.mixer[key] = value end
    end
    if type(control.forwardPid) == "table" then applyPidTuning(state.forwardPid, control.forwardPid) end
    M.reset(state)
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
    return true, target
end

function M.saveTuning(state, path)
    local target = path or tuningPath()
    local payload = {
        controller = {
            enabled = state.enabled == true,
            targetSpeed = state.targetSpeed,
            turnCommand = state.turnCommand,
            speedScale = state.speedScale,
            speedFilterAlpha = state.speedFilterAlpha,
            outputMin = state.outputMin,
            outputMax = state.outputMax,
            maxStep = state.maxStep,
            mixer = state.mixer,
            forwardPid = pidTuning(state.forwardPid)
        }
    }
    local content = "-- Generated by fc. Hardware config stays in IO Hub fleet_config.lua.\nreturn " ..
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

function M.zeroMain(state)
    local result, err = writeMain(state, 0, 0)
    if result then
        state.lastLeft = 0
        state.lastRight = 0
        state.zeroed = true
    end
    return result, err
end

local function queueMain(state, left, right)
    state.pendingWrite = actuatorMap(state, left, right)
    state.pendingLeft = left
    state.pendingRight = right
end

local function restorePending(state, values, left, right)
    state.pendingWrite = values
    state.pendingLeft = left
    state.pendingRight = right
end

local function writeError(state, writes)
    writes = writes or {}
    return writes[leftName(state.cfg) .. "Err"] or writes[rightName(state.cfg) .. "Err"]
end

function M.step(state)
    local name = sensorName(state.cfg)
    local sentWrite = state.pendingWrite
    local sentLeft = state.pendingLeft
    local sentRight = state.pendingRight
    state.pendingWrite = nil
    state.pendingLeft = nil
    state.pendingRight = nil

    local snap, snapErr = client.exchange(state.cfg, {
        readSensors = { name },
        writeActuators = sentWrite
    })
    local timestamp = now()
    state.lastSnapshot = snap
    if not snap then
        if sentWrite then
            restorePending(state, sentWrite, sentLeft, sentRight)
        elseif state.enabled then
            queueMain(state, 0, 0)
        end
        state.status = tostring(snapErr)
        state.lastErr = snapErr
        return nil, snapErr
    end

    local appliedWriteErr = writeError(state, snap.writes)
    if sentWrite and not appliedWriteErr then
        state.lastLeft = sentLeft
        state.lastRight = sentRight
        state.zeroed = sentLeft == 0 and sentRight == 0
    end

    local sensors = snap.sensors or {}
    local rawSpeed = tonumber(sensors[name])
    local err = sensors[name .. "Err"]
    if rawSpeed == nil or err then
        local msg = err or ("missing forward speed sensor [" .. tostring(name) .. "]")
        state.status = tostring(msg)
        state.lastErr = msg
        if state.enabled then queueMain(state, 0, 0) end
        return nil, msg
    end

    local speed = rawSpeed * state.speedScale
    local alpha = clamp(tonumber(state.speedFilterAlpha) or 1, 0, 1)
    if state.filteredSpeed == nil then
        state.filteredSpeed = speed
    else
        state.filteredSpeed = state.filteredSpeed + alpha * (speed - state.filteredSpeed)
    end
    speed = state.filteredSpeed

    local dt = state.period
    if state.lastTime ~= nil then
        dt = timestamp - state.lastTime
        if dt <= 0 then dt = state.period end
    end
    state.lastTime = timestamp

    local base = 0
    local pidInfo = { error = state.targetSpeed - speed, integral = state.forwardPid.integral, derivative = 0 }
    if state.enabled then
        local value, info = pid.update(state.forwardPid, state.targetSpeed, speed, dt)
        if type(value) ~= "number" then
            state.status = tostring(info)
            state.lastErr = info
            queueMain(state, 0, 0)
            return nil, info
        end
        base = value
        pidInfo = info
    end

    local mixer = state.mixer or {}
    local neutral = tonumber(mixer.neutral) or 0
    local forward = base * (tonumber(mixer.forwardScale) or 1)
    local turn = (tonumber(state.turnCommand) or 0) * (tonumber(mixer.turnScale) or 1)
    local left = neutral + forward + turn * (tonumber(mixer.leftTurnSign) or -1)
    local right = neutral + forward + turn * (tonumber(mixer.rightTurnSign) or 1)
    left = limitStep(state, state.lastLeft, clamp(left, state.outputMin, state.outputMax))
    right = limitStep(state, state.lastRight, clamp(right, state.outputMin, state.outputMax))

    local writeResult = snap.writes
    local writeErr = appliedWriteErr
    if state.enabled then
        queueMain(state, left, right)
        state.zeroed = false
    elseif not state.zeroed then
        queueMain(state, 0, 0)
        left, right = 0, 0
    else
        left, right = 0, 0
    end

    state.speed = {
        current = speed,
        raw = rawSpeed,
        target = state.targetSpeed,
        error = state.targetSpeed - speed,
        pid = pidInfo
    }
    state.output = {
        base = base,
        turn = turn,
        left = left,
        right = right,
        write = writeResult,
        writeErr = writeErr
    }
    state.status = writeErr or (state.enabled and "ok" or "disabled")
    state.lastErr = writeErr
    return state
end

function M.summary(state)
    return string.format(
        "FWD %s v=%.2f>%.2f err=%.2f base=%.1f turn=%.1f L=%.1f R=%.1f %s",
        state.enabled and "ON" or "OFF",
        tonumber(state.speed.current) or 0,
        tonumber(state.speed.target) or 0,
        tonumber(state.speed.error) or 0,
        tonumber(state.output.base) or 0,
        tonumber(state.output.turn) or 0,
        tonumber(state.output.left) or 0,
        tonumber(state.output.right) or 0,
        tostring(state.status)
    )
end

return M
