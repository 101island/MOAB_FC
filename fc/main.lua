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

local cfg = loadFirst({ "fc/config.lua", "config.lua" })
local tuning = loadOptional({ "fc/tuning.lua", "fc_tuning.lua" })
if tuning then
    mergeTable(cfg, tuning)
end
local runtime = loadFirst({ "fc/runtime.lua", "runtime.lua" })
local typewriter = loadOptional({ "fc/typewriter.lua", "typewriter.lua" })

local args = { ... }
local targetSpeed = nil
local startEnabled = nil
local startDisplay = nil
local displayMode = nil
local startTypewriter = nil
local numericArgs = {}
local index = 1
while index <= #args do
    local arg = args[index]
    if arg == "--target" then
        targetSpeed = tonumber(args[index + 1])
        index = index + 1
    elseif arg == "--enable" then
        startEnabled = true
    elseif arg == "--disable" then
        startEnabled = false
    elseif arg == "--display" then
        startDisplay = true
    elseif arg == "--no-display" then
        startDisplay = false
    elseif arg == "--debug-display" then
        startDisplay = true
        displayMode = "debug"
    elseif arg == "--compact-display" then
        startDisplay = true
        displayMode = "compact"
    elseif arg == "--display-mode" then
        displayMode = args[index + 1]
        index = index + 1
    elseif arg == "--typewriter" then
        startTypewriter = true
    elseif arg == "--no-typewriter" then
        startTypewriter = false
    else
        local n = tonumber(arg)
        if n then
            numericArgs[#numericArgs + 1] = n
        end
    end
    index = index + 1
end
if #numericArgs >= 1 then
    cfg.hubID = numericArgs[1]
end
if #numericArgs >= 2 and targetSpeed == nil then
    targetSpeed = numericArgs[2]
end

cfg.display = cfg.display or {}
if startDisplay ~= nil then
    cfg.display.enabled = startDisplay
end
if displayMode == "debug" or displayMode == "compact" then
    cfg.display.mode = displayMode
end
cfg.typewriter = cfg.typewriter or {}
if startTypewriter ~= nil then
    cfg.typewriter.enabled = startTypewriter
end
local display = loadOptional({ "fc/display.lua", "display.lua" })
local displayEnabled = cfg.display.enabled ~= false and display ~= nil
local typewriterEnabled = cfg.typewriter and cfg.typewriter.enabled ~= false and typewriter ~= nil

local state = runtime.new(cfg, {
    targetSpeed = targetSpeed,
    enabled = startEnabled
})

local running = true

local function log(message)
    if not displayEnabled then
        print(message)
    end
end

local function clearDisplay(message)
    if not display or type(display.clear) ~= "function" then return end
    local previous = cfg.display.enabled
    cfg.display.enabled = true
    local ok, err = display.clear(cfg, message)
    cfg.display.enabled = previous
    if not ok and err then print("DISPLAY ERR: " .. tostring(err)) end
end

local function setDisplayEnabled(enabled)
    enabled = enabled == true
    if enabled and not display then
        displayEnabled = false
        cfg.display.enabled = false
        print("DISPLAY ERR: display module is missing")
        return
    end
    if not enabled then clearDisplay("DISPLAY OFF") end
    displayEnabled = enabled
    cfg.display.enabled = enabled
    print("ACTION display=" .. tostring(displayEnabled))
end

local function speedStep()
    return tonumber(cfg.keyboard and cfg.keyboard.speedStep) or 0.2
end

local function turnStep()
    return tonumber(cfg.keyboard and cfg.keyboard.turnStep) or 8
end

local function applyAction(action)
    if action == "toggle" then
        runtime.setEnabled(state, not state.enabled)
    elseif action == "speedUp" then
        runtime.adjustTarget(state, speedStep())
    elseif action == "speedDown" then
        runtime.adjustTarget(state, -speedStep())
    elseif action == "speedZero" then
        runtime.adjustTarget(state, -state.targetSpeed)
    elseif action == "turnLeft" then
        runtime.adjustTurn(state, -turnStep())
    elseif action == "turnRight" then
        runtime.adjustTurn(state, turnStep())
    elseif action == "turnZero" then
        runtime.centerTurn(state)
    elseif action == "load" then
        local ok, err = runtime.loadTuning(state)
        if not ok then log("LOAD ERR: " .. tostring(err)) end
    elseif action == "save" then
        local ok, err = runtime.saveTuning(state)
        if not ok then log("SAVE ERR: " .. tostring(err)) end
    elseif action == "reset" then
        runtime.reset(state)
    elseif action == "toggleDisplay" then
        setDisplayEnabled(not displayEnabled)
    elseif action == "quit" then
        running = false
        runtime.setEnabled(state, false)
        runtime.zeroMain(state)
    end
end

local function controlLoop()
    log("MOAB FC Forward PID")
    log("hubID=" .. tostring(cfg.hubID) ..
        " enabled=" .. tostring(state.enabled) ..
        " targetSpeed=" .. tostring(state.targetSpeed) ..
        " display=" .. tostring(displayEnabled) ..
        " typewriter=" .. tostring(typewriterEnabled))
    log("keys: space on/off, w/s speed, a/d turn, x center turn, 0 speed0")
    log("      l load, v save, r reset, m display, q quit")

    local nextPrint = 0
    while running do
        local ok, err = runtime.step(state)
        if not ok and err then
            log("ERR: " .. tostring(err))
            nextPrint = 0
        else
            local t = os.clock()
            if not displayEnabled and t >= nextPrint then
                print(runtime.summary(state))
                nextPrint = t + 0.5
            end
        end
        sleep(state.period)
    end
end

local function displayLoop()
    local period = tonumber(cfg.display and cfg.display.period) or 0.2
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

local function typewriterLoop()
    if not typewriterEnabled then
        while running do sleep(3600) end
        return
    end

    local tw = typewriter.new(cfg)
    local lastErr = nil
    while running do
        local actions, err = typewriter.poll(tw)
        if actions then
            if lastErr then
                log("TYPEWRITER OK")
                lastErr = nil
            end
            for _, action in ipairs(actions) do
                applyAction(action)
            end
        elseif err and err ~= lastErr then
            log("TYPEWRITER ERR: " .. tostring(err))
            lastErr = err
        end
        sleep(tonumber(tw.pollPeriod) or 0.05)
    end
end

local function inputLoop()
    while running do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "key" and type(keys) == "table" then
            if p1 == keys.space then
                applyAction("toggle")
            end
        elseif event == "char" then
            if p1 == "w" then
                applyAction("speedUp")
            elseif p1 == "s" then
                applyAction("speedDown")
            elseif p1 == "a" then
                applyAction("turnLeft")
            elseif p1 == "d" then
                applyAction("turnRight")
            elseif p1 == "x" then
                applyAction("turnZero")
            elseif p1 == "0" then
                applyAction("speedZero")
            elseif p1 == "l" then
                applyAction("load")
            elseif p1 == "v" then
                applyAction("save")
            elseif p1 == "r" then
                applyAction("reset")
            elseif p1 == "m" then
                applyAction("toggleDisplay")
            elseif p1 == "q" then
                applyAction("quit")
            end
        elseif event == "monitor_touch" and displayEnabled and display then
            local action = display.handleTouch(p2, p3)
            if action then
                applyAction(action)
            end
        end
    end
end

if type(parallel) == "table" and type(parallel.waitForAny) == "function" then
    parallel.waitForAny(controlLoop, displayLoop, inputLoop, typewriterLoop)
else
    controlLoop()
end

runtime.setEnabled(state, false)
runtime.zeroMain(state)
log("FC stopped")
