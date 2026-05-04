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

local cfg = loadFirst(modulePaths("config.lua"))
local client = loadFirst(modulePaths("client.lua"))

local args = { ... }
if tonumber(args[1]) then
    cfg.hubID = tonumber(args[1])
end

local command = tonumber(args[2]) or 16
local seconds = tonumber(args[3]) or 4
local period = tonumber(args[4]) or 0.5

local pitchName = cfg.sensors and cfg.sensors.pitch or "GimbalZAngle"
local rollName = cfg.sensors and cfg.sensors.roll or "GimbalXAngle"
local a = cfg.actuators or {}
local actuatorOrder = {
    a.tailLeft or "PropTailLeft",
    a.tailRight or "PropTailRight",
    a.noseLeft or "PropNoseLeft",
    a.noseRight or "PropNoseRight"
}

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

local function fmt(value)
    if value == nil then return "nil" end
    if type(value) == "number" then return string.format("%.3f", value) end
    return tostring(value)
end

local function zeroMap()
    local values = {}
    for _, name in ipairs(actuatorOrder) do
        values[name] = 0
    end
    return values
end

local function fail(message)
    print("ERR: " .. tostring(message))
    print("Usage:")
    print("  test_iohub.lua <hubID> [command] [seconds] [period]")
    print("Example:")
    print("  test_iohub.lua 65 16 4 0.5")
end

local function printSnapshot(prefix, snap)
    local sensors = snap and snap.sensors or {}
    local actuators = snap and snap.actuators or {}
    printf("%s pitch=%s roll=%s", prefix, fmt(sensors[pitchName]), fmt(sensors[rollName]))
    for _, name in ipairs(actuatorOrder) do
        printf("  %s out=%s cmd=%s exact=%s err=%s",
            name,
            fmt(actuators[name]),
            fmt(actuators[name .. "Command"]),
            fmt(actuators[name .. "ExactOutput"]),
            tostring(actuators[name .. "Err"]))
    end
end

if tonumber(cfg.hubID) == nil or tonumber(cfg.hubID) <= 0 then
    fail("missing IO Hub computer ID")
    return
end

print("Attitude SAS IO Hub link test")
printf("hubID=%s modem=%s protocol=%s", tostring(cfg.hubID), tostring(cfg.modemSide), tostring(cfg.protocol))

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

local values = {
    [actuatorOrder[1]] = command,
    [actuatorOrder[2]] = command,
    [actuatorOrder[3]] = command,
    [actuatorOrder[4]] = command
}

local written, writeErr = client.writeActuators(cfg, values)
if not written then
    fail(writeErr)
    return
end
print("write-ok all props=" .. fmt(command))

local runOk, runErr = pcall(function()
    local ticks = math.max(1, math.floor(seconds / period + 0.5))
    for i = 1, ticks do
        local loopSnap, loopErr = client.snapshot(cfg)
        if not loopSnap then error(loopErr) end
        printSnapshot(string.format("tick=%03d", i), loopSnap)
        sleep(period)
    end
end)

local stopped, stopErr = client.writeActuators(cfg, zeroMap())
if not stopped then
    print("ZERO ERR: " .. tostring(stopErr))
else
    print("zero-ok")
end

if not runOk then
    fail(runErr)
    return
end

print("link test finished")
