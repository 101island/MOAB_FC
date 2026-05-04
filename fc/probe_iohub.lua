local function loadFirst(paths)
    for _, path in ipairs(paths) do
        if not fs or fs.exists(path) then
            local ok, mod = pcall(dofile, path)
            if ok then return mod end
        end
    end
    error("cannot load module: " .. table.concat(paths, ", "))
end

local cfg = loadFirst({ "fc/config.lua", "config.lua" })
local client = loadFirst({ "fc/client.lua", "client.lua" })

local args = { ... }
local hubID = tonumber(args[1])
if hubID then cfg.hubID = hubID end

print("FC IO Hub probe")
print("hubID=" .. tostring(cfg.hubID))
print("protocol=" .. tostring(cfg.protocol))

local side, openErr = client.open(cfg)
if not side then
    print("OPEN ERR: " .. tostring(openErr))
    return
end
print("modem=" .. tostring(side))

local pong, pingErr = client.ping(cfg)
if not pong then
    print("PING ERR: " .. tostring(pingErr))
    print("Check IO Hub computer is running main.lua")
    print("Check same protocol and wired modem network")
    return
end
print("ping=" .. tostring(pong))

local snap, snapErr = client.snapshot(cfg)
if not snap then
    print("SNAP ERR: " .. tostring(snapErr))
    return
end

local sensors = snap.sensors or {}
local actuators = snap.actuators or {}
local fwd = cfg.sensors and cfg.sensors.forwardSpeed or "ForwardSpeed"
local left = cfg.actuators and cfg.actuators.leftMain or "MainThrusterLeft"
local right = cfg.actuators and cfg.actuators.rightMain or "MainThrusterRight"

print(fwd .. "=" .. tostring(sensors[fwd]) .. " err=" .. tostring(sensors[fwd .. "Err"]))
print(left .. "=" .. tostring(actuators[left]) .. " err=" .. tostring(actuators[left .. "Err"]))
print(right .. "=" .. tostring(actuators[right]) .. " err=" .. tostring(actuators[right .. "Err"]))
print("probe ok")
