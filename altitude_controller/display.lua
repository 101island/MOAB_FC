local M = {}

local buttons = {}
local fieldRegions = {}
local activePage = 1
local selectedField = {
    pid = 1,
    ff = 1
}
local stepScales = { 0.1, 1, 10 }
local stepScaleIndex = 2

local pages = {
    { label = "CTRL", key = "ctrl" },
    { label = "PID", key = "pid" },
    { label = "FF", key = "ff" },
    { label = "PLOT", key = "plot" },
    { label = "IO", key = "io" }
}

local function cfgDisplay(cfg)
    return cfg.display or {}
end

local function wrap(cfg)
    local spec = cfgDisplay(cfg)
    if spec.enabled == false then
        return nil, "display disabled"
    end
    if type(peripheral) ~= "table" then
        return nil, "peripheral API unavailable"
    end

    local device
    if type(spec.remoteName) == "string" and spec.remoteName ~= "" then
        device = peripheral.wrap(spec.remoteName)
    else
        device = peripheral.find(spec.peripheralType or "monitor")
    end
    if not device then
        return nil, "cannot find monitor"
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
    if fg and type(device.setTextColor) == "function" then
        device.setTextColor(fg)
    end
    if bg and type(device.setBackgroundColor) == "function" then
        device.setBackgroundColor(bg)
    end
end

local function size(device)
    local width, height = device.getSize()
    return tonumber(width) or 1, tonumber(height) or 1
end

local function writeAt(device, x, y, text, fg, bg)
    local width, height = size(device)
    if x < 1 or y < 1 or x > width or y > height then
        return
    end
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
    if value == nil then
        return "--"
    end
    if type(value) == "number" then
        return string.format("%." .. tostring(digits or 2) .. "f", value)
    end
    return tostring(value)
end

local function resetPid(pid)
    if type(pid) ~= "table" then
        return
    end
    pid.integral = 0
    pid.previousError = nil
    pid.previousIntegralError = nil
end

local function resetLoops(state)
    resetPid(state.outerPid)
    resetPid(state.innerPid)
end

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then
        return minValue
    end
    if maxValue ~= nil and value > maxValue then
        return maxValue
    end
    return value
end

local function addButton(device, label, action, fn, x, y, fg)
    local width = size(device)
    if x + #label - 1 > width then
        return x
    end
    writeAt(device, x, y, label, fg or color("cyan"))
    buttons[#buttons + 1] = {
        x1 = x,
        x2 = x + #label - 1,
        y = y,
        action = action,
        fn = fn
    }
    return x + #label + 1
end

local function drawMenu(device)
    local width = size(device)
    local x = 1
    for index, page in ipairs(pages) do
        local token = index == activePage and ("[" .. page.label .. "]") or (" " .. page.label .. " ")
        if x + #token - 1 > width then
            break
        end
        local selected = index == activePage
        writeAt(device, x, 1, token,
            selected and color("black") or color("white"),
            selected and color("white") or color("black"))
        x = x + #token + 1
    end
end

local function menuHit(x, y)
    if y ~= 1 then
        return nil
    end
    local cursor = 1
    for index, page in ipairs(pages) do
        local tokenWidth = #page.label + 2
        if x >= cursor and x < cursor + tokenWidth then
            return index
        end
        cursor = cursor + tokenWidth + 1
    end
    return nil
end

local function pageKey()
    local page = pages[activePage] or pages[1]
    return page.key
end

local function tuneFields(state)
    local fields = {
        {
            label = "TGT ALT",
            get = function() return state.targetAltitude end,
            step = 1,
            adjust = function(delta)
                state.targetAltitude = (tonumber(state.targetAltitude) or 0) + delta
                resetLoops(state)
            end
        },
        {
            label = "MAN SPD",
            get = function() return state.manualSpeedTarget end,
            step = 0.1,
            adjust = function(delta)
                state.manualSpeedTarget = (tonumber(state.manualSpeedTarget) or 0) + delta
                resetPid(state.innerPid)
            end
        },
        {
            label = "O KP",
            get = function() return state.outerPid.kp end,
            step = 0.01,
            adjust = function(delta) state.outerPid.kp = math.max(0, (tonumber(state.outerPid.kp) or 0) + delta); resetPid(state.outerPid) end
        },
        {
            label = "O KI",
            get = function() return state.outerPid.ki end,
            step = 0.001,
            adjust = function(delta) state.outerPid.ki = math.max(0, (tonumber(state.outerPid.ki) or 0) + delta); resetPid(state.outerPid) end
        },
        {
            label = "O KD",
            get = function() return state.outerPid.kd end,
            step = 0.01,
            adjust = function(delta) state.outerPid.kd = math.max(0, (tonumber(state.outerPid.kd) or 0) + delta); resetPid(state.outerPid) end
        },
        {
            label = "I KP",
            get = function() return state.innerPid.kp end,
            step = 0.1,
            adjust = function(delta) state.innerPid.kp = math.max(0, (tonumber(state.innerPid.kp) or 0) + delta); resetPid(state.innerPid) end
        },
        {
            label = "I KI",
            get = function() return state.innerPid.ki end,
            step = 0.001,
            adjust = function(delta) state.innerPid.ki = math.max(0, (tonumber(state.innerPid.ki) or 0) + delta); resetPid(state.innerPid) end
        },
        {
            label = "I KD",
            get = function() return state.innerPid.kd end,
            step = 0.01,
            adjust = function(delta) state.innerPid.kd = math.max(0, (tonumber(state.innerPid.kd) or 0) + delta); resetPid(state.innerPid) end
        },
        {
            label = "MAXSTEP",
            get = function() return state.maxStep end,
            step = 0.1,
            adjust = function(delta) state.maxStep = math.max(0, (tonumber(state.maxStep) or 0) + delta) end
        },
        {
            label = "FILTER",
            get = function() return state.speedFilterAlpha end,
            step = 0.05,
            adjust = function(delta) state.speedFilterAlpha = clamp((tonumber(state.speedFilterAlpha) or 1) + delta, 0, 1) end
        }
    }
    return fields
end

local function feedforwardFields(state)
    local fields = {}
    local points = state.feedforward and state.feedforward.points
    if type(points) ~= "table" then
        return fields
    end

    for index, point in ipairs(points) do
        fields[#fields + 1] = {
            label = "FF" .. tostring(point.altitude),
            get = function() return point.level end,
            step = 0.05,
            adjust = function(delta)
                point.level = clamp((tonumber(point.level) or 0) + delta,
                    state.feedforward.outputMin or 0,
                    state.feedforward.outputMax or 15)
                resetLoops(state)
            end
        }
    end
    return fields
end

local function selectedIndex(key, fields)
    selectedField[key] = selectedField[key] or 1
    if selectedField[key] < 1 then
        selectedField[key] = 1
    end
    if #fields > 0 and selectedField[key] > #fields then
        selectedField[key] = #fields
    end
    return selectedField[key]
end

local function adjustSelected(state, sign)
    local key = pageKey()
    local fields = key == "ff" and feedforwardFields(state) or tuneFields(state)
    if key ~= "pid" and key ~= "ff" then
        return
    end
    local index = selectedIndex(key, fields)
    local field = fields[index]
    if not field then
        return
    end
    local step = (tonumber(field.step) or 1) * (tonumber(stepScales[stepScaleIndex]) or 1)
    field.adjust(sign * step)
end

local function nextField(state)
    local key = pageKey()
    local fields = key == "ff" and feedforwardFields(state) or tuneFields(state)
    if (key ~= "pid" and key ~= "ff") or #fields == 0 then
        return
    end
    selectedField[key] = selectedIndex(key, fields) + 1
    if selectedField[key] > #fields then
        selectedField[key] = 1
    end
end

local function drawBottomButtons(device, state)
    local _, height = size(device)
    local row = math.max(1, height - 1)
    local x = 1
    local key = pageKey()

    x = addButton(device, state.enabled and "[OFF]" or "[ON]", "toggle", nil, x, row)
    x = addButton(device, state.pidOutputEnabled and "[PON]" or "[POF]", "pidOutput", nil, x, row)
    if key == "pid" or key == "ff" then
        x = addButton(device, "[-]", nil, function() adjustSelected(state, -1) end, x, row)
        x = addButton(device, "[+]", nil, function() adjustSelected(state, 1) end, x, row)
        x = addButton(device, "[x" .. tostring(stepScales[stepScaleIndex]) .. "]", nil, function()
            stepScaleIndex = stepScaleIndex + 1
            if stepScaleIndex > #stepScales then
                stepScaleIndex = 1
            end
        end, x, row)
        x = addButton(device, "[N]", nil, function() nextField(state) end, x, row)
    else
        x = addButton(device, "[-1]", "down1", nil, x, row)
        x = addButton(device, "[+1]", "up1", nil, x, row)
        x = addButton(device, "[-5]", "down5", nil, x, row)
        x = addButton(device, "[+5]", "up5", nil, x, row)
    end
    x = addButton(device, "[M]", "mode", nil, x, row)
    x = addButton(device, "[RD]", "load", nil, x, row)
    x = addButton(device, "[WR]", "save", nil, x, row)
    addButton(device, "[R]", "reset", nil, x, row)
end

local function drawStatus(device, state)
    local width, height = size(device)
    local text = tostring(state.status or ""):sub(1, width)
    writeAt(device, 1, height, text, state.lastErr and color("red") or color("gray"))
end

local function drawValue(device, x, y, label, value, fg)
    writeAt(device, x, y, tostring(label):sub(1, 8), color("white"))
    writeAt(device, x + 9, y, fmt(value), fg or color("lime"))
end

local function drawCtrl(device, state)
    local width = size(device)
    local col = math.max(18, math.floor(width / 3))
    writeAt(device, 1, 2, "CTRL " .. tostring(state.mode) .. " " .. (state.enabled and "ON" or "OFF") ..
        " PID " .. (state.pidOutputEnabled and "ON" or "OFF"),
        state.enabled and color("lime") or color("red"))

    drawValue(device, 1, 4, "ALT", state.position.current, color("lime"))
    drawValue(device, 1, 5, "TARGET", state.position.target, color("yellow"))
    drawValue(device, 1, 6, "ERR", state.position.error, color("orange"))

    drawValue(device, col + 1, 4, "V/S", state.speed.current, color("lime"))
    drawValue(device, col + 1, 5, "TGT V/S", state.speed.target, color("yellow"))
    drawValue(device, col + 1, 6, "ERR", state.speed.error, color("orange"))

    drawValue(device, col * 2 + 1, 4, "OUT", state.output.command, color("cyan"))
    drawValue(device, col * 2 + 1, 5, "FF", state.output.feedforward, color("yellow"))
    drawValue(device, col * 2 + 1, 6, "PID", state.output.correction, color("cyan"))
    drawValue(device, col * 2 + 1, 7, "RB", state.output.readback, color("gray"))
end

local function drawFields(device, key, fields)
    local width, height = size(device)
    local index = selectedIndex(key, fields)
    local cols = width >= 60 and 2 or 1
    local colWidth = math.floor(width / cols)
    local startRow = 4
    local maxRow = math.max(startRow, height - 3)
    local rowsPerCol = math.max(1, maxRow - startRow + 1)
    local first = 1
    if cols == 1 and index > rowsPerCol then
        first = index - rowsPerCol + 1
    end

    fieldRegions = {}
    for fieldIndex = first, #fields do
        local visible = fieldIndex - first
        local col = math.floor(visible / rowsPerCol)
        if col >= cols then
            break
        end
        local row = startRow + (visible % rowsPerCol)
        local x = 1 + col * colWidth
        local field = fields[fieldIndex]
        local mark = fieldIndex == index and ">" or " "
        local fg = fieldIndex == index and color("yellow") or color("white")
        local valueColor = fieldIndex == index and color("yellow") or color("lime")
        writeAt(device, x, row, mark .. tostring(field.label):sub(1, 8), fg)
        writeAt(device, x + 10, row, fmt(field.get()), valueColor)
        fieldRegions[#fieldRegions + 1] = {
            x1 = x,
            x2 = math.min(width, x + colWidth - 1),
            y = row,
            key = key,
            index = fieldIndex
        }
    end
end

local function drawPid(device, state)
    writeAt(device, 1, 2, "PID TUNE out " .. (state.pidOutputEnabled and "ON" or "OFF") ..
        "  step x" .. tostring(stepScales[stepScaleIndex]), color("cyan"))
    writeAt(device, 1, 3, "touch field, then [-]/[+]; [N] next", color("gray"))
    drawFields(device, "pid", tuneFields(state))
end

local function drawFeedforward(device, state)
    writeAt(device, 1, 2, "FEEDFORWARD cur=" .. fmt(state.output.feedforward) ..
        " pid=" .. (state.pidOutputEnabled and "on" or "off"), color("cyan"))
    writeAt(device, 1, 3, "hover table levels, step x" .. tostring(stepScales[stepScaleIndex]), color("gray"))
    drawFields(device, "ff", feedforwardFields(state))
end

local function sampleValue(sample, key)
    if type(sample) == "table" then
        return sample[key]
    end
    return nil
end

local function bounds(samples, series)
    local minValue = nil
    local maxValue = nil
    for _, sample in ipairs(samples or {}) do
        for _, item in ipairs(series or {}) do
            local value = sampleValue(sample, item.key)
            if type(value) == "number" then
                if minValue == nil or value < minValue then minValue = value end
                if maxValue == nil or value > maxValue then maxValue = value end
            end
        end
    end
    if minValue == nil or maxValue == nil then
        return 0, 1
    end
    if minValue == maxValue then
        return minValue - 1, maxValue + 1
    end
    return minValue, maxValue
end

local function plotRow(value, minValue, maxValue, top, height)
    if type(value) ~= "number" or height < 1 then
        return nil
    end
    local ratio = (value - minValue) / (maxValue - minValue)
    ratio = clamp(ratio, 0, 1)
    return top + height - 1 - math.floor(ratio * (height - 1) + 0.5)
end

local function drawChart(device, x, y, width, height, title, samples, series)
    if width < 14 or height < 4 then
        return
    end
    local minValue, maxValue = bounds(samples, series)
    writeAt(device, x, y, title .. " " .. fmt(minValue, 1) .. ".." .. fmt(maxValue, 1), color("cyan"))
    local plotTop = y + 1
    local plotHeight = height - 1
    local plotWidth = width
    local count = #samples
    for col = 1, plotWidth do
        local index = count - plotWidth + col
        local sample = index >= 1 and samples[index] or nil
        if sample then
            for _, item in ipairs(series or {}) do
                local row = plotRow(sampleValue(sample, item.key), minValue, maxValue, plotTop, plotHeight)
                if row then
                    writeAt(device, x + col - 1, row, item.char or "*", item.color)
                end
            end
        end
    end
end

local function drawPlot(device, state)
    local width, height = size(device)
    local samples = state.history and state.history.samples or {}
    writeAt(device, 1, 2, "PLOT samples=" .. tostring(#samples), color("cyan"))
    local available = height - 4
    if available < 8 then
        writeAt(device, 1, 4, "monitor too small", color("red"))
        return
    end
    local chartCount = available >= 15 and 3 or 2
    local chartHeight = math.floor(available / chartCount)
    drawChart(device, 1, 4, width, chartHeight, "ALT *cur -tgt", samples, {
        { key = "altitude", char = "*", color = color("lime") },
        { key = "altitudeTarget", char = "-", color = color("yellow") }
    })
    drawChart(device, 1, 4 + chartHeight, width, chartHeight, "V/S *cur -tgt", samples, {
        { key = "speed", char = "*", color = color("lime") },
        { key = "speedTarget", char = "-", color = color("yellow") }
    })
    if chartCount >= 3 then
        drawChart(device, 1, 4 + chartHeight * 2, width, chartHeight, "OUT *cmd -ff", samples, {
            { key = "output", char = "*", color = color("cyan") },
            { key = "feedforward", char = "-", color = color("yellow") }
        })
    end
end

local function sortedKeys(map)
    local keys = {}
    if type(map) ~= "table" then
        return keys
    end
    for key in pairs(map) do
        if type(key) == "string" and
            not key:find("Err$") and
            not key:find("Method$") and
            key ~= "order" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local function drawIoList(device, title, data, x, y, width, maxRows)
    writeAt(device, x, y, title, color("cyan"))
    local row = y + 1
    for _, key in ipairs(sortedKeys(data)) do
        if row > y + maxRows then
            break
        end
        local err = data[key .. "Err"]
        writeAt(device, x, row, key:sub(1, 10), color("white"))
        writeAt(device, x + 11, row, fmt(data[key]), err and color("red") or color("lime"))
        row = row + 1
    end
end

local function drawIo(device, state)
    local width, height = size(device)
    local snap = state.lastSnapshot or {}
    local col = math.max(22, math.floor(width / 2))
    local rows = math.max(3, height - 5)
    drawIoList(device, "SENSORS", snap.sensors or {}, 1, 3, col - 1, rows)
    drawIoList(device, "ACTUATORS", snap.actuators or {}, col + 1, 3, width - col, rows)
end

function M.draw(cfg, state)
    local device, err = wrap(cfg)
    if not device then
        return nil, err
    end

    buttons = {}
    fieldRegions = {}
    clear(device)
    drawMenu(device)

    local key = pageKey()
    if key == "pid" then
        drawPid(device, state)
    elseif key == "ff" then
        drawFeedforward(device, state)
    elseif key == "plot" then
        drawPlot(device, state)
    elseif key == "io" then
        drawIo(device, state)
    else
        drawCtrl(device, state)
    end

    drawBottomButtons(device, state)
    drawStatus(device, state)
    return true
end

function M.handleTouch(x, y)
    local pageIndex = menuHit(x, y)
    if pageIndex then
        activePage = pageIndex
        return nil
    end

    for _, region in ipairs(fieldRegions) do
        if y == region.y and x >= region.x1 and x <= region.x2 then
            selectedField[region.key] = region.index
            return nil
        end
    end

    for _, button in ipairs(buttons) do
        if y == button.y and x >= button.x1 and x <= button.x2 then
            if type(button.fn) == "function" then
                button.fn()
                return nil
            end
            return button.action
        end
    end
    return nil
end

return M
