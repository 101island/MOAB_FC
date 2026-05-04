local M = {}

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

local rednetUtil = loadFirst(modulePaths("rednet_util.lua"))

local function now()
    if type(os) == "table" and type(os.epoch) == "function" then
        return os.epoch("utc") / 1000
    end
    if type(os) == "table" and type(os.clock) == "function" then
        return os.clock()
    end
    return 0
end

local function hubID(cfg)
    local id = tonumber(cfg and cfg.hubID)
    if id == nil or id <= 0 then
        return nil, "missing IO Hub computer ID"
    end
    return id
end

local sequence = 0

local function nextRequestId()
    sequence = sequence + 1
    local id = "attitude"
    if type(os) == "table" and type(os.getComputerID) == "function" then
        id = tostring(os.getComputerID())
    end
    return id .. ":" .. tostring(now()) .. ":" .. tostring(sequence)
end

local function copyMessage(msg)
    local out = {}
    for key, value in pairs(msg or {}) do
        out[key] = value
    end
    return out
end

local function drain(protocol)
    while true do
        local sender = rednet.receive(protocol, 0)
        if not sender then
            return
        end
    end
end

function M.open(cfg)
    return rednetUtil.open((cfg and cfg.modemSide) or "auto")
end

function M.request(cfg, msg, timeout)
    local opened, openErr = M.open(cfg)
    if not opened then
        return nil, openErr
    end

    local id, idErr = hubID(cfg)
    if not id then
        return nil, idErr
    end

    local protocol = (cfg and cfg.protocol) or "moab_fc_v1"
    local waitSeconds = tonumber(timeout) or tonumber(cfg and cfg.timeout) or 3
    local requestId = nextRequestId()
    local outbound = copyMessage(msg)
    outbound.requestId = requestId

    drain(protocol)
    rednet.send(id, outbound, protocol)

    local deadline = now() + waitSeconds
    while true do
        local remaining = deadline - now()
        if remaining <= 0 then
            return nil, "timeout waiting for IO Hub"
        end

        local sender, reply = rednet.receive(protocol, remaining)
        if sender == id then
            if type(reply) ~= "table" then
                return nil, "invalid IO Hub reply"
            end
            if reply.requestId == requestId then
                if reply.ok == false then
                    return nil, reply.err or "IO Hub request failed", reply
                end
                return reply.result, nil, reply
            elseif reply.requestId == nil and reply.type == "reply" then
                -- Older IO Hub builds did not echo requestId. Accept after drain().
                if reply.ok == false then
                    return nil, reply.err or "IO Hub request failed", reply
                end
                return reply.result, nil, reply
            end
        end
    end
end

function M.snapshot(cfg)
    local result, err, reply = M.request(cfg, { type = "get_snapshot" })
    if not result then
        return nil, err, reply
    end
    if type(result.sensors) ~= "table" or type(result.actuators) ~= "table" then
        return nil, "invalid IO Hub snapshot reply", reply
    end
    return result, nil, reply
end

function M.snapshotSome(cfg, sensorNames, actuatorNames)
    local result, err, reply = M.request(cfg, {
        type = "get_snapshot_some",
        sensors = sensorNames or {},
        actuators = actuatorNames or {}
    })
    if not result then
        return nil, err, reply
    end
    if type(result.sensors) ~= "table" or type(result.actuators) ~= "table" then
        return nil, "invalid IO Hub snapshot reply", reply
    end
    return result, nil, reply
end

function M.exchange(cfg, options)
    options = options or {}
    local result, err, reply = M.request(cfg, {
        type = "exchange",
        readSensors = options.readSensors or options.sensors or {},
        readActuators = options.readActuators or options.actuators or {},
        writeActuators = options.writeActuators
    })
    if not result then
        return nil, err, reply
    end
    if type(result.sensors) ~= "table" or type(result.actuators) ~= "table" then
        return nil, "invalid IO Hub exchange reply", reply
    end
    return result, nil, reply
end

function M.ping(cfg)
    return M.request(cfg, { type = "ping" })
end

function M.getConfig(cfg)
    return M.request(cfg, { type = "get_config" })
end

function M.readSensors(cfg)
    return M.request(cfg, { type = "read_sensors" })
end

function M.readSensorsSome(cfg, names)
    return M.request(cfg, {
        type = "read_sensors_some",
        names = names or {}
    })
end

function M.readActuators(cfg)
    return M.request(cfg, { type = "read_actuators" })
end

function M.readActuatorsSome(cfg, names)
    return M.request(cfg, {
        type = "read_actuators_some",
        names = names or {}
    })
end

function M.readActuatorsCached(cfg, names)
    return M.request(cfg, {
        type = "read_actuators_cached",
        names = names or {}
    })
end

function M.writeActuator(cfg, name, value)
    return M.request(cfg, {
        type = "write_actuator",
        name = name,
        value = value
    })
end

function M.writeActuators(cfg, values)
    return M.request(cfg, {
        type = "write_actuators",
        values = values
    })
end

return M
