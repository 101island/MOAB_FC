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

local sensors = loadFirst({ "sensors.lua", "io_hub/sensors.lua" })
local actuators = loadFirst({ "actuators.lua", "io_hub/actuators.lua" })

local M = {}

local state = {
    sensors = { order = {} },
    actuators = { order = {} },
    lastSnapshotAt = 0
}

local function now()
    if os and type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    if os and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

function M.readSensors(cfg)
    state.sensors = sensors.readAll(cfg)
    return state.sensors
end

function M.readSensorsSome(cfg, names)
    state.sensors = sensors.readSome(cfg, names)
    return state.sensors
end

function M.readActuators(cfg)
    state.actuators = actuators.readAll(cfg)
    return state.actuators
end

function M.readActuatorsSome(cfg, names)
    state.actuators = actuators.readSome(cfg, names)
    return state.actuators
end

function M.readActuatorsCached(cfg, names)
    state.actuators = actuators.cached(cfg, names)
    return state.actuators
end

function M.updateActuators(cfg, force)
    state.actuators = actuators.updateAll(cfg, force)
    return state.actuators
end

function M.updatePwmActuators(cfg, force)
    state.actuators = actuators.updatePwm(cfg, force)
    return state.actuators
end

function M.writeActuator(cfg, name, value)
    local result, err = actuators.setOutput(cfg, name, value)
    if result then
        state.actuators = actuators.toResultMap(cfg, { [name] = result })
    end
    return result, err
end

function M.writeActuators(cfg, values)
    local result = {}
    for name, value in pairs(values or {}) do
        local written, err = actuators.setOutput(cfg, name, value)
        result[name] = written
        if err then
            result[name .. "Err"] = err
        end
    end
    state.actuators = actuators.toResultMap(cfg, result)
    return result
end

function M.stopAll(cfg)
    local result = actuators.stopAll(cfg)
    state.actuators = actuators.toResultMap(cfg, result)
    return result
end

function M.snapshot(cfg)
    M.readSensors(cfg)
    M.readActuators(cfg)
    state.lastSnapshotAt = now()
    return {
        t = state.lastSnapshotAt,
        sensors = state.sensors,
        actuators = state.actuators
    }
end

function M.snapshotSome(cfg, sensorNames, actuatorNames)
    local timestamp = now()
    local sensorResult = M.readSensorsSome(cfg, sensorNames or {})
    local actuatorResult = M.readActuatorsCached(cfg, actuatorNames or {})
    state.lastSnapshotAt = timestamp
    return {
        t = timestamp,
        sensors = sensorResult,
        actuators = actuatorResult
    }
end

function M.exchange(cfg, request)
    request = request or {}
    local writeResult = nil
    if type(request.writeActuators) == "table" then
        writeResult = M.writeActuators(cfg, request.writeActuators)
    elseif request.writeActuatorName ~= nil then
        local written, err = M.writeActuator(cfg, request.writeActuatorName, request.writeActuatorValue)
        writeResult = { [request.writeActuatorName] = written }
        if err then
            writeResult[request.writeActuatorName .. "Err"] = err
        end
    end

    local snapshot = M.snapshotSome(
        cfg,
        request.readSensors or request.sensors or {},
        request.readActuators or request.actuators or {}
    )
    snapshot.writes = writeResult or {}
    return snapshot
end

return M
