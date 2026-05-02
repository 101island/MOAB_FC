local M = {}

function M.sortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return keys
end

function M.cloneShallow(tbl)
    local out = {}
    for key, value in pairs(tbl or {}) do
        out[key] = value
    end
    return out
end

return M
