local args = { ... }

local hubID = tonumber(args[1])
local modemSide = args[2] or "top"
local command = args[3] or "snapshot"
local defaultProtocol = "moab_fc_v1"
local protocol = defaultProtocol

if not hubID then
    print("Usage:")
    print("  io_client.lua <hubID> <modemSide> snapshot [protocol]")
    print("  io_client.lua <hubID> <modemSide> ping [protocol]")
    print("  io_client.lua <hubID> <modemSide> write <name> <value> [protocol]")
    print("  io_client.lua <hubID> <modemSide> stop [protocol]")
    return
end

local function request(msg)
    rednet.send(hubID, msg, protocol)
    local sender, reply = rednet.receive(protocol, 3)
    if sender ~= hubID then
        print("ERR: no reply from hub")
        return nil
    end
    return reply
end

local function dump(value, indent)
    indent = indent or ""
    if type(value) ~= "table" then
        print(indent .. tostring(value))
        return
    end
    for key, item in pairs(value) do
        if type(item) == "table" then
            print(indent .. tostring(key) .. ":")
            dump(item, indent .. "  ")
        else
            print(indent .. tostring(key) .. " = " .. tostring(item))
        end
    end
end

rednet.open(modemSide)

local msg
if command == "ping" then
    protocol = args[4] or defaultProtocol
    msg = { type = "ping" }
elseif command == "write" then
    protocol = args[6] or defaultProtocol
    msg = {
        type = "write_actuator",
        name = args[4],
        value = tonumber(args[5])
    }
elseif command == "stop" then
    protocol = args[4] or defaultProtocol
    msg = { type = "stop_all" }
else
    protocol = args[4] or defaultProtocol
    msg = { type = "get_snapshot" }
end

local reply = request(msg)
if reply then
    dump(reply)
end
