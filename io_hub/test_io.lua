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

local args = { ... }
local mode = args[1] or "all"

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

local function printTableValues(tbl)
    for _, name in ipairs(tbl.order or {}) do
        local value = tbl[name]
        local err = tbl[name .. "Err"]
        if err then
            printf("%s = nil  ERR: %s", name, tostring(err))
        else
            printf("%s = %s", name, tostring(value))
        end
    end
end

local function sampleSensors(period, count)
    period = tonumber(period) or tonumber(cfg.samplePeriod) or 0.1
    count = tonumber(count) or 20
    for _ = 1, count do
        printTableValues(hal.readSensors(cfg))
        print("---")
        sleep(period)
    end
end

local function sampleAll(period, count)
    period = tonumber(period) or tonumber(cfg.samplePeriod) or 0.1
    count = tonumber(count) or 20
    for _ = 1, count do
        local snap = hal.snapshot(cfg)
        print("sensors:")
        printTableValues(snap.sensors)
        print("actuators:")
        printTableValues(snap.actuators)
        print("---")
        sleep(period)
        hal.updateActuators(cfg)
    end
end

local function setActuator(name, value, seconds)
    seconds = tonumber(seconds) or 1
    local period = tonumber(cfg.actuatorPwm and cfg.actuatorPwm.period) or 0.05
    local ticks = math.max(1, math.floor(seconds / period + 0.5))
    local printEvery = math.max(1, math.floor(0.5 / period + 0.5))
    local result, err = hal.writeActuator(cfg, name, value)
    if not result then
        print("ERR: " .. tostring(err))
        return
    end

    printf("%s command=%s output=%s exact=%s", name, tostring(value), tostring(result.output), tostring(result.exactOutput))
    for i = 1, ticks do
        hal.updateActuators(cfg)
        if i == 1 or i == ticks or i % printEvery == 0 then
            local values = hal.readActuators(cfg)
            printf("tick=%03d read=%s command=%s exact=%s err=%s",
                i,
                tostring(values[name]),
                tostring(values[name .. "Command"]),
                tostring(values[name .. "ExactOutput"]),
                tostring(values[name .. "Err"]))
        end
        sleep(period)
    end
end

local function sweep(name, fromValue, toValue, step, hold)
    fromValue = tonumber(fromValue) or 0
    toValue = tonumber(toValue) or 15
    step = tonumber(step) or 1
    hold = tonumber(hold) or 0.5

    local value = fromValue
    while value <= toValue do
        setActuator(name, value, hold)
        value = value + step
    end
end

if mode == "sensors" then
    sampleSensors(args[2], args[3])
elseif mode == "actuator" then
    setActuator(args[2] or "SteamVent", args[3] or 0, args[4] or 1)
elseif mode == "sweep" then
    sweep(args[2] or "SteamVent", args[3], args[4], args[5], args[6])
elseif mode == "stop" then
    hal.stopAll(cfg)
    print("all actuators stopped")
else
    sampleAll(args[2], args[3])
end
