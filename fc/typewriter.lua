local M = {}

local function now()
    if type(os) == "table" and type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

local function config(cfg)
    return cfg and cfg.typewriter or {}
end

local function isLinkedTypewriter(name)
    if type(peripheral) ~= "table" or type(peripheral.getType) ~= "function" then
        return false
    end
    local ok, kind = pcall(peripheral.getType, name)
    if not ok then return false end
    if kind == "linked_typewriter" then return true end
    if type(kind) == "table" then
        for _, item in ipairs(kind) do
            if item == "linked_typewriter" then return true end
        end
    end
    return false
end

local function wrapByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    if type(peripheral) ~= "table" or type(peripheral.wrap) ~= "function" then return nil end
    local device = peripheral.wrap(name)
    if device and isLinkedTypewriter(name) then
        return device, name
    end
    return nil
end

function M.open(cfg)
    local spec = config(cfg)
    if spec.enabled == false then
        return nil, "typewriter disabled"
    end
    if type(peripheral) ~= "table" then
        return nil, "peripheral API unavailable"
    end

    local device, address = wrapByName(spec.remoteName)
    if device then return device, nil, address end

    device, address = wrapByName(spec.side or "top")
    if device then return device, nil, address end

    if type(peripheral.find) == "function" then
        device = peripheral.find("linked_typewriter")
        if device then return device, nil, "linked_typewriter" end
    end

    return nil, "cannot find linked_typewriter"
end

local function readSet(device)
    local ok, list = pcall(device.getPressedKeyCodes)
    if not ok then return nil, list end
    local set = {}
    for _, code in ipairs(list or {}) do
        local n = tonumber(code)
        if n then set[n] = true end
    end
    return set
end

function M.new(cfg)
    local spec = config(cfg)
    return {
        cfg = cfg,
        pollPeriod = tonumber(spec.pollPeriod) or 0.05,
        repeatDelay = tonumber(spec.repeatDelay) or 0.3,
        repeatPeriod = tonumber(spec.repeatPeriod) or 0.12,
        previous = {},
        nextRepeat = {},
        device = nil,
        address = nil,
        lastErr = nil
    }
end

function M.poll(state)
    if type(state) ~= "table" then
        return nil, "missing typewriter state"
    end

    if not state.device then
        local device, err, address = M.open(state.cfg)
        if not device then
            state.lastErr = err
            return nil, err
        end
        state.device = device
        state.address = address
        state.lastErr = nil
    end

    local current, err = readSet(state.device)
    if not current then
        state.device = nil
        state.lastErr = err
        return nil, err
    end

    local spec = config(state.cfg)
    local keys = spec.keys or {}
    local repeatActions = spec.repeatActions or {}
    local timestamp = now()
    local actions = {}

    for code in pairs(current) do
        local action = keys[code]
        if action then
            local firstPress = not state.previous[code]
            local repeatable = repeatActions[action] == true
            local due = repeatable and timestamp >= (state.nextRepeat[code] or 0)
            if firstPress or due then
                actions[#actions + 1] = action
                if repeatable then
                    state.nextRepeat[code] = timestamp + (firstPress and state.repeatDelay or state.repeatPeriod)
                end
            end
        end
    end

    for code in pairs(state.previous) do
        if not current[code] then
            state.nextRepeat[code] = nil
        end
    end

    state.previous = current
    state.lastErr = nil
    return actions
end

return M
