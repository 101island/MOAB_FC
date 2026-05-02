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

local cfg = loadFirst({ "io_hub/fleet_config.lua", "fleet_config.lua" })
local hal = loadFirst({ "io_hub/hal.lua", "hal.lua" })
local rednetUtil = loadFirst({ "io_hub/rednet_util.lua", "common/rednet_util.lua", "rednet_util.lua" })

local function reply(sender, ok, result, err)
    rednet.send(sender, {
        type = "reply",
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
        reply(sender, true, "pong")
    elseif msg.type == "get_config" then
        reply(sender, true, cfg)
    elseif msg.type == "get_snapshot" then
        reply(sender, true, hal.snapshot(cfg))
    elseif msg.type == "read_sensors" then
        reply(sender, true, hal.readSensors(cfg))
    elseif msg.type == "read_actuators" then
        reply(sender, true, hal.readActuators(cfg))
    elseif msg.type == "write_actuator" then
        local result, err = hal.writeActuator(cfg, msg.name, msg.value)
        reply(sender, result ~= nil, result, err)
    elseif msg.type == "write_actuators" then
        reply(sender, true, hal.writeActuators(cfg, msg.values))
    elseif msg.type == "stop_all" then
        reply(sender, true, hal.stopAll(cfg))
    else
        reply(sender, false, nil, "unknown request type [" .. tostring(msg.type) .. "]")
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

local function rpcLoop()
    while true do
        local sender, msg = rednet.receive(cfg.protocol)
        local ok, err = pcall(handle, sender, msg)
        if not ok then
            reply(sender, false, nil, err)
        end
    end
end

local function pwmLoop()
    local period = tonumber(cfg.actuatorPwm and cfg.actuatorPwm.period) or 0.05
    if period <= 0 then
        period = 0.05
    end

    while true do
        hal.updateActuators(cfg, false)
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
                reply(sender, false, nil, err)
            end
        end

        hal.updateActuators(cfg, false)
    end
end
