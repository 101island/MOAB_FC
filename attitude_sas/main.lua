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

local function loadOptional(paths)
    for _, path in ipairs(paths) do
        if not fs or fs.exists(path) then
            local ok, mod = pcall(dofile, path)
            if ok then
                return mod
            end
            print("WARN: cannot load optional module " .. tostring(path) .. ": " .. tostring(mod))
        end
    end
    return nil
end

local function runningDir()
    if type(shell) == "table" and type(shell.getRunningProgram) == "function" and
        type(fs) == "table" and type(fs.getDir) == "function" then
        local dir = fs.getDir(shell.getRunningProgram() or "")
        if dir and dir ~= "." then return dir end
    end
    return ""
end

local function joinPath(dir, name)
    if dir == nil or dir == "" then return name end
    if type(fs) == "table" and type(fs.combine) == "function" then
        return fs.combine(dir, name)
    end
    return dir .. "/" .. name
end

local function modulePaths(name)
    local path = joinPath(runningDir(), name)
    if path == name then return { name } end
    return { path, name }
end

local function mergeTable(target, source)
    if type(target) ~= "table" or type(source) ~= "table" then
        return target
    end
    for key, value in pairs(source) do
        if type(value) == "table" and type(target[key]) == "table" then
            mergeTable(target[key], value)
        else
            target[key] = value
        end
    end
    return target
end

local cfg = loadFirst(modulePaths("config.lua"))
local tuning = loadOptional(modulePaths("tuning.lua"))
if tuning then
    mergeTable(cfg, tuning)
end

local runtime = loadFirst(modulePaths("runtime.lua"))

local args = { ... }
local startDisplay = false
local startPitch = nil
local startRoll = nil
local explicitAxis = false
for _, arg in ipairs(args) do
    local n = tonumber(arg)
    if n and n > 0 then
        cfg.hubID = n
    elseif arg == "--display" then
        startDisplay = true
    elseif arg == "--enable" then
        startPitch = true
        startRoll = true
        explicitAxis = false
    elseif arg == "--pitch" then
        startPitch = true
        explicitAxis = true
    elseif arg == "--roll" then
        startRoll = true
        explicitAxis = true
    end
end
if explicitAxis then
    if startPitch == nil then startPitch = false end
    if startRoll == nil then startRoll = false end
end

cfg.display = cfg.display or {}

local display = loadOptional(modulePaths("display.lua"))
local displayEnabled = startDisplay and display ~= nil
cfg.display.enabled = displayEnabled
if startDisplay and not display then
    print("WARN: display requested but display module is missing")
end

local state = runtime.new(cfg, {
    pitchEnabled = startPitch,
    rollEnabled = startRoll
})

local running = true
local lastMonitorTouchAt = 0

local function now()
    if type(os) == "table" and type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

local function clearDisplay(message)
    if not display or type(display.clear) ~= "function" then
        return
    end
    local previous = cfg.display and cfg.display.enabled
    cfg.display.enabled = true
    local ok, err = display.clear(cfg, message)
    cfg.display.enabled = previous
    if not ok and err then
        print("DISPLAY ERR: " .. tostring(err))
    end
end

local function setDisplayEnabled(enabled)
    enabled = enabled == true
    if enabled and not display then
        print("DISPLAY ERR: display module is missing")
        displayEnabled = false
        cfg.display.enabled = false
        return
    end
    if displayEnabled == enabled then
        print("ACTION display=" .. tostring(displayEnabled))
        return
    end
    if not enabled then
        clearDisplay("DISPLAY OFF")
    end
    displayEnabled = enabled
    cfg.display.enabled = displayEnabled
    print("ACTION display=" .. tostring(displayEnabled))
end

local function applyAction(action)
    if action == "togglePitch" then
        runtime.setPitchEnabled(state, not state.pitchEnabled)
        print("ACTION pitch=" .. tostring(state.pitchEnabled) .. " roll=" .. tostring(state.rollEnabled))
    elseif action == "pitchOn" then
        runtime.setPitchEnabled(state, true)
        print("ACTION pitch=" .. tostring(state.pitchEnabled) .. " roll=" .. tostring(state.rollEnabled))
    elseif action == "pitchOff" then
        runtime.setPitchEnabled(state, false)
        print("ACTION pitch=" .. tostring(state.pitchEnabled) .. " roll=" .. tostring(state.rollEnabled))
    elseif action == "toggleRoll" then
        runtime.setRollEnabled(state, not state.rollEnabled)
        print("ACTION pitch=" .. tostring(state.pitchEnabled) .. " roll=" .. tostring(state.rollEnabled))
    elseif action == "rollOn" then
        runtime.setRollEnabled(state, true)
        print("ACTION pitch=" .. tostring(state.pitchEnabled) .. " roll=" .. tostring(state.rollEnabled))
    elseif action == "rollOff" then
        runtime.setRollEnabled(state, false)
        print("ACTION pitch=" .. tostring(state.pitchEnabled) .. " roll=" .. tostring(state.rollEnabled))
    elseif action == "load" then
        local ok, err = runtime.loadTuning(state)
        if not ok then print("LOAD ERR: " .. tostring(err)) end
    elseif action == "save" then
        local ok, err = runtime.saveTuning(state)
        if not ok then print("SAVE ERR: " .. tostring(err)) end
    elseif action == "reset" then
        runtime.reset(state)
    elseif action == "toggleDisplay" then
        setDisplayEnabled(not displayEnabled)
    elseif action == "quit" then
        running = false
        runtime.setPitchEnabled(state, false)
        runtime.setRollEnabled(state, false)
        runtime.zeroProps(state)
    end
end

local function controlLoop()
    print("Attitude SAS")
    print("hubID=" .. tostring(cfg.hubID) ..
        " pitch=" .. tostring(state.pitchEnabled) ..
        " roll=" .. tostring(state.rollEnabled) ..
        " display=" .. tostring(displayEnabled))
    print("keys: p pitch, b roll, d display, l load, s save, r reset, q quit")
    local lastPrintedErr = nil
    while running do
        local ok, err = runtime.step(state)
        if not ok and err then
            if err ~= lastPrintedErr then
                print("ERR: " .. tostring(err))
                lastPrintedErr = err
            end
        else
            if lastPrintedErr and displayEnabled then
                print("OK: link restored")
            end
            lastPrintedErr = nil
            if not displayEnabled then
                print(runtime.summary(state))
            end
        end
        sleep(state.period)
    end
end

local function displayLoop()
    local period = tonumber(cfg.display and cfg.display.period) or 0.5
    local lastErr = nil
    while running do
        if displayEnabled and display then
            local ok, err = display.draw(cfg, state)
            if not ok and err ~= lastErr then
                print("DISPLAY ERR: " .. tostring(err))
                lastErr = err
            elseif ok then
                lastErr = nil
            end
        end
        sleep(period)
    end
end

local function inputLoop()
    while running do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" and type(keys) == "table" then
            -- Printable shortcuts are handled by the char event below. Handling
            -- p/b/l/s/r/q here as well would toggle twice for one key press.
        elseif event == "char" then
            if p1 == "p" then
                applyAction("togglePitch")
            elseif p1 == "b" then
                applyAction("toggleRoll")
            elseif p1 == "d" then
                applyAction("toggleDisplay")
            elseif p1 == "l" then
                applyAction("load")
            elseif p1 == "s" then
                applyAction("save")
            elseif p1 == "r" then
                applyAction("reset")
            elseif p1 == "q" then
                applyAction("quit")
            end
        elseif event == "monitor_touch" and displayEnabled and display then
            local t = now()
            if t - lastMonitorTouchAt >= 0.6 then
                lastMonitorTouchAt = t
                local action = display.handleTouch(p2, p3)
                if action then
                    applyAction(action)
                end
            end
        end
    end
end

if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
    parallel.waitForAny(controlLoop, displayLoop, inputLoop)
else
    controlLoop()
end

runtime.setPitchEnabled(state, false)
runtime.setRollEnabled(state, false)
runtime.zeroProps(state)
print("Attitude SAS stopped")
