local files = {
  ".wrap_commands_enabled",
  "ccwrap.lua",
  "cd",
  "copy",
  "cp",
  "del",
  "delete",
  "dir",
  "id",
  "inventory_example.lua",
  "list",
  "ls",
  "main.lua",
  "mkdir",
  "move",
  "mv",
  "path_check.lua",
  "report.lua",
  "rm",
  "startup.lua",
  "update",
  "wrap_commands.lua",
  "config",
  "lib",
}

print("This removes the project files from this ComputerCraft computer.")
write("Type reset to continue: ")

if read() ~= "reset" then
  print("Cancelled.")
  return
end

for _, path in ipairs(files) do
  if fs.exists(path) then
    print("Deleting " .. path)
    fs.delete(path)
  end
end

print("Reset complete.")
