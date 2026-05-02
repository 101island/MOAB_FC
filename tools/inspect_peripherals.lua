local args = { ... }
local target = args[1]
local outPath
local page = false

for i = 1, #args do
    if args[i] == "--out" then
        outPath = args[i + 1]
    elseif args[i] == "--page" then
        page = true
    end
end

if target == "--out" or target == "--page" then
    target = nil
end

local lines = {}

local function emit(text)
    lines[#lines + 1] = text
end

local function printMethods(name)
    local ok, methods = pcall(peripheral.getMethods, name)
    if not ok or type(methods) ~= "table" then
        emit("  methods: <unavailable>")
        return
    end

    table.sort(methods)
    for _, method in ipairs(methods) do
        emit("  - " .. method)
    end
end

if type(peripheral) ~= "table" then
    error("peripheral API is unavailable")
end

if target and target ~= "" then
    emit(target .. " [" .. tostring(peripheral.getType(target)) .. "]")
    printMethods(target)
else
    local names = peripheral.getNames()
    table.sort(names)

    for _, name in ipairs(names) do
        emit(name .. " [" .. tostring(peripheral.getType(name)) .. "]")
        printMethods(name)
        emit("")
    end
end

if outPath and outPath ~= "" then
    local file = fs.open(outPath, "w")
    if not file then
        error("cannot open output file: " .. tostring(outPath))
    end
    for _, line in ipairs(lines) do
        file.writeLine(line)
    end
    file.close()
    print("written " .. outPath)
elseif page then
    local _, height = term.getSize()
    local pageSize = math.max(1, height - 2)
    for i, line in ipairs(lines) do
        print(line)
        if i % pageSize == 0 and i < #lines then
            write("-- more --")
            os.pullEvent("key")
            print("")
        end
    end
else
    for _, line in ipairs(lines) do
        print(line)
    end
end
