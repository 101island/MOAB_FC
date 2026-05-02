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

local args = { ... }
local actuatorName = args[1] or "SteamVent"
local level = tonumber(args[2]) or 15
local holdSeconds = tonumber(args[3]) or 4

local sides = { "left", "right", "front", "back", "top", "bottom" }

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

local function wrapRelay(spec)
    if type(peripheral) ~= "table" then
        return nil, "peripheral API is unavailable"
    end

    local remoteName = spec.remoteName
    if type(remoteName) == "string" and remoteName ~= "" then
        local device = peripheral.wrap(remoteName)
        if not device then
            return nil, "cannot wrap peripheral [" .. remoteName .. "]"
        end
        return device, remoteName
    end

    local peripheralType = spec.peripheralType or "redstone_relay"
    local device = peripheral.find(peripheralType)
    if not device then
        return nil, "cannot find peripheral type [" .. peripheralType .. "]"
    end
    return device, peripheralType
end

local function setAnalog(device, side, value)
    if type(device.setAnalogOutput) == "function" then
        device.setAnalogOutput(side, value)
        return true
    end
    if type(device.setAnalogueOutput) == "function" then
        device.setAnalogueOutput(side, value)
        return true
    end
    return false, "device has no analog output method"
end

local function getAnalog(device, side)
    if type(device.getAnalogOutput) == "function" then
        return device.getAnalogOutput(side)
    end
    if type(device.getAnalogueOutput) == "function" then
        return device.getAnalogueOutput(side)
    end
    return nil
end

local function clearAll(device)
    for _, side in ipairs(sides) do
        setAnalog(device, side, 0)
    end
end

local function printReadback(device)
    local parts = {}
    for _, side in ipairs(sides) do
        parts[#parts + 1] = side .. "=" .. tostring(getAnalog(device, side))
    end
    print("  readback " .. table.concat(parts, " "))
end

local spec = cfg.actuators and cfg.actuators[actuatorName]
if type(spec) ~= "table" then
    error("unknown actuator [" .. tostring(actuatorName) .. "]")
end

local device, addressOrErr = wrapRelay(spec)
if not device then
    error(addressOrErr)
end

local ok, err = pcall(function()
    print("redstone relay side probe")
    printf("  actuator = %s", tostring(actuatorName))
    printf("  relay    = %s", tostring(addressOrErr))
    printf("  level    = %s", tostring(level))
    printf("  hold     = %ss per side", tostring(holdSeconds))
    print("")

    clearAll(device)
    printReadback(device)

    for _, side in ipairs(sides) do
        print("")
        printf("[%s] output %s for %ss", side, tostring(level), tostring(holdSeconds))
        clearAll(device)
        local setOk, setErr = setAnalog(device, side, level)
        if not setOk then
            error(setErr)
        end
        printReadback(device)

        local t0 = os.clock()
        while os.clock() - t0 < holdSeconds do
            sleep(0.5)
        end

        setAnalog(device, side, 0)
        printReadback(device)
    end
end)

clearAll(device)

print("")
if ok then
    print("side probe finished; all relay sides are now 0")
    print("Use the side where Steam Vent responds as fleet_config.lua SteamVent.outputSide.")
else
    print("side probe failed: " .. tostring(err))
    print("all relay sides were reset to 0")
end
