local DEFAULT_NAMES = {
    "Create_RotationSpeedController_1",
    "Create_RotationSpeedController_2",
    "Create_RotationSpeedController_3",
    "Create_RotationSpeedController_4"
}

local args = { ... }
local mode = args[1] or "list"

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

local function splitNames(text)
    local names = {}
    for item in tostring(text or ""):gmatch("[^,]+") do
        names[#names + 1] = item
    end
    return names
end

local function targetNames()
    if args[2] and args[2] ~= "" and args[2]:find(",") then
        return splitNames(args[2])
    end
    return DEFAULT_NAMES
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

local function listMethods(name, device)
    if type(peripheral) == "table" and type(peripheral.getMethods) == "function" then
        local methods = peripheral.getMethods(name)
        if type(methods) == "table" then
            table.sort(methods)
            return methods
        end
    end

    local methods = {}
    for key, value in pairs(device) do
        if type(value) == "function" then
            methods[#methods + 1] = key
        end
    end
    table.sort(methods)
    return methods
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

local function list()
    for _, name in ipairs(targetNames()) do
        local device, err = wrap(name)
        printf("[%s]", name)
        if not device then
            printf("  ERR %s", tostring(err))
        else
            if type(peripheral) == "table" and type(peripheral.getType) == "function" then
                printf("  type = %s", tostring(peripheral.getType(name)))
            end
            for _, method in ipairs(listMethods(name, device)) do
                printf("  - %s", tostring(method))
            end
        end
    end
end

local function align()
    local method = args[2] or "setTargetSpeed"
    local value = tonumber(args[3]) or 16
    local hold = tonumber(args[4]) or 3
    local zero = tonumber(args[5]) or 0

    print("rotation controller alignment")
    printf("  method = %s", tostring(method))
    printf("  pulse  = %s for %.2fs", tostring(value), hold)
    printf("  zero   = %s", tostring(zero))
    print("Observe which propeller moves, then write the mapping table.")
    print("Suggested physical labels: NoseLeft, NoseRight, TailLeft, TailRight.")
    print("")

    for _, name in ipairs(DEFAULT_NAMES) do
        local device, err = wrap(name)
        printf("[%s]", name)
        if not device then
            printf("  ERR %s", tostring(err))
        else
            print("  Press Enter to pulse this controller.")
            if type(read) == "function" then
                read()
            end
            local ok, setErr = call(device, method, value)
            if not ok then
                printf("  SET ERR %s", tostring(setErr))
            else
                printf("  ON  %s = %s", tostring(method), tostring(value))
                sleep(hold)
                call(device, method, zero)
                printf("  OFF %s = %s", tostring(method), tostring(zero))
            end
            print("  Record: rawName -> physical position -> positive direction/effect")
        end
        print("")
    end
end

local function usage()
    print("Usage:")
    print("  probe_rotation_controllers.lua list")
    print("  probe_rotation_controllers.lua align <setMethod> <pulseValue> <holdSeconds> <zeroValue>")
    print("")
    print("Examples:")
    print("  probe_rotation_controllers.lua list")
    print("  probe_rotation_controllers.lua align setTargetSpeed 16 3 0")
end

if mode == "list" then
    list()
elseif mode == "align" then
    align()
else
    usage()
end
