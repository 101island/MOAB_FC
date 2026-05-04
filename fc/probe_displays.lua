local args = { ... }
local target = args[1]

if type(peripheral) ~= "table" then
    error("peripheral API unavailable")
end

local function isMonitorType(kind)
    if kind == "monitor" then return true end
    if type(kind) == "table" then
        for _, item in ipairs(kind) do
            if item == "monitor" then return true end
        end
    end
    return false
end

local function probe(name)
    local kind = peripheral.getType(name)
    if not isMonitorType(kind) then
        return nil
    end
    local device = peripheral.wrap(name)
    if not device or type(device.getSize) ~= "function" then
        return nil
    end
    local width, height = device.getSize()
    return {
        name = name,
        width = tonumber(width) or 0,
        height = tonumber(height) or 0,
        area = (tonumber(width) or 0) * (tonumber(height) or 0)
    }
end

local monitors = {}
if target and target ~= "" then
    local item = probe(target)
    if item then monitors[#monitors + 1] = item end
else
    for _, name in ipairs(peripheral.getNames()) do
        local item = probe(name)
        if item then monitors[#monitors + 1] = item end
    end
end

table.sort(monitors, function(a, b)
    if a.area == b.area then return a.name < b.name end
    return a.area > b.area
end)

if #monitors == 0 then
    print("no monitor visible from FC")
    print("If IO Hub 3x2 is not listed here, FC cannot direct-wrap it.")
    return
end

for index, item in ipairs(monitors) do
    print(string.format("%d. %s size=%sx%s area=%s",
        index, item.name, item.width, item.height, item.area))
end

local best = monitors[1]
print("best=" .. tostring(best.name))

local device = peripheral.wrap(best.name)
if device then
    if type(device.setTextScale) == "function" then device.setTextScale(0.5) end
    if type(device.clear) == "function" then device.clear() end
    if type(device.setCursorPos) == "function" then device.setCursorPos(1, 1) end
    if type(device.write) == "function" then
        device.write("FC display probe " .. tostring(best.name))
    end
end
