local M = {}

local SIDES = { "left", "right", "front", "back", "top", "bottom" }

local function hasModem(side)
    if type(peripheral) ~= "table" then
        return false
    end

    if type(peripheral.hasType) == "function" then
        local ok, result = pcall(peripheral.hasType, side, "modem")
        if ok and result then
            return true
        end
    end

    if type(peripheral.getType) == "function" then
        local ok, kind = pcall(peripheral.getType, side)
        if ok then
            if kind == "modem" then
                return true
            end
            if type(kind) == "table" then
                for _, item in ipairs(kind) do
                    if item == "modem" then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function tryOpen(side)
    if type(rednet.isOpen) == "function" and rednet.isOpen(side) then
        return true
    end

    local ok = pcall(rednet.open, side)
    if ok then
        return true
    end
    return false
end

function M.open(preferredSide)
    if type(rednet) ~= "table" then
        return nil, "rednet API is unavailable"
    end

    if type(preferredSide) == "string" and preferredSide ~= "" and preferredSide ~= "auto" then
        if tryOpen(preferredSide) then
            return preferredSide
        end
    end

    for _, side in ipairs(SIDES) do
        if hasModem(side) and tryOpen(side) then
            return side
        end
    end

    for _, side in ipairs(SIDES) do
        if tryOpen(side) then
            return side
        end
    end

    return nil, "no local modem found on any computer side"
end

return M
