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

local cfg = loadFirst({ "fleet_config.lua", "io_hub/fleet_config.lua" })
local hal = loadFirst({ "hal.lua", "io_hub/hal.lua" })
local rednetUtil = loadFirst({ "rednet_util.lua", "io_hub/rednet_util.lua", "common/rednet_util.lua" })
local BUILD = "exchange-v2"

local function requestIdOf(msg)
    if type(msg) == "table" then
        return msg.requestId
    end
    return nil
end

local function reply(sender, ok, result, err, requestId)
    rednet.send(sender, {
        type = "reply",
        requestId = requestId,
        ok = ok,
        result = result,
        err = err
    }, cfg.protocol)
end

local function handle(sender, msg)
    if type(msg) ~= "table" then
        reply(sender, false, nil, "message must be a table")
        return
    end

    if msg.type == "ping" then
        reply(sender, true, "pong", nil, msg.requestId)
    elseif msg.type == "get_config" then
        reply(sender, true, cfg, nil, msg.requestId)
    elseif msg.type == "get_snapshot" then
        reply(sender, true, hal.snapshot(cfg), nil, msg.requestId)
    elseif msg.type == "get_snapshot_some" then
        reply(sender, true, hal.snapshotSome(
            cfg,
            msg.sensors or msg.sensorNames or {},
            msg.actuators or msg.actuatorNames or {}
        ), nil, msg.requestId)
    elseif msg.type == "exchange" then
        reply(sender, true, hal.exchange(cfg, msg), nil, msg.requestId)
    elseif msg.type == "read_sensors" then
        reply(sender, true, hal.readSensors(cfg), nil, msg.requestId)
    elseif msg.type == "read_sensors_some" then
        reply(sender, true, hal.readSensorsSome(cfg, msg.names or msg.sensors or {}), nil, msg.requestId)
    elseif msg.type == "read_actuators" then
        reply(sender, true, hal.readActuators(cfg), nil, msg.requestId)
    elseif msg.type == "read_actuators_some" then
        reply(sender, true, hal.readActuatorsSome(cfg, msg.names or msg.actuators or {}), nil, msg.requestId)
    elseif msg.type == "read_actuators_cached" then
        reply(sender, true, hal.readActuatorsCached(cfg, msg.names or msg.actuators or {}), nil, msg.requestId)
    elseif msg.type == "write_actuator" then
        local result, err = hal.writeActuator(cfg, msg.name, msg.value)
        reply(sender, result ~= nil, result, err, msg.requestId)
    elseif msg.type == "write_actuators" then
        reply(sender, true, hal.writeActuators(cfg, msg.values), nil, msg.requestId)
    elseif msg.type == "stop_all" then
        reply(sender, true, hal.stopAll(cfg), nil, msg.requestId)
    else
        reply(sender, false, nil, "unknown request type [" .. tostring(msg.type) .. "]", msg.requestId)
    end
end

if type(rednet) ~= "table" then
    error("rednet API is unavailable")
end

local openedSide, modemErr = rednetUtil.open(cfg.modemSide)
if not openedSide then
    error(modemErr)
end

print("MOAB IO Hub")
print("modem=" .. tostring(openedSide))
print("protocol=" .. tostring(cfg.protocol))
print("rpc=" .. BUILD)

local function rpcLoop()
    while true do
        local sender, msg = rednet.receive(cfg.protocol)
        local ok, err = pcall(handle, sender, msg)
        if not ok then
            reply(sender, false, nil, err, requestIdOf(msg))
        end
    end
end

local function pwmLoop()
    local period = tonumber(cfg.actuatorPwm and cfg.actuatorPwm.period) or 0.05
    if period <= 0 then
        period = 0.05
    end

    while true do
        hal.updatePwmActuators(cfg, false)
        sleep(period)
    end
end

if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
    parallel.waitForAny(rpcLoop, pwmLoop)
else
    while true do
        local timeout = tonumber(cfg.actuatorPwm and cfg.actuatorPwm.period) or 0.05
        local sender, msg = rednet.receive(cfg.protocol, timeout)
        if sender then
            local ok, err = pcall(handle, sender, msg)
            if not ok then
                reply(sender, false, nil, err, requestIdOf(msg))
            end
        end

        hal.updatePwmActuators(cfg, false)
    end
end
