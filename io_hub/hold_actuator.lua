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
local actuators = loadFirst({ "io_hub/actuators.lua", "actuators.lua" })

local args = { ... }
local actuatorName = args[1] or "SteamVent"
local command = tonumber(args[2]) or 7.5
local seconds = tonumber(args[3]) or 10
local printPeriod = tonumber(args[4]) or 0.5

local sides = { "left", "right", "front", "back", "top", "bottom" }

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

local function period()
    local spec = cfg.actuators and cfg.actuators[actuatorName] or {}
    local p = tonumber(spec.pwmPeriod)
    if p == nil then
        p = tonumber(cfg.actuatorPwm and cfg.actuatorPwm.period)
    end
    if p == nil or p <= 0 then
        p = 0.05
    end
    return p
end

local function wrapRelay()
    local spec = cfg.actuators and cfg.actuators[actuatorName]
    if type(spec) ~= "table" then
        return nil, "unknown actuator [" .. tostring(actuatorName) .. "]"
    end
    if type(peripheral) ~= "table" then
        return nil, "peripheral API unavailable"
    end

    if type(spec.remoteName) == "string" and spec.remoteName ~= "" then
        local device = peripheral.wrap(spec.remoteName)
        if not device then
            return nil, "cannot wrap peripheral [" .. spec.remoteName .. "]"
        end
        return device, spec.remoteName
    end

    local peripheralType = spec.peripheralType or "redstone_relay"
    local device = peripheral.find(peripheralType)
    if not device then
        return nil, "cannot find peripheral type [" .. peripheralType .. "]"
    end
    return device, peripheralType
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

local function sideReadback(device)
    if not device then
        return "side-readback unavailable"
    end

    local parts = {}
    for _, side in ipairs(sides) do
        parts[#parts + 1] = side .. "=" .. fmt(getAnalog(device, side))
    end
    return table.concat(parts, " ")
end

local function readConfigured()
    local values = actuators.readAll(cfg)
    return {
        output = values[actuatorName],
        command = values[actuatorName .. "Command"],
        exact = values[actuatorName .. "ExactOutput"],
        err = values[actuatorName .. "Err"]
    }
end

local function monitorLoop(device)
    local started = os.epoch and (os.epoch("utc") / 1000) or os.clock()
    local ticks = math.max(1, math.floor(seconds / printPeriod + 0.5))

    for i = 1, ticks do
        local r = readConfigured()
        local nowSeconds = os.epoch and (os.epoch("utc") / 1000) or os.clock()
        printf(
            "t=%.2f read=%s command=%s exact=%s err=%s",
            nowSeconds - started,
            fmt(r.output),
            fmt(r.command),
            fmt(r.exact),
            tostring(r.err)
        )
        print("  sides " .. sideReadback(device))
        sleep(printPeriod)
    end
end

local function manualPwmLoop()
    local p = period()
    while true do
        actuators.updateAll(cfg)
        sleep(p)
    end
end

local relay = nil
local relayErr = nil
relay, relayErr = wrapRelay()

local ok, err = pcall(function()
    print("hold actuator")
    printf("  actuator = %s", tostring(actuatorName))
    printf("  command  = %s", fmt(command))
    printf("  seconds  = %s", fmt(seconds))
    printf("  period   = %s", fmt(period()))
    printf("  relay    = %s", tostring(relayErr))

    local result, setErr = actuators.setOutput(cfg, actuatorName, command)
    if not result then
        error(setErr)
    end
    printf("  set-ok output=%s exact=%s lower=%s upper=%s fraction=%s",
        fmt(result.output),
        fmt(result.exactOutput),
        fmt(result.lowerOutput),
        fmt(result.upperOutput),
        fmt(result.pwmFraction)
    )

    if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
        parallel.waitForAny(function() monitorLoop(relay) end, manualPwmLoop)
    else
        local p = period()
        local totalTicks = math.max(1, math.floor(seconds / p + 0.5))
        local printEvery = math.max(1, math.floor(printPeriod / p + 0.5))
        for i = 1, totalTicks do
            actuators.updateAll(cfg)
            if i == 1 or i == totalTicks or i % printEvery == 0 then
                local r = readConfigured()
                printf("tick=%03d read=%s command=%s exact=%s err=%s",
                    i, fmt(r.output), fmt(r.command), fmt(r.exact), tostring(r.err))
                print("  sides " .. sideReadback(relay))
            end
            sleep(p)
        end
    end
end)

local stopOk, stopErr = pcall(function()
    actuators.setOutput(cfg, actuatorName, 0)
    actuators.updateAll(cfg, true)
end)

if not stopOk then
    print("stop ERR: " .. tostring(stopErr))
end

if ok then
    print("hold finished; actuator set to 0")
else
    print("hold failed: " .. tostring(err))
end
