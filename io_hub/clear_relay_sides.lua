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
local sides = { "left", "right", "front", "back", "top", "bottom" }

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

local spec = cfg.actuators and cfg.actuators[actuatorName]
if type(spec) ~= "table" then
    error("unknown actuator [" .. tostring(actuatorName) .. "]")
end

local device, addressOrErr = wrapRelay(spec)
if not device then
    error(addressOrErr)
end

print("clear relay sides")
print("  actuator = " .. tostring(actuatorName))
print("  relay    = " .. tostring(addressOrErr))

for _, side in ipairs(sides) do
    local ok, err = setAnalog(device, side, 0)
    if not ok then
        error(err)
    end
end

local parts = {}
for _, side in ipairs(sides) do
    parts[#parts + 1] = side .. "=" .. tostring(getAnalog(device, side))
end
print("  readback " .. table.concat(parts, " "))
print("done")
