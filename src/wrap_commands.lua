local flagPath = "/.wrap_commands_enabled"

local staleAliases = {
  "cd",
  "cp",
  "copy",
  "del",
  "delete",
  "dir",
  "id",
  "list",
  "ls",
  "mkdir",
  "move",
  "mv",
  "rm",
}

for _, alias in ipairs(staleAliases) do
  shell.clearAlias(alias)
end

if fs.exists(flagPath) then
  fs.delete(flagPath)
end

print("Command wrapping is disabled.")
print("Use report run <command> for captured command output.")
