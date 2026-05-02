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

local cfg = loadFirst({ "altitude_controller/config.lua", "config.lua" })
local client = loadFirst({ "altitude_controller/client.lua", "client.lua" })

local args = { ... }
if tonumber(args[1]) then
    cfg.hubID = tonumber(args[1])
end

local command = tonumber(args[2]) or tonumber(cfg.linkTest and cfg.linkTest.command) or 7.5
local seconds = tonumber(args[3]) or tonumber(cfg.linkTest and cfg.linkTest.seconds) or 10
local period = tonumber(args[4]) or tonumber(cfg.linkTest and cfg.linkTest.period) or 0.5

local altitudeName = cfg.sensors and cfg.sensors.altitude or "Altitude"
local speedName = cfg.sensors and cfg.sensors.verticalSpeed or "VerticalSpeed"
local actuatorName = cfg.actuator and cfg.actuator.steamVent or "SteamVent"

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

local function fmt(value)
    if value == nil then
        return "nil"
    end
    if type(value) == "number" then
        return string.format("%.3f", value)
    end
    return tostring(value)
end

local function printSnapshot(prefix, snap)
    local sensors = snap and snap.sensors or {}
    local actuators = snap and snap.actuators or {}
    printf(
        "%s alt=%s vs=%s out=%s cmd=%s exact=%s sensorErr=%s/%s actErr=%s",
        prefix,
        fmt(sensors[altitudeName]),
        fmt(sensors[speedName]),
        fmt(actuators[actuatorName]),
        fmt(actuators[actuatorName .. "Command"]),
        fmt(actuators[actuatorName .. "ExactOutput"]),
        tostring(sensors[altitudeName .. "Err"]),
        tostring(sensors[speedName .. "Err"]),
        tostring(actuators[actuatorName .. "Err"])
    )
end

local function fail(message)
    print("ERR: " .. tostring(message))
    print("Usage:")
    print("  test_iohub.lua <hubID> [command] [seconds] [period]")
    print("Example:")
    print("  test_iohub.lua 12 7.5 10 0.5")
end

if tonumber(cfg.hubID) == nil or tonumber(cfg.hubID) <= 0 then
    fail("missing IO Hub computer ID")
    return
end

print("Altitude Controller IO Hub link test")
printf("hubID=%s modem=%s protocol=%s", tostring(cfg.hubID), tostring(cfg.modemSide), tostring(cfg.protocol))
printf("read %s/%s, write %s=%s for %.2fs", altitudeName, speedName, actuatorName, fmt(command), seconds)

local ok, err = client.ping(cfg)
if not ok then
    fail(err)
    return
end
print("ping=" .. tostring(ok))

local snap, snapErr = client.snapshot(cfg)
if not snap then
    fail(snapErr)
    return
end
printSnapshot("before", snap)

local written, writeErr = client.writeActuator(cfg, actuatorName, command)
if not written then
    fail(writeErr)
    return
end
printf("write-ok output=%s exact=%s", fmt(written.output), fmt(written.exactOutput))

local runOk, runErr = pcall(function()
    local ticks = math.max(1, math.floor(seconds / period + 0.5))
    for i = 1, ticks do
        local loopSnap, loopErr = client.snapshot(cfg)
        if not loopSnap then
            error(loopErr)
        end
        printSnapshot(string.format("tick=%03d", i), loopSnap)
        sleep(period)
    end
end)

if cfg.linkTest == nil or cfg.linkTest.stopAfter ~= false then
    local stopped, stopErr = client.stopAll(cfg)
    if not stopped then
        print("STOP ERR: " .. tostring(stopErr))
    else
        print("stop-ok")
    end
end

if not runOk then
    fail(runErr)
    return
end

print("link test finished")
