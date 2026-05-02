local M = {}

local function displaySpec(cfg)
    local spec = cfg and cfg.display or {}
    if spec.enabled == false then
        return nil, "display disabled"
    end
    return spec
end

local function wrap(spec)
    if type(peripheral) ~= "table" then
        return nil, "peripheral API is unavailable"
    end

    local remoteName = spec.remoteName
    if type(remoteName) == "string" and remoteName ~= "" then
        local device = peripheral.wrap(remoteName)
        if not device then
            return nil, "cannot wrap peripheral [" .. remoteName .. "]"
        end
        return device, nil, remoteName
    end

    local peripheralType = spec.peripheralType or "monitor"
    local device = peripheral.find(peripheralType)
    if not device then
        return nil, "cannot find peripheral type [" .. peripheralType .. "]"
    end
    return device, nil, peripheralType
end

local function setColor(device, fg, bg)
    if type(colors) ~= "table" then
        return
    end
    if fg and type(device.setTextColor) == "function" then
        device.setTextColor(fg)
    end
    if bg and type(device.setBackgroundColor) == "function" then
        device.setBackgroundColor(bg)
    end
end

local function fit(value, width)
    local text = tostring(value == nil and "" or value)
    if width == nil or width <= 0 then
        return text
    end
    if #text > width then
        return text:sub(1, width)
    end
    return text .. string.rep(" ", width - #text)
end

local function formatValue(value)
    if value == nil then
        return "nil"
    end
    if type(value) == "number" then
        return string.format("%.3f", value)
    end
    return tostring(value)
end

local function orderedItems(values)
    local items = {}
    if type(values) ~= "table" then
        return items
    end
    for _, name in ipairs(values.order or {}) do
        items[#items + 1] = {
            name = name,
            value = values[name],
            err = values[name .. "Err"]
        }
    end
    return items
end

function M.open(cfg)
    local spec, specErr = displaySpec(cfg)
    if not spec then
        return nil, specErr
    end

    local device, err, address = wrap(spec)
    if not device then
        return nil, err
    end

    local scale = tonumber(spec.textScale)
    if scale ~= nil and type(device.setTextScale) == "function" then
        device.setTextScale(scale)
    end

    return {
        device = device,
        address = address,
        spec = spec
    }
end

function M.clear(cfg)
    local handle, err = M.open(cfg)
    if not handle then
        return nil, err
    end

    local device = handle.device
    setColor(device, colors and colors.white, colors and colors.black)
    device.clear()
    device.setCursorPos(1, 1)
    return true
end

function M.info(cfg)
    local handle, err = M.open(cfg)
    if not handle then
        return nil, err
    end

    local width, height = handle.device.getSize()
    return {
        address = handle.address,
        width = width,
        height = height,
        textScale = handle.spec.textScale
    }
end

function M.drawLines(cfg, lines)
    local handle, err = M.open(cfg)
    if not handle then
        return nil, err
    end

    local device = handle.device
    local width, height = device.getSize()
    setColor(device, colors and colors.white, colors and colors.black)
    device.clear()

    for row = 1, math.min(height, #lines) do
        device.setCursorPos(1, row)
        device.write(fit(lines[row], width))
    end

    return {
        address = handle.address,
        width = width,
        height = height
    }
end

function M.drawSnapshot(cfg, snapshot)
    local spec = cfg and cfg.display or {}
    local lines = {}
    local title = spec.title or "MOAB IO HUB"

    lines[#lines + 1] = title
    lines[#lines + 1] = "t=" .. formatValue(snapshot and snapshot.t)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "SENSORS"

    for _, item in ipairs(orderedItems(snapshot and snapshot.sensors)) do
        if item.err then
            lines[#lines + 1] = item.name .. " ERR " .. tostring(item.err)
        else
            lines[#lines + 1] = item.name .. " = " .. formatValue(item.value)
        end
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "ACTUATORS"

    for _, item in ipairs(orderedItems(snapshot and snapshot.actuators)) do
        if item.err then
            lines[#lines + 1] = item.name .. " ERR " .. tostring(item.err)
        else
            local command = snapshot.actuators[item.name .. "Command"]
            local exact = snapshot.actuators[item.name .. "ExactOutput"]
            lines[#lines + 1] = item.name .. " = " .. formatValue(item.value) ..
                " cmd=" .. formatValue(command) ..
                " exact=" .. formatValue(exact)
        end
    end

    return M.drawLines(cfg, lines)
end

function M.drawProbe(cfg)
    local info, err = M.info(cfg)
    if not info then
        return nil, err
    end

    return M.drawLines(cfg, {
        "DISPLAY OK",
        "address=" .. tostring(info.address),
        "size=" .. tostring(info.width) .. "x" .. tostring(info.height),
        "scale=" .. tostring(info.textScale),
        "",
        "If this is visible,",
        "monitor link is up."
    })
end

return M
