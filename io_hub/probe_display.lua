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

local cfg = loadFirst({ "fleet_config.lua", "io_hub/fleet_config.lua" })
local hal = loadFirst({ "hal.lua", "io_hub/hal.lua" })
local display = loadFirst({ "display.lua", "io_hub/display.lua" })

local args = { ... }
local seconds = tonumber(args[1]) or 10
local period = tonumber(args[2]) or tonumber(cfg.samplePeriod) or 0.5

local function printf(fmt, ...)
    print(string.format(fmt, ...))
end

local function printPeripherals()
    if type(peripheral) ~= "table" or type(peripheral.getNames) ~= "function" then
        print("peripheral API unavailable")
        return
    end

    local names = peripheral.getNames() or {}
    table.sort(names)
    print("wired peripherals:")
    for _, name in ipairs(names) do
        local kind = "?"
        if type(peripheral.getType) == "function" then
            local ok, value = pcall(peripheral.getType, name)
            if ok then
                kind = tostring(value)
            end
        end

        local mark = kind == "monitor" and "*" or " "
        printf("  %s %s [%s]", mark, tostring(name), kind)
    end
end

print("display probe")
printPeripherals()

local info, infoErr = display.info(cfg)
if not info then
    print("ERR: " .. tostring(infoErr))
    return
end

printf("monitor=%s size=%sx%s scale=%s",
    tostring(info.address),
    tostring(info.width),
    tostring(info.height),
    tostring(info.textScale))

local ok, err = display.drawProbe(cfg)
if not ok then
    print("ERR: " .. tostring(err))
    return
end

sleep(1)

local ticks = math.max(1, math.floor(seconds / period + 0.5))
for i = 1, ticks do
    local snap = hal.snapshot(cfg)
    local drawn, drawErr = display.drawSnapshot(cfg, snap)
    if not drawn then
        print("DRAW ERR: " .. tostring(drawErr))
        return
    end

    printf("draw %d/%d monitor=%s size=%sx%s",
        i,
        ticks,
        tostring(drawn.address),
        tostring(drawn.width),
        tostring(drawn.height))

    sleep(period)
    hal.updateActuators(cfg)
end

print("display probe finished")
