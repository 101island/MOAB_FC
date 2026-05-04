local args = { ... }

local target = args[1] or "top"
local period = tonumber(args[2]) or 0.05
local monitorTarget = args[3] or "left"

local names = {
    [32] = "SPACE",
    [256] = "ESC",
    [257] = "ENTER",
    [258] = "TAB",
    [259] = "BACKSPACE",
    [260] = "INSERT",
    [261] = "DELETE",
    [262] = "RIGHT",
    [263] = "LEFT",
    [264] = "DOWN",
    [265] = "UP",
    [340] = "LSHIFT",
    [341] = "LCTRL",
    [342] = "LALT",
    [343] = "LMETA",
    [344] = "RSHIFT",
    [345] = "RCTRL",
    [346] = "RALT",
    [347] = "RMETA"
}

for code = 48, 57 do
    names[code] = string.char(code)
end
for code = 65, 90 do
    names[code] = string.char(code)
end
for i = 1, 12 do
    names[289 + i] = "F" .. tostring(i)
end

local function wrapTypewriter(name)
    if type(peripheral) ~= "table" then
        return nil, "peripheral API unavailable"
    end

    local device = peripheral.wrap(name)
    if device and peripheral.getType(name) == "linked_typewriter" then
        return device, name
    end

    if type(peripheral.find) == "function" then
        device = peripheral.find("linked_typewriter")
        if device then
            return device, "linked_typewriter"
        end
    end

    return nil, "cannot find linked_typewriter on [" .. tostring(name) .. "]"
end

local function wrapDisplay(name)
    if type(peripheral) ~= "table" then
        return nil
    end

    local device = peripheral.wrap(name)
    if device and peripheral.getType(name) == "monitor" then
        return device, name
    end

    if type(peripheral.find) == "function" then
        device = peripheral.find("monitor")
        if device then
            return device, "monitor"
        end
    end

    return term, "terminal"
end

local function keyName(code)
    code = tonumber(code)
    if not code then return "?" end
    return names[code] or ("KEY_" .. tostring(code))
end

local function readSet(device)
    local list = device.getPressedKeyCodes()
    local set = {}
    local ordered = {}
    for _, code in ipairs(list or {}) do
        local n = tonumber(code)
        if n and not set[n] then
            set[n] = true
            ordered[#ordered + 1] = n
        end
    end
    table.sort(ordered)
    return set, ordered
end

local function formatKeys(ordered)
    if #ordered == 0 then
        return "none"
    end
    local parts = {}
    for _, code in ipairs(ordered) do
        parts[#parts + 1] = keyName(code) .. "(" .. tostring(code) .. ")"
    end
    return table.concat(parts, " ")
end

local function fit(text, width)
    text = tostring(text or "")
    if #text <= width then
        return text
    end
    if width <= 1 then
        return text:sub(1, width)
    end
    return text:sub(1, width - 1) .. ">"
end

local function writeLine(device, row, text)
    local width, height = device.getSize()
    if row < 1 or row > height then
        return
    end
    device.setCursorPos(1, row)
    device.clearLine()
    device.write(fit(text, width))
end

local function draw(device, source, ordered, pressed, released)
    local width, height = device.getSize()
    device.clear()
    writeLine(device, 1, "TYPE " .. tostring(source))
    writeLine(device, 2, "NOW " .. formatKeys(ordered))
    writeLine(device, 3, "DN  " .. formatKeys(pressed))
    writeLine(device, 4, "UP  " .. formatKeys(released))
    if height >= 5 then
        writeLine(device, 5, "Ctrl+T stop")
    end
    if width <= 12 and height >= 3 then
        writeLine(device, 1, "NOW")
        writeLine(device, 2, formatKeys(ordered))
        writeLine(device, 3, "D " .. formatKeys(pressed))
        if height >= 4 then
            writeLine(device, 4, "U " .. formatKeys(released))
        end
    end
end

local function diff(previous, current)
    local pressed = {}
    local released = {}
    for code in pairs(current) do
        if not previous[code] then
            pressed[#pressed + 1] = code
        end
    end
    for code in pairs(previous) do
        if not current[code] then
            released[#released + 1] = code
        end
    end
    table.sort(pressed)
    table.sort(released)
    return pressed, released
end

local device, sourceOrErr = wrapTypewriter(target)
if not device then
    print("ERR: " .. tostring(sourceOrErr))
    print("Usage: test_typewriter.lua [sideOrName] [period]")
    print("Example: test_typewriter.lua top 0.05")
    return
end

print("Linked Typewriter test")
print("source=" .. tostring(sourceOrErr))
print("period=" .. tostring(period))
local display, displaySource = wrapDisplay(monitorTarget)
if display and display.setTextScale then
    display.setTextScale(0.5)
end
print("display=" .. tostring(displaySource))
print("Hold keys on the linked typewriter. Watch monitor. Ctrl+T to stop.")
sleep(1)

local previous = {}
while true do
    local current, ordered = readSet(device)
    local pressed, released = diff(previous, current)

    draw(display, sourceOrErr, ordered, pressed, released)

    previous = current
    sleep(period)
end
