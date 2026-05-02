local program = "io_hub/main.lua"

if fs and not fs.exists(program) then
    program = "main.lua"
end

while true do
    local ok, err = pcall(function()
        shell.run(program)
    end)

    print("IO Hub exited: " .. tostring(err))
    sleep(2)
end
