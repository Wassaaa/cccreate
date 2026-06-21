local commands = {
  "ls",
  "list",
  "rm",
  "delete",
  "cd",
  "ccwrap",
  "report",
  "update",
}

print("Shell path: " .. shell.path())
print("Current dir: " .. shell.dir())

for _, command in ipairs(commands) do
  print(command .. " -> " .. tostring(shell.resolveProgram(command)))
end
