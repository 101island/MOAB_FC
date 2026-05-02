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

local cfg = loadFirst({ "attitude_sas/config.lua", "attitude_config.lua" })
local tuning = loadOptional({ "attitude_sas/tuning.lua", "attitude_tuning.lua" })
if tuning then
    mergeTable(cfg, tuning)
end

local runtime = loadFirst({ "attitude_sas/runtime.lua", "attitude_runtime.lua" })

local args = { ... }
local startDisplay = false
local startPitch = nil
local startRoll = nil
for _, arg in ipairs(args) do
    local n = tonumber(arg)
    if n and n > 0 then
        cfg.hubID = n
    elseif arg == "--display" then
        startDisplay = true
    elseif arg == "--enable" then
        startPitch = true
        startRoll = true
    elseif arg == "--pitch" then
        startPitch = true
    elseif arg == "--roll" then
        startRoll = true
    end
end

cfg.display = cfg.display or {}
cfg.display.enabled = startDisplay

local display = nil
if startDisplay then
    display = loadFirst({ "attitude_sas/display.lua", "attitude_display.lua" })
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
        " display=" .. tostring(startDisplay))
    local lastPrintedErr = nil
    while running do
        local ok, err = runtime.step(state)
        if not ok and err then
            if err ~= lastPrintedErr then
                print("ERR: " .. tostring(err))
                lastPrintedErr = err
            end
        else
            if lastPrintedErr and startDisplay then
                print("OK: link restored")
            end
            lastPrintedErr = nil
            if not startDisplay then
                print(runtime.summary(state))
            end
        end
        sleep(state.period)
    end
end

local function displayLoop()
    if not startDisplay or not display then
        while running do sleep(3600) end
    end
    local period = tonumber(cfg.display and cfg.display.period) or 0.5
    local lastErr = nil
    while running do
        local ok, err = display.draw(cfg, state)
        if not ok and err ~= lastErr then
            print("DISPLAY ERR: " .. tostring(err))
            lastErr = err
        elseif ok then
            lastErr = nil
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
            elseif p1 == "l" then
                applyAction("load")
            elseif p1 == "s" then
                applyAction("save")
            elseif p1 == "r" then
                applyAction("reset")
            elseif p1 == "q" then
                applyAction("quit")
            end
        elseif event == "monitor_touch" and startDisplay and display then
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
