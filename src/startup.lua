-- Runs automatically when the ComputerCraft computer boots.

if fs.exists(".wrap_commands_enabled") then
  shell.run("wrap_commands", "install")
end

shell.run("main")
