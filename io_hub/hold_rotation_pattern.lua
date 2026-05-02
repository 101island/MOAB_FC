local DEFAULT_NAMES = {
    "Create_RotationSpeedController_1",
    "Create_RotationSpeedController_2",
    "Create_RotationSpeedController_3",
    "Create_RotationSpeedController_4"
}

local args = { ... }

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

local function split(text)
    local values = {}
    for item in tostring(text or ""):gmatch("[^,]+") do
        values[#values + 1] = item
    end
    return values
end

local function wrap(name)
    if type(peripheral) ~= "table" then
        return nil, "peripheral API unavailable"
    end
    local device = peripheral.wrap(name)
    if not device then
        return nil, "cannot wrap " .. tostring(name)
    end
    return device
end

local function call(device, method, value)
    local fn = device[method]
    if type(fn) ~= "function" then
        return nil, "no method [" .. tostring(method) .. "]"
    end
    local ok, result = pcall(fn, value)
    if not ok then
        return nil, result
    end
    return result == nil and true or result
end

local function readTarget(device)
    local fn = device.getTargetSpeed
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    return nil
end

local function makeValues(base, step)
    return {
        base,
        base + step,
        base + step * 2,
        base + step * 3
    }
end

local method = args[1] or "setTargetSpeed"
local base = tonumber(args[2]) or 8
local step = tonumber(args[3]) or 8
local period = tonumber(args[4]) or 0.5
local zero = tonumber(args[5]) or 0
local names = args[6] and split(args[6]) or DEFAULT_NAMES
local values = makeValues(base, step)

local devices = {}

local function setAll(active)
    for index, name in ipairs(names) do
        local device = devices[index]
        if device then
            local value = active and values[index] or zero
            local ok, err = call(device, method, value)
            if not ok then
                printf("%s ERR %s", name, tostring(err))
            end
        end
    end
end

local function stopAll()
    setAll(false)
    print("all rotation controllers set to zero")
end

print("rotation controller pattern hold")
printf("  method = %s", tostring(method))
printf("  values = %s, %s, %s, %s", tostring(values[1]), tostring(values[2]), tostring(values[3]), tostring(values[4]))
printf("  period = %.2fs", period)
print("Mapping by visible speed:")
for index, name in ipairs(names) do
    printf("  %s -> %s", tostring(name), tostring(values[index]))
    local device, err = wrap(name)
    if not device then
        printf("    ERR %s", tostring(err))
    end
    devices[index] = device
end
print("")
print("Press q or Ctrl+T to stop and zero all controllers.")

local running = true

local function outputLoop()
    while running do
        setAll(true)
        for index, name in ipairs(names) do
            local device = devices[index]
            if device then
                local target = readTarget(device)
                printf("%s command=%s read=%s", name, tostring(values[index]), tostring(target))
            end
        end
        print("---")
        sleep(period)
    end
end

local function inputLoop()
    while running do
        local event, keyOrChar = os.pullEventRaw()
        if event == "char" and keyOrChar == "q" then
            running = false
        elseif event == "key" and type(keys) == "table" and keyOrChar == keys.q then
            running = false
        elseif event == "terminate" then
            running = false
        end
    end
end

local ok, err
if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
    ok, err = pcall(parallel.waitForAny, outputLoop, inputLoop)
else
    ok, err = pcall(outputLoop)
end

stopAll()
if not ok then
    error(err, 0)
end
