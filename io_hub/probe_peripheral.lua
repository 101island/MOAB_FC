local target = ...

if type(peripheral) ~= "table" then
    error("peripheral API is unavailable")
end

if not target or target == "" then
    print("Usage: probe_peripheral.lua <peripheralName> [method]")
    print("Example: probe_peripheral.lua attitude_sensor_0")
    return
end

local onlyMethod = select(2, ...)
local device = peripheral.wrap(target)
if not device then
    print("ERR: cannot wrap " .. tostring(target))
    return
end

local function serialize(value)
    if type(textutils) == "table" and type(textutils.serialize) == "function" then
        return textutils.serialize(value)
    end
    return tostring(value)
end

local function shouldCall(name)
    if onlyMethod and onlyMethod ~= "" then
        return name == onlyMethod
    end
    return name:match("^get") or name:match("^is") or name:match("^has")
end

local function call(name)
    local fn = device[name]
    if type(fn) ~= "function" then
        print(name .. " = <not a function>")
        return
    end

    local values = { pcall(fn) }
    if not values[1] then
        print(name .. " ERR: " .. tostring(values[2]))
        return
    end

    local out = {}
    for i = 2, #values do
        out[#out + 1] = values[i]
    end
    print(name .. " -> " .. serialize(out))
end

local ok, methods = pcall(peripheral.getMethods, target)
if not ok or type(methods) ~= "table" then
    print("ERR: cannot get methods for " .. tostring(target))
    return
end

table.sort(methods)
print(target .. " [" .. tostring(peripheral.getType(target)) .. "]")

for _, name in ipairs(methods) do
    if shouldCall(name) then
        call(name)
    end
end
