-- Simple CC:Tweaked updater.
-- Edit these values after you create your GitHub repository.
local githubUser = "Wassaaa"
local githubRepo = "cccreate"
local branch = "main"
local basePath = "src"
local updaterPath = "update"

local baseUrl = "https://raw.githubusercontent.com/" .. githubUser .. "/" .. githubRepo .. "/" .. branch .. "/" .. basePath .. "/"
local updaterUrl = "https://raw.githubusercontent.com/" .. githubUser .. "/" .. githubRepo .. "/" .. branch .. "/update.lua"

local files = {
  "startup.lua",
  "main.lua",
  "inventory_example.lua",
  "report.lua",
  "config/webhook.example.lua",
  "lib/diagnostics.lua",
  "lib/inventory_tools.lua",
  "lib/logger.lua",
  "lib/reporter.lua",
}

local args = { ... }
local skipSelfUpdate = args[1] == "--no-self-update"

local function ensureFolder(path)
  local folder = fs.getDir(path)

  if folder ~= "" and not fs.exists(folder) then
    print("Creating folder: " .. folder)
    fs.makeDir(folder)
  end
end

local function readFile(path)
  if not fs.exists(path) then
    return nil
  end

  local handle = fs.open(path, "r")
  if not handle then
    return nil
  end

  local contents = handle.readAll()
  handle.close()

  return contents
end

local function writeFile(path, contents)
  ensureFolder(path)

  local handle = fs.open(path, "w")
  if not handle then
    error("Failed to open " .. path .. " for writing", 0)
  end

  handle.write(contents)
  handle.close()
end

local function downloadText(url)
  local response, errorMessage = http.get(url)
  if not response then
    error("Failed to download " .. url .. ": " .. tostring(errorMessage), 0)
  end

  local contents = response.readAll()
  response.close()

  return contents
end

local function selfUpdate()
  if skipSelfUpdate then
    return false
  end

  print("Checking updater...")

  local latest = downloadText(updaterUrl)
  local current = readFile(updaterPath)

  if current == latest then
    print("Updater is already current.")
    return false
  end

  writeFile(updaterPath, latest)

  print("Updater changed. Restarting updater...")
  shell.run(updaterPath, "--no-self-update")
  return true
end

local function downloadFile(path)
  local url = baseUrl .. path

  print("Downloading " .. path)

  local contents = downloadText(url)
  writeFile(path, contents)

  print("Updated " .. path)
end

if selfUpdate() then
  return
end

print("Updating from " .. githubUser .. "/" .. githubRepo .. " (" .. branch .. ")")

for _, path in ipairs(files) do
  downloadFile(path)
end

print("Update complete. Run reboot to restart.")
