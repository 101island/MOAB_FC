local M = {}

local buttons = {}

local function displaySpec(cfg)
    local base = cfg and cfg.display or {}
    local mode = base.mode or "compact"
    local profile = base.profiles and base.profiles[mode] or nil
    local spec = {}
    for key, value in pairs(base) do
        if key ~= "profiles" then spec[key] = value end
    end
    if type(profile) == "table" then
        for key, value in pairs(profile) do spec[key] = value end
    end
    spec.mode = mode
    return spec
end

local function wrap(cfg)
    local spec = displaySpec(cfg)
    if spec.enabled == false then
        return nil, "display disabled"
    end
    if type(peripheral) ~= "table" then
        return nil, "peripheral API unavailable"
    end

    local device
    local address
    if type(spec.remoteName) == "string" and spec.remoteName ~= "" then
        device = peripheral.wrap(spec.remoteName)
        address = spec.remoteName
    elseif type(spec.side) == "string" and spec.side ~= "" then
        device = peripheral.wrap(spec.side)
        address = spec.side
    else
        local bestName = nil
        local bestArea = -1
        if type(peripheral.getNames) == "function" and type(peripheral.getType) == "function" then
            for _, name in ipairs(peripheral.getNames()) do
                local kind = peripheral.getType(name)
                local isMonitor = kind == "monitor"
                if type(kind) == "table" then
                    for _, item in ipairs(kind) do
                        if item == "monitor" then isMonitor = true end
                    end
                end
                if isMonitor then
                    local candidate = peripheral.wrap(name)
                    if candidate and type(candidate.getSize) == "function" then
                        local w, h = candidate.getSize()
                        local area = (tonumber(w) or 0) * (tonumber(h) or 0)
                        if area > bestArea then
                            bestArea = area
                            bestName = name
                            device = candidate
                        end
                    end
                end
            end
        end
        if not device then
            device = peripheral.find(spec.peripheralType or "monitor")
        end
        address = bestName or spec.peripheralType or "monitor"
    end
    if not device then
        return nil, "cannot find monitor [" .. tostring(address) .. "]"
    end

    local scale = tonumber(spec.textScale)
    if scale and type(device.setTextScale) == "function" then
        device.setTextScale(scale)
    end
    return device
end

local function color(name)
    if type(colors) == "table" then
        return colors[name]
    end
    return nil
end

local function setColor(device, fg, bg)
    if fg and type(device.setTextColor) == "function" then device.setTextColor(fg) end
    if bg and type(device.setBackgroundColor) == "function" then device.setBackgroundColor(bg) end
end

local function size(device)
    local width, height = device.getSize()
    return tonumber(width) or 1, tonumber(height) or 1
end

local function writeAt(device, x, y, text, fg, bg)
    local width, height = size(device)
    if x < 1 or y < 1 or x > width or y > height then return end
    local s = tostring(text or "")
    setColor(device, fg or color("white"), bg or color("black"))
    device.setCursorPos(x, y)
    device.write(s:sub(1, math.max(0, width - x + 1)))
end

local function clear(device)
    setColor(device, color("white"), color("black"))
    device.clear()
    device.setCursorPos(1, 1)
end

local function fmt(value, digits)
    if value == nil then return "--" end
    if type(value) == "number" then
        return string.format("%." .. tostring(digits or 2) .. "f", value)
    end
    return tostring(value)
end

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

local function addButton(device, label, action, x, y, fg)
    local width = size(device)
    if x + #label - 1 > width then return x end
    writeAt(device, x, y, label, fg or color("cyan"))
    buttons[#buttons + 1] = {
        x1 = x,
        x2 = x + #label - 1,
        y = y,
        action = action
    }
    return x + #label + 1
end

local function drawBar(device, x, y, width, value, minValue, maxValue, fg)
    if width < 4 then return end
    local ratio = 0
    if maxValue ~= minValue then
        ratio = clamp(((tonumber(value) or 0) - minValue) / (maxValue - minValue), 0, 1)
    end
    local fill = math.floor(width * ratio + 0.5)
    local text = string.rep("#", fill) .. string.rep("-", width - fill)
    writeAt(device, x, y, text, fg or color("lime"))
end

local function drawHeader(device, state)
    local status = state.enabled and "FWD ON" or "FWD OFF"
    writeAt(device, 1, 1, status, state.enabled and color("lime") or color("red"))
    writeAt(device, 10, 1, "v=" .. fmt(state.speed.current, 2) .. ">" .. fmt(state.speed.target, 2), color("white"))
    writeAt(device, 30, 1, "err=" .. fmt(state.speed.error, 2), color("yellow"))
end

local function drawValues(device, state)
    writeAt(device, 1, 3, "TARGET", color("gray"))
    writeAt(device, 10, 3, fmt(state.speed.target, 2), color("yellow"))
    writeAt(device, 1, 4, "SPEED", color("gray"))
    writeAt(device, 10, 4, fmt(state.speed.current, 2), color("lime"))
    writeAt(device, 1, 5, "ERROR", color("gray"))
    writeAt(device, 10, 5, fmt(state.speed.error, 2), color("orange"))

    writeAt(device, 24, 3, "BASE", color("gray"))
    writeAt(device, 31, 3, fmt(state.output.base, 1), color("cyan"))
    writeAt(device, 24, 4, "TURN", color("gray"))
    writeAt(device, 31, 4, fmt(state.output.turn, 1), color("cyan"))
    writeAt(device, 24, 5, "STAT", color("gray"))
    writeAt(device, 31, 5, tostring(state.status or ""):sub(1, 18), state.lastErr and color("red") or color("lime"))
end

local function drawOutputs(device, state)
    local width = size(device)
    local barWidth = math.max(8, width - 12)
    local minValue = tonumber(state.outputMin) or -256
    local maxValue = tonumber(state.outputMax) or 256
    writeAt(device, 1, 7, "LEFT ", color("gray"))
    writeAt(device, 7, 7, fmt(state.output.left, 1), color("lime"))
    drawBar(device, 1, 8, barWidth, state.output.left, minValue, maxValue, color("lime"))

    writeAt(device, 1, 10, "RIGHT", color("gray"))
    writeAt(device, 7, 10, fmt(state.output.right, 1), color("lime"))
    drawBar(device, 1, 11, barWidth, state.output.right, minValue, maxValue, color("lime"))
end

local function drawButtons(device, state)
    local _, height = size(device)
    local row = math.max(1, height - 1)
    local x = 1
    x = addButton(device, state.enabled and "[OFF]" or "[ON]", "toggle", x, row)
    x = addButton(device, "[V-]", "speedDown", x, row)
    x = addButton(device, "[V+]", "speedUp", x, row)
    x = addButton(device, "[L]", "turnLeft", x, row)
    x = addButton(device, "[R]", "turnRight", x, row)
    x = addButton(device, "[C]", "turnZero", x, row)
    x = addButton(device, "[0]", "speedZero", x, row)
    x = addButton(device, "[RD]", "load", x, row)
    addButton(device, "[WR]", "save", x, row)
end

local function drawCompact(device, state)
    local width, height = size(device)
    local enabled = state.enabled and "ON" or "OFF"
    writeAt(device, 1, 1,
        ("V %s>%s"):format(fmt(state.speed.current, 1), fmt(state.speed.target, 1)),
        state.enabled and color("lime") or color("white"))
    if width >= 14 then
        writeAt(device, math.min(width, 12), 1, enabled, state.enabled and color("lime") or color("red"))
    end

    if height >= 2 then
        writeAt(device, 1, 2,
            ("B %s T %s"):format(fmt(state.output.base, 0), fmt(state.output.turn, 0)),
            color("cyan"))
    end
    if height >= 3 then
        writeAt(device, 1, 3,
            ("L%s R%s"):format(fmt(state.output.left, 0), fmt(state.output.right, 0)),
            color("yellow"))
    end
    if height >= 4 then
        local status = tostring(state.status or ""):sub(1, width - 2)
        writeAt(device, 1, 4, "S " .. status, state.lastErr and color("red") or color("gray"))
    end
    if height >= 5 then
        writeAt(device, 1, 5, "W/S V  A/D T", color("gray"))
    end
end

function M.draw(cfg, state)
    local device, err = wrap(cfg)
    if not device then return nil, err end
    local spec = displaySpec(cfg)
    buttons = {}
    clear(device)
    if spec.mode == "debug" then
        drawHeader(device, state)
        drawValues(device, state)
        drawOutputs(device, state)
        drawButtons(device, state)
    else
        drawCompact(device, state)
    end
    return true
end

function M.clear(cfg, message)
    local device, err = wrap(cfg)
    if not device then return nil, err end
    clear(device)
    if message then
        writeAt(device, 1, 1, tostring(message), color("gray"))
    end
    return true
end

function M.handleTouch(x, y)
    for _, button in ipairs(buttons) do
        if y == button.y and x >= button.x1 and x <= button.x2 then
            return button.action
        end
    end
    return nil
end

return M
