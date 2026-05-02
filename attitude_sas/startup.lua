local program = "attitude_sas/main.lua"
if fs and not fs.exists(program) then
    program = "main.lua"
end

shell.run(program, ...)
