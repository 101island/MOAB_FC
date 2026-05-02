local outPath = ... or "inspect.txt"

if type(peripheral) ~= "table" then
    error("peripheral API is unavailable")
end

local file = fs.open(outPath, "w")
if not file then
    error("cannot open output file: " .. tostring(outPath))
end

local function writeLine(text)
    file.writeLine(text)
end

local function writeMethods(name)
    local ok, methods = pcall(peripheral.getMethods, name)
    if not ok or type(methods) ~= "table" then
        writeLine("  methods: <unavailable>")
        return
    end

    table.sort(methods)
    for _, method in ipairs(methods) do
        writeLine("  - " .. method)
    end
end

local names = peripheral.getNames()
table.sort(names)

for _, name in ipairs(names) do
    writeLine(name .. " [" .. tostring(peripheral.getType(name)) .. "]")
    writeMethods(name)
    writeLine("")
end

file.close()
print("written " .. outPath)
