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

local args = { ... }
local actuatorName = args[1] or "SteamVent"
local highCommand = tonumber(args[2]) or 15
local midCommand = tonumber(args[3]) or 7.5
local highSeconds = tonumber(args[4]) or 2
local midSeconds = tonumber(args[5]) or 5
local redstoneSides = { "left", "right", "front", "back", "top", "bottom" }

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

local function actuatorSpec()
    local spec = cfg.actuators and cfg.actuators[actuatorName]
    if type(spec) ~= "table" then
        error("unknown actuator [" .. tostring(actuatorName) .. "]")
    end
    return spec
end

local function pwmPeriod(spec)
    local period = tonumber(spec.pwmPeriod)
    if period == nil and cfg.actuatorPwm then
        period = tonumber(cfg.actuatorPwm.period)
    end
    if period == nil or period <= 0 then
        period = 0.05
    end
    return period
end

local function printPeripherals(spec)
    if type(peripheral) ~= "table" or type(peripheral.getNames) ~= "function" then
        print("peripheral API unavailable")
        return
    end

    local names = peripheral.getNames() or {}
    table.sort(names)
    print("wired peripherals:")
    for _, name in ipairs(names) do
        local kind = "?"
        if type(peripheral.getType) == "function" then
            local ok, value = pcall(peripheral.getType, name)
            if ok then
                kind = tostring(value)
            end
        end

        local mark = " "
        if name == spec.remoteName or kind == tostring(spec.peripheralType) then
            mark = "*"
        end
        printf("  %s %s [%s]", mark, tostring(name), kind)
    end
end

local function printSpec(spec)
    print("target actuator:")
    printf("  name           = %s", tostring(actuatorName))
    printf("  driver         = %s", tostring(spec.driver))
    printf("  peripheralType = %s", tostring(spec.peripheralType))
    printf("  remoteName     = %s", tostring(spec.remoteName))
    printf("  outputSide     = %s", tostring(spec.outputSide))
    printf("  outputRange    = %s .. %s", fmt(spec.outputMin), fmt(spec.outputMax))
    printf("  pwmEnabled     = %s", tostring(spec.pwmEnabled))
    printf("  pwmPeriod      = %s s", fmt(pwmPeriod(spec)))
end

local function clearRelaySides(spec)
    if type(peripheral) ~= "table" then
        return nil, "peripheral API unavailable"
    end

    local device
    if type(spec.remoteName) == "string" and spec.remoteName ~= "" then
        device = peripheral.wrap(spec.remoteName)
    else
        device = peripheral.find(spec.peripheralType or "redstone_relay")
    end

    if not device then
        return nil, "cannot find relay to clear"
    end

    for _, side in ipairs(redstoneSides) do
        if type(device.setAnalogOutput) == "function" then
            device.setAnalogOutput(side, 0)
        elseif type(device.setAnalogueOutput) == "function" then
            device.setAnalogueOutput(side, 0)
        else
            return nil, "device has no analog output method"
        end
    end

    return true
end

local function readLine()
    local values = hal.readActuators(cfg)
    local err = values[actuatorName .. "Err"]
    local address = values[actuatorName .. "Address"]
    local output = values[actuatorName]
    local command = values[actuatorName .. "Command"]
    local exact = values[actuatorName .. "ExactOutput"]

    return {
        address = address,
        output = output,
        command = command,
        exact = exact,
        err = err
    }
end

local function printReadback(prefix)
    local line = readLine()
    printf(
        "%s address=%s read=%s command=%s exact=%s err=%s",
        prefix,
        tostring(line.address),
        fmt(line.output),
        fmt(line.command),
        fmt(line.exact),
        tostring(line.err)
    )
    return line
end

local function hold(spec, seconds, printEverySeconds, historyLimit)
    local period = pwmPeriod(spec)
    local ticks = math.max(1, math.floor(seconds / period + 0.5))
    local printEvery = math.max(1, math.floor((printEverySeconds or 0.5) / period + 0.5))
    local history = {}

    for i = 1, ticks do
        hal.updateActuators(cfg)
        local line = readLine()

        if historyLimit and #history < historyLimit then
            history[#history + 1] = fmt(line.output)
        end

        if i == 1 or i == ticks or i % printEvery == 0 then
            printf(
                "  tick=%03d read=%s command=%s exact=%s err=%s",
                i,
                fmt(line.output),
                fmt(line.command),
                fmt(line.exact),
                tostring(line.err)
            )
        end

        sleep(period)
    end

    if #history > 0 then
        print("  pulse(first " .. tostring(#history) .. " ticks)=" .. table.concat(history, " "))
    end
end

local function writeAndHold(label, spec, command, seconds, historyLimit)
    print("")
    printf("[%s] write %s = %s, hold %.2fs", label, actuatorName, fmt(command), seconds)
    local result, err = hal.writeActuator(cfg, actuatorName, command)
    if not result then
        error(err)
    end

    printf(
        "  write-ok output=%s exact=%s lower=%s upper=%s fraction=%s",
        fmt(result.output),
        fmt(result.exactOutput),
        fmt(result.lowerOutput),
        fmt(result.upperOutput),
        fmt(result.pwmFraction)
    )
    printReadback("  after-write")
    hold(spec, seconds, 0.5, historyLimit)
end

local spec = actuatorSpec()

local ok, err = pcall(function()
    print("Steam Vent link probe")
    printSpec(spec)
    print("")
    printPeripherals(spec)

    clearRelaySides(spec)
    writeAndHold("off", spec, 0, 1, 8)
    writeAndHold("full", spec, highCommand, highSeconds, 16)
    writeAndHold("pdm", spec, midCommand, midSeconds, 40)
    writeAndHold("stop", spec, 0, 1, 8)
end)

local stopOk, stopErr = pcall(function()
    hal.writeActuator(cfg, actuatorName, 0)
    hal.updateActuators(cfg, true)
end)

if not stopOk then
    print("failsafe-stop ERR: " .. tostring(stopErr))
end

print("")
if ok then
    print("probe finished")
    print("If relay readback changes but Steam Vent is still idle, check outputSide and physical redstone adjacency.")
else
    print("probe failed: " .. tostring(err))
    print("Check wired modem network, fleet_config.lua remoteName/peripheralType, and redstone relay outputSide.")
end
