-- Simple CC:Tweaked updater.
-- Edit these values after you create your GitHub repository.
local githubUser = "Wassaaa"
local githubRepo = "cccreate"
local branch = "main"
local basePath = "src"
local updaterPath = "/update"

local baseUrl = "https://raw.githubusercontent.com/" .. githubUser .. "/" .. githubRepo .. "/" .. branch .. "/" .. basePath .. "/"
local updaterUrl = "https://raw.githubusercontent.com/" .. githubUser .. "/" .. githubRepo .. "/" .. branch .. "/update.lua"

local files = {
  "startup.lua",
  "ccwrap.lua",
  "main.lua",
  "inventory_example.lua",
  "ap_inventory_manager_test.lua",
  "tom_gpu_terminal.lua",
  "requester_test.lua",
  "path_check.lua",
  "reset_project.lua",
  "report.lua",
  "report_shell.lua",
  "wrap_commands.lua",
  "config/webhook.example.lua",
  "lib/diagnostics.lua",
  "lib/tom_gpu_term.lua",
  "lib/inventory_tools.lua",
  "lib/logger.lua",
  "lib/reporter.lua",
}

local staleFiles = {
  "/.wrap_commands_enabled",
  "/cd",
  "/copy",
  "/cp",
  "/del",
  "/delete",
  "/dir",
  "/id",
  "/list",
  "/ls",
  "/mkdir",
  "/move",
  "/mv",
  "/rm",
}

local temporaryAliases = {
  "dir",
  "id",
  "list",
  "ls",
}

local args = { ... }
local skipSelfUpdate = args[1] == "--no-self-update"

local function installPath(path)
  return fs.combine("/", path)
end

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
  local targetPath = installPath(path)

  print("Downloading " .. path)

  local contents = downloadText(url)
  writeFile(targetPath, contents)

  print("Updated " .. path)
end

local function restoreReportShellAliases()
  local wrapperDir = "/report_aliases"
  local originalAliasesPath = "/report_aliases/original_aliases.lua"
  local originals = nil

  if not fs.exists(wrapperDir) then
    return
  end

  if fs.exists(originalAliasesPath) then
    local handle = fs.open(originalAliasesPath, "r")
    if handle then
      originals = textutils.unserialize(handle.readAll())
      handle.close()
    end
  end

  for _, alias in ipairs(temporaryAliases) do
    if shell.aliases()[alias] then
      print("Clearing temporary alias " .. alias)
      shell.clearAlias(alias)
    end
  end

  if originals then
    for alias, target in pairs(originals) do
      if target then
        print("Restoring original alias " .. alias)
        shell.setAlias(alias, target)
      end
    end
  end

  print("Removing report shell wrappers")
  fs.delete(wrapperDir)
end

if selfUpdate() then
  return
end

print("Updating from " .. githubUser .. "/" .. githubRepo .. " (" .. branch .. ")")

restoreReportShellAliases()

for _, path in ipairs(staleFiles) do
  if fs.exists(path) then
    print("Removing stale " .. path)
    fs.delete(path)
  end
end

for _, path in ipairs(files) do
  downloadFile(path)
end

print("Update complete. Run reboot if startup changed.")
print("Run report_shell enable to re-enable report-only aliases.")
