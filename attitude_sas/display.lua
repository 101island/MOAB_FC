local M = {}
M.moduleName = "attitude_sas.display"

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
    { label = "ATT", key = "ctrl" },
    { label = "PID", key = "pid" },
    { label = "PFF", key = "ff" },
    { label = "MIX", key = "out" },
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
    if fg and type(device.setTextColor) == "function" then device.setTextColor(fg) end
    if bg and type(device.setBackgroundColor) == "function" then device.setBackgroundColor(bg) end
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

local function clamp(value, minValue, maxValue)
    if minValue ~= nil and value < minValue then return minValue end
    if maxValue ~= nil and value > maxValue then return maxValue end
    return value
end

local function resetPid(p)
    if type(p) ~= "table" then return end
    p.integral = 0
    p.previousError = nil
    p.previousIntegralError = nil
end

local function resetLoops(state)
    resetPid(state.pitchPid)
    resetPid(state.rollPid)
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
        if x + #token - 1 > width then break end
        local selected = index == activePage
        writeAt(device, x, 1, token,
            selected and color("black") or color("white"),
            selected and color("white") or color("black"))
        x = x + #token + 1
    end
end

local function menuHit(x, y)
    if y ~= 1 then return nil end
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
    return {
        {
            label = "P TGT",
            get = function() return state.targetPitch end,
            step = 0.1,
            adjust = function(delta) state.targetPitch = (tonumber(state.targetPitch) or 0) + delta; resetPid(state.pitchPid) end
        },
        {
            label = "R TGT",
            get = function() return state.targetRoll end,
            step = 0.1,
            adjust = function(delta) state.targetRoll = (tonumber(state.targetRoll) or 0) + delta; resetPid(state.rollPid) end
        },
        {
            label = "P KP",
            get = function() return state.pitchPid.kp end,
            step = 0.1,
            adjust = function(delta) state.pitchPid.kp = math.max(0, (tonumber(state.pitchPid.kp) or 0) + delta); resetPid(state.pitchPid) end
        },
        {
            label = "P KI",
            get = function() return state.pitchPid.ki end,
            step = 0.001,
            adjust = function(delta) state.pitchPid.ki = math.max(0, (tonumber(state.pitchPid.ki) or 0) + delta); resetPid(state.pitchPid) end
        },
        {
            label = "P KD",
            get = function() return state.pitchPid.kd end,
            step = 0.01,
            adjust = function(delta) state.pitchPid.kd = math.max(0, (tonumber(state.pitchPid.kd) or 0) + delta); resetPid(state.pitchPid) end
        },
        {
            label = "R KP",
            get = function() return state.rollPid.kp end,
            step = 0.1,
            adjust = function(delta) state.rollPid.kp = math.max(0, (tonumber(state.rollPid.kp) or 0) + delta); resetPid(state.rollPid) end
        },
        {
            label = "R KI",
            get = function() return state.rollPid.ki end,
            step = 0.001,
            adjust = function(delta) state.rollPid.ki = math.max(0, (tonumber(state.rollPid.ki) or 0) + delta); resetPid(state.rollPid) end
        },
        {
            label = "R KD",
            get = function() return state.rollPid.kd end,
            step = 0.01,
            adjust = function(delta) state.rollPid.kd = math.max(0, (tonumber(state.rollPid.kd) or 0) + delta); resetPid(state.rollPid) end
        },
        {
            label = "FILTER",
            get = function() return state.angleFilterAlpha end,
            step = 0.05,
            adjust = function(delta) state.angleFilterAlpha = clamp((tonumber(state.angleFilterAlpha) or 1) + delta, 0, 1) end
        },
        {
            label = "MAXSTEP",
            get = function() return state.maxStep end,
            step = 1,
            adjust = function(delta) state.maxStep = math.max(0, (tonumber(state.maxStep) or 0) + delta) end
        },
        {
            label = "OUT MIN",
            get = function() return state.outputMin end,
            step = 1,
            adjust = function(delta) state.outputMin = (tonumber(state.outputMin) or 0) + delta end
        },
        {
            label = "OUT MAX",
            get = function() return state.outputMax end,
            step = 1,
            adjust = function(delta) state.outputMax = (tonumber(state.outputMax) or 0) + delta end
        },
        {
            label = "P SCALE",
            get = function() return state.pitchScale end,
            step = 0.1,
            adjust = function(delta) state.pitchScale = (tonumber(state.pitchScale) or 1) + delta; resetLoops(state) end
        },
        {
            label = "R SCALE",
            get = function() return state.rollScale end,
            step = 0.1,
            adjust = function(delta) state.rollScale = (tonumber(state.rollScale) or 1) + delta; resetLoops(state) end
        }
    }
end

local function ffFields(state)
    local ff = state.pitchFeedforward or {}
    local mixer = state.mixer or {}
    return {
        {
            label = "FF EN",
            get = function() return ff.enabled == false and 0 or 1 end,
            step = 1,
            adjust = function() ff.enabled = ff.enabled == false end
        },
        {
            label = "FF GAIN",
            get = function() return ff.gain end,
            step = 0.01,
            adjust = function(delta) ff.gain = (tonumber(ff.gain) or 0) + delta end
        },
        {
            label = "FF BIAS",
            get = function() return ff.bias end,
            step = 0.1,
            adjust = function(delta) ff.bias = (tonumber(ff.bias) or 0) + delta end
        },
        {
            label = "FF MIN",
            get = function() return ff.outputMin end,
            step = 1,
            adjust = function(delta) ff.outputMin = (tonumber(ff.outputMin) or 0) + delta end
        },
        {
            label = "FF MAX",
            get = function() return ff.outputMax end,
            step = 1,
            adjust = function(delta) ff.outputMax = (tonumber(ff.outputMax) or 0) + delta end
        },
        {
            label = "NEUTRAL",
            get = function() return mixer.neutral end,
            step = 1,
            adjust = function(delta) mixer.neutral = (tonumber(mixer.neutral) or 0) + delta end
        },
        {
            label = "MIX P",
            get = function() return mixer.pitchScale end,
            step = 0.1,
            adjust = function(delta) mixer.pitchScale = (tonumber(mixer.pitchScale) or 1) + delta end
        },
        {
            label = "MIX R",
            get = function() return mixer.rollScale end,
            step = 0.1,
            adjust = function(delta) mixer.rollScale = (tonumber(mixer.rollScale) or 1) + delta end
        }
    }
end

local function selectedIndex(key, fields)
    selectedField[key] = selectedField[key] or 1
    if selectedField[key] < 1 then selectedField[key] = 1 end
    if #fields > 0 and selectedField[key] > #fields then selectedField[key] = #fields end
    return selectedField[key]
end

local function adjustSelected(state, sign)
    local key = pageKey()
    local fields = key == "ff" and ffFields(state) or tuneFields(state)
    if key ~= "pid" and key ~= "ff" then return end
    local field = fields[selectedIndex(key, fields)]
    if not field then return end
    local step = (tonumber(field.step) or 1) * (tonumber(stepScales[stepScaleIndex]) or 1)
    field.adjust(sign * step)
end

local function nextField(state)
    local key = pageKey()
    local fields = key == "ff" and ffFields(state) or tuneFields(state)
    if (key ~= "pid" and key ~= "ff") or #fields == 0 then return end
    selectedField[key] = selectedIndex(key, fields) + 1
    if selectedField[key] > #fields then selectedField[key] = 1 end
end

local function drawBottomButtons(device, state)
    local _, height = size(device)
    local row = math.max(1, height - 1)
    local x = 1
    local key = pageKey()
    x = addButton(device,
        state.pitchEnabled and "[POFF]" or "[PON]",
        state.pitchEnabled and "pitchOff" or "pitchOn",
        nil, x, row)
    x = addButton(device,
        state.rollEnabled and "[ROFF]" or "[RON]",
        state.rollEnabled and "rollOff" or "rollOn",
        nil, x, row)
    if key == "pid" or key == "ff" then
        x = addButton(device, "[-]", nil, function() adjustSelected(state, -1) end, x, row)
        x = addButton(device, "[+]", nil, function() adjustSelected(state, 1) end, x, row)
        x = addButton(device, "[x" .. tostring(stepScales[stepScaleIndex]) .. "]", nil, function()
            stepScaleIndex = stepScaleIndex + 1
            if stepScaleIndex > #stepScales then stepScaleIndex = 1 end
        end, x, row)
        x = addButton(device, "[N]", nil, function() nextField(state) end, x, row)
    end
    x = addButton(device, "[RD]", "load", nil, x, row)
    x = addButton(device, "[WR]", "save", nil, x, row)
    addButton(device, "[R]", "reset", nil, x, row)
end

local function drawStatus(device, state)
    local width, height = size(device)
    writeAt(device, 1, height, tostring(state.status or ""):sub(1, width),
        state.lastErr and color("red") or color("gray"))
end

local function drawValue(device, x, y, label, value, fg)
    writeAt(device, x, y, tostring(label):sub(1, 9), color("white"))
    writeAt(device, x + 10, y, fmt(value), fg or color("lime"))
end

local function drawCtrl(device, state)
    local width = size(device)
    local col = math.max(20, math.floor(width / 3))
    writeAt(device, 1, 2,
        "ATTITUDE SAS P=" .. (state.pitchEnabled and "ON" or "OFF") ..
        " R=" .. (state.rollEnabled and "ON" or "OFF"),
        (state.pitchEnabled or state.rollEnabled) and color("lime") or color("red"))

    drawValue(device, 1, 4, "PITCH", state.pitch.current, color("lime"))
    drawValue(device, 1, 5, "P TGT", state.pitch.target, color("yellow"))
    drawValue(device, 1, 6, "P ERR", state.pitch.error, color("orange"))
    drawValue(device, 1, 7, "P OUT", state.pitch.command, color("cyan"))

    drawValue(device, col + 1, 4, "ROLL", state.roll.current, color("lime"))
    drawValue(device, col + 1, 5, "R TGT", state.roll.target, color("yellow"))
    drawValue(device, col + 1, 6, "R ERR", state.roll.error, color("orange"))
    drawValue(device, col + 1, 7, "R OUT", state.roll.command, color("cyan"))

    drawValue(device, col * 2 + 1, 4, "FF", state.pitch.feedforward, color("yellow"))
    drawValue(device, col * 2 + 1, 5, "FF SRC", state.pitch.feedforwardSource, color("gray"))
    drawValue(device, col * 2 + 1, 6, "P PID", state.pitch.pidOutput, color("cyan"))
    drawValue(device, col * 2 + 1, 7, "R PID", state.roll.pidOutput, color("cyan"))
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
    if cols == 1 and index > rowsPerCol then first = index - rowsPerCol + 1 end

    fieldRegions = {}
    for fieldIndex = first, #fields do
        local visible = fieldIndex - first
        local col = math.floor(visible / rowsPerCol)
        if col >= cols then break end
        local row = startRow + (visible % rowsPerCol)
        local x = 1 + col * colWidth
        local field = fields[fieldIndex]
        local mark = fieldIndex == index and ">" or " "
        local fg = fieldIndex == index and color("yellow") or color("white")
        writeAt(device, x, row, mark .. tostring(field.label):sub(1, 9), fg)
        writeAt(device, x + 11, row, fmt(field.get()), fieldIndex == index and color("yellow") or color("lime"))
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
    writeAt(device, 1, 2, "ATT PID TUNE step x" .. tostring(stepScales[stepScaleIndex]), color("cyan"))
    writeAt(device, 1, 3, "touch field, then [-]/[+]; [N] next", color("gray"))
    drawFields(device, "pid", tuneFields(state))
end

local function sourceLabel(ff)
    if type(ff) ~= "table" then return "none" end
    if type(ff.sourceActuators) == "table" and #ff.sourceActuators > 0 then
        local short = {}
        for _, name in ipairs(ff.sourceActuators) do
            if name == "MainThrusterLeft" then
                short[#short + 1] = "L"
            elseif name == "MainThrusterRight" then
                short[#short + 1] = "R"
            elseif type(name) == "string" and name ~= "" then
                short[#short + 1] = name
            end
        end
        if #short > 0 then
            return "avg(" .. table.concat(short, "+") .. ")"
        end
    end
    local single = ff.sourceActuator
    if type(single) == "string" and single ~= "" then
        return single
    end
    return "avg(L+R)"
end

local function drawFf(device, state)
    local ff = state.pitchFeedforward or {}
    writeAt(device, 1, 2, "PITCH MAIN-THRUST FF source=" .. sourceLabel(ff), color("cyan"))
    writeAt(device, 1, 3, "ff = bias + gain * avg(main thrust)", color("gray"))
    drawFields(device, "ff", ffFields(state))
end

local function sortedKeys(map)
    local keys = {}
    if type(map) ~= "table" then return keys end
    for key in pairs(map) do
        if type(key) == "string" and not key:find("Err$") and key ~= "order" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

local function drawOut(device, state)
    writeAt(device, 1, 2, "PROP MIX OUTPUTS", color("cyan"))
    local row = 4
    local commands = state.output and state.output.commands or {}
    for _, key in ipairs(sortedKeys(commands)) do
        writeAt(device, 1, row, key:sub(1, 14), color("white"))
        writeAt(device, 16, row, fmt(commands[key]), color("lime"))
        row = row + 1
    end
end

local function sampleValue(sample, key)
    if type(sample) == "table" then return sample[key] end
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
    if minValue == nil or maxValue == nil then return 0, 1 end
    if minValue == maxValue then return minValue - 1, maxValue + 1 end
    return minValue, maxValue
end

local function plotRow(value, minValue, maxValue, top, height)
    if type(value) ~= "number" or height < 1 then return nil end
    local ratio = clamp((value - minValue) / (maxValue - minValue), 0, 1)
    return top + height - 1 - math.floor(ratio * (height - 1) + 0.5)
end

local function drawChart(device, x, y, width, height, title, samples, series)
    if width < 14 or height < 4 then return end
    local minValue, maxValue = bounds(samples, series)
    writeAt(device, x, y, title .. " " .. fmt(minValue, 1) .. ".." .. fmt(maxValue, 1), color("cyan"))
    local plotTop = y + 1
    local plotHeight = height - 1
    local count = #samples
    for col = 1, width do
        local index = count - width + col
        local sample = index >= 1 and samples[index] or nil
        if sample then
            for _, item in ipairs(series or {}) do
                local row = plotRow(sampleValue(sample, item.key), minValue, maxValue, plotTop, plotHeight)
                if row then writeAt(device, x + col - 1, row, item.char or "*", item.color) end
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
    local chartHeight = math.floor(available / 2)
    drawChart(device, 1, 4, width, chartHeight, "PITCH *cur -tgt", samples, {
        { key = "pitch", char = "*", color = color("lime") },
        { key = "pitchTarget", char = "-", color = color("yellow") }
    })
    drawChart(device, 1, 4 + chartHeight, width, chartHeight, "ROLL *cur -tgt", samples, {
        { key = "roll", char = "*", color = color("lime") },
        { key = "rollTarget", char = "-", color = color("yellow") }
    })
end

local function drawIoList(device, title, data, x, y, width, maxRows)
    writeAt(device, x, y, title, color("cyan"))
    local row = y + 1
    for _, key in ipairs(sortedKeys(data)) do
        if row > y + maxRows then break end
        local err = data[key .. "Err"]
        writeAt(device, x, row, key:sub(1, 11), color("white"))
        writeAt(device, x + 12, row, fmt(data[key]), err and color("red") or color("lime"))
        row = row + 1
    end
end

local function drawIo(device, state)
    local width, height = size(device)
    local snap = state.lastSnapshot or {}
    local col = math.max(24, math.floor(width / 2))
    local rows = math.max(3, height - 5)
    drawIoList(device, "SENSORS", snap.sensors or {}, 1, 3, col - 1, rows)
    drawIoList(device, "ACTUATORS", snap.actuators or {}, col + 1, 3, width - col, rows)
end

function M.draw(cfg, state)
    local device, err = wrap(cfg)
    if not device then return nil, err end
    if state and state.position and state.speed and not state.pitch then
        return nil, "wrong display module state: expected Attitude SAS state"
    end
    buttons = {}
    fieldRegions = {}
    clear(device)
    drawMenu(device)

    local key = pageKey()
    if key == "pid" then
        drawPid(device, state)
    elseif key == "ff" then
        drawFf(device, state)
    elseif key == "out" then
        drawOut(device, state)
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
