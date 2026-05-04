local PROGRAM = "fc/main.lua"
local FALLBACK_PROGRAM = "main.lua"

-- Real-flight default:
--   compact HUD on the left 1x1 monitor
--   linked typewriter enabled
--   forward PID remains disabled until Space toggles it
local ARGS = {
    "65",
    "--compact-display",
    "--typewriter",
    "--disable"
}

local START_DELAY = 1
local RESTART_DELAY = 2
local RESTART_ON_CLEAN_EXIT = false
local SKIP_SECONDS = 1
local unpackArgs = table.unpack or unpack

local function exists(path)
    return type(fs) ~= "table" or type(fs.exists) ~= "function" or fs.exists(path)
end

local function programPath()
    if exists(PROGRAM) then
        return PROGRAM
    end
    return FALLBACK_PROGRAM
end

local function isTerminate(err)
    return tostring(err):lower():find("terminated", 1, true) ~= nil
end

local function shouldSkip()
    if SKIP_SECONDS <= 0 or type(os) ~= "table" or
        type(os.startTimer) ~= "function" or type(os.pullEventRaw) ~= "function" or
        type(keys) ~= "table" then
        return false
    end

    print("AUTO: press Shift in " .. tostring(SKIP_SECONDS) .. "s to skip")
    local timer = os.startTimer(SKIP_SECONDS)
    while true do
        local event, value = os.pullEventRaw()
        if event == "key" and (value == keys.leftShift or value == keys.rightShift) then
            return true
        end
        if event == "terminate" then
            return true
        end
        if event == "timer" and value == timer then
            return false
        end
    end
end

if shouldSkip() then
    print("AUTO: skipped")
    return
end

if START_DELAY > 0 then
    sleep(START_DELAY)
end

while true do
    local program = programPath()
    print("AUTO: starting FC")
    print("AUTO: " .. program .. " " .. table.concat(ARGS, " "))

    local ok, result = pcall(function()
        return shell.run(program, unpackArgs(ARGS))
    end)

    if not ok and isTerminate(result) then
        print("AUTO: terminated")
        break
    end

    if ok and result ~= false and not RESTART_ON_CLEAN_EXIT then
        print("AUTO: exited")
        break
    end

    if ok then
        print("AUTO: exited, restarting in " .. tostring(RESTART_DELAY) .. "s")
    else
        print("AUTO ERR: " .. tostring(result))
        print("AUTO: restarting in " .. tostring(RESTART_DELAY) .. "s")
    end
    sleep(RESTART_DELAY)
end
