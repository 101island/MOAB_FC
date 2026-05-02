local program = "altitude_controller/main.lua"
if fs and not fs.exists(program) then
    program = "main.lua"
end

shell.run(program, ...)
