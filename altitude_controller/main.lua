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

local cfg = loadFirst({ "altitude_controller/config.lua", "config.lua" })
local tuning = loadOptional({ "altitude_controller/tuning.lua", "tuning.lua" })
if tuning then
    mergeTable(cfg, tuning)
end
local runtime = loadFirst({ "altitude_controller/runtime.lua", "runtime.lua" })

local args = { ... }
local targetAltitude = tonumber(args[1])
local startEnabled = false
local startDisplay = false
for _, arg in ipairs(args) do
    if arg == "--enable" then
        startEnabled = true
    elseif arg == "--display" then
        startDisplay = true
    end
end

cfg.display = cfg.display or {}
cfg.display.enabled = startDisplay

local display = nil
if startDisplay then
    display = loadFirst({ "altitude_controller/display.lua", "display.lua" })
end

local state = runtime.new(cfg, {
    targetAltitude = targetAltitude,
    enabled = startEnabled
})

local running = true

local function applyAction(action)
    if action == "toggle" then
        runtime.setEnabled(state, not state.enabled)
    elseif action == "up1" then
        runtime.adjustTarget(state, 1)
    elseif action == "down1" then
        runtime.adjustTarget(state, -1)
    elseif action == "up5" then
        runtime.adjustTarget(state, 5)
    elseif action == "down5" then
        runtime.adjustTarget(state, -5)
    elseif action == "mode" then
        runtime.cycleMode(state)
    elseif action == "pidOutput" then
        runtime.setPidOutputEnabled(state, not state.pidOutputEnabled)
    elseif action == "load" then
        local ok, err = runtime.loadTuning(state)
        if not ok then
            print("LOAD ERR: " .. tostring(err))
        end
    elseif action == "save" then
        local ok, err = runtime.saveTuning(state)
        if not ok then
            print("SAVE ERR: " .. tostring(err))
        end
    elseif action == "reset" then
        runtime.reset(state)
    elseif action == "quit" then
        running = false
        runtime.setEnabled(state, false)
    end
end

local function controlLoop()
    print("Altitude Controller")
    print("target=" .. tostring(state.targetAltitude) ..
        " enabled=" .. tostring(state.enabled) ..
        " display=" .. tostring(startDisplay))
    while running do
        local ok, err = runtime.step(state)
        if not ok and err then
            print("ERR: " .. tostring(err))
        elseif not startDisplay then
            print(runtime.summary(state))
        end
        sleep(state.period)
    end
end

local function displayLoop()
    if not startDisplay or not display then
        while running do
            sleep(3600)
        end
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
            if p1 == keys.space then
                applyAction("toggle")
            elseif p1 == keys.equals or p1 == keys.numPadAdd then
                applyAction("up1")
            elseif p1 == keys.minus or p1 == keys.numPadSubtract then
                applyAction("down1")
            elseif p1 == keys.m then
                applyAction("mode")
            elseif p1 == keys.p then
                applyAction("pidOutput")
            elseif p1 == keys.l then
                applyAction("load")
            elseif p1 == keys.s then
                applyAction("save")
            elseif p1 == keys.r then
                applyAction("reset")
            elseif p1 == keys.q then
                applyAction("quit")
            end
        elseif event == "char" then
            if p1 == "+" then
                applyAction("up1")
            elseif p1 == "-" then
                applyAction("down1")
            elseif p1 == "m" then
                applyAction("mode")
            elseif p1 == "p" then
                applyAction("pidOutput")
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
            local action = display.handleTouch(p2, p3)
            if action then
                applyAction(action)
            end
        end
    end
end

if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
    parallel.waitForAny(controlLoop, displayLoop, inputLoop)
else
    controlLoop()
end

runtime.setEnabled(state, false)
print("Altitude Controller stopped")
