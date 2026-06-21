-- One-time repair script for removing the old command wrapper experiment.
-- Download with:
-- wget https://raw.githubusercontent.com/Wassaaa/cccreate/main/repair.lua repair_once
-- repair_once

local githubUser = "Wassaaa"
local githubRepo = "cccreate"
local branch = "main"

local updaterUrl = "https://raw.githubusercontent.com/" .. githubUser .. "/" .. githubRepo .. "/" .. branch .. "/update.lua"

local staleNames = {
  ".wrap_commands_enabled",
  "cd",
  "copy",
  "cp",
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

local function downloadText(url)
  local response, errorMessage = http.get(url)
  if not response then
    error("Failed to download " .. url .. ": " .. tostring(errorMessage), 0)
  end

  local contents = response.readAll()
  response.close()
  return contents
end

local function writeFile(path, contents)
  local handle = fs.open(path, "w")
  if not handle then
    error("Failed to write " .. path, 0)
  end

  handle.write(contents)
  handle.close()
end

print("Repairing ComputerCraft project install...")

for _, name in ipairs(staleNames) do
  shell.clearAlias(name)
end

for _, name in ipairs(staleNames) do
  local path = "/" .. name
  if fs.exists(path) then
    print("Deleting stale " .. path)
    fs.delete(path)
  end
end

print("Refreshing updater...")
writeFile("/update", downloadText(updaterUrl))

print("Running updater...")
shell.run("/update", "--no-self-update")

print("Repair complete. Run reboot.")
