-- Simple CC:Tweaked updater.
local githubUser = "Wassaaa"
local githubRepo = "cccreate"
local branch = "main"
local srcRoot = "src"
local baseSource = srcRoot .. "/base"
local projectsSource = srcRoot .. "/projects"
local updaterPath = "/update"

local apiRoot = "https://api.github.com/repos/" .. githubUser .. "/" .. githubRepo .. "/contents/"
local rawRef = branch
local rawRoot = "https://raw.githubusercontent.com/" .. githubUser .. "/" .. githubRepo .. "/" .. rawRef .. "/"
local updaterUrl = rawRoot .. "update.lua"
local unpackArgs = table.unpack or unpack

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
  "/lib/tom_gpu_term.lua",
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

if skipSelfUpdate then
  table.remove(args, 1)
end

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

local function writeFile(path, contents, binary)
  ensureFolder(path)

  local handle = fs.open(path, binary and "wb" or "w")
  if not handle then
    error("Failed to open " .. path .. " for writing", 0)
  end

  handle.write(contents)
  handle.close()
end

local function requestHeaders()
  return {
    ["Accept"] = "application/vnd.github+json",
    ["User-Agent"] = "cccreate-updater",
  }
end

local function download(url, binary)
  local response, errorMessage = http.get(url, requestHeaders(), binary)
  if not response then
    error("Failed to download " .. url .. ": " .. tostring(errorMessage), 0)
  end

  local contents = response.readAll()
  response.close()

  return contents
end

local function downloadText(url)
  return download(url, false)
end

local function contentUrl(path)
  return apiRoot .. path .. "?ref=" .. branch
end

local function refUrl()
  return "https://api.github.com/repos/" .. githubUser .. "/" .. githubRepo .. "/git/ref/heads/" .. branch
end

local function decodeJson(contents, url)
  local decoded = textutils.unserializeJSON(contents)

  if type(decoded) ~= "table" then
    error("GitHub returned invalid JSON for " .. url, 0)
  end

  return decoded
end

local function listGitHub(path)
  local url = contentUrl(path)
  return decodeJson(downloadText(url), url)
end

local function resolveRawRef()
  local url = refUrl()
  local ref = decodeJson(downloadText(url), url)

  if type(ref.object) == "table" and type(ref.object.sha) == "string" then
    rawRef = ref.object.sha
    rawRoot = "https://raw.githubusercontent.com/" .. githubUser .. "/" .. githubRepo .. "/" .. rawRef .. "/"
    updaterUrl = rawRoot .. "update.lua"
  end
end

local function isBinary(path)
  local lower = string.lower(path)
  return lower:match("%.png$") ~= nil
    or lower:match("%.jpg$") ~= nil
    or lower:match("%.jpeg$") ~= nil
    or lower:match("%.gif$") ~= nil
    or lower:match("%.webp$") ~= nil
    or lower:match("%.nbt$") ~= nil
end

local function shouldInstall(path)
  local name = fs.getName(path)
  return name ~= "AGENTS.md"
end

local function relativeInstallPath(sourceRoot, sourcePath)
  if sourcePath == sourceRoot then
    return ""
  end

  return string.sub(sourcePath, string.len(sourceRoot) + 2)
end

local function collectFiles(sourceRoot, sourcePath, results)
  results = results or {}

  for _, entry in ipairs(listGitHub(sourcePath)) do
    if entry.type == "dir" then
      collectFiles(sourceRoot, entry.path, results)
    elseif entry.type == "file" then
      local targetPath = relativeInstallPath(sourceRoot, entry.path)
      if shouldInstall(targetPath) then
        table.insert(results, {
          sourcePath = entry.path,
          targetPath = targetPath,
          url = rawRoot .. entry.path,
          binary = isBinary(entry.path),
        })
      end
    end
  end

  return results
end

local function availableProjects()
  local projects = {}

  for _, entry in ipairs(listGitHub(projectsSource)) do
    if entry.type == "dir" then
      table.insert(projects, entry.name)
    end
  end

  table.sort(projects)
  return projects
end

local function hasProject(projects, name)
  for _, project in ipairs(projects) do
    if project == name then
      return true
    end
  end

  return false
end

local function selectedProjects()
  local selected = {}
  local listOnly = false

  if #args == 0 then
    return selected, nil, listOnly
  end

  local projects = availableProjects()

  for _, arg in ipairs(args) do
    if arg == "--list" then
      listOnly = true
    elseif arg == "all" then
      selected = projects
    elseif hasProject(projects, arg) then
      table.insert(selected, arg)
    else
      error("Unknown project: " .. arg .. ". Run update --list.", 0)
    end
  end

  return selected, projects, listOnly
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
  shell.run(updaterPath, "--no-self-update", unpackArgs(args))
  return true
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

local function downloadFile(entry)
  print("Downloading " .. entry.sourcePath .. " -> " .. entry.targetPath)

  local contents = download(entry.url, entry.binary)
  writeFile(installPath(entry.targetPath), contents, entry.binary)

  print("Updated " .. entry.targetPath)
end

local function installSource(label, sourceRoot)
  print("Updating " .. label .. " from " .. sourceRoot)

  local files = collectFiles(sourceRoot, sourceRoot)
  table.sort(files, function(a, b)
    return a.targetPath < b.targetPath
  end)

  for _, file in ipairs(files) do
    downloadFile(file)
  end
end

local function printProjects(projects)
  print("Available projects:")

  for _, project in ipairs(projects) do
    print("- " .. project)
  end
end

resolveRawRef()

if selfUpdate() then
  return
end

local projectsToInstall, projects, listOnly = selectedProjects()

if listOnly then
  printProjects(projects)
  return
end

print("Updating from " .. githubUser .. "/" .. githubRepo .. " (" .. branch .. " " .. string.sub(rawRef, 1, 7) .. ")")

restoreReportShellAliases()

for _, path in ipairs(staleFiles) do
  if fs.exists(path) then
    print("Removing stale " .. path)
    fs.delete(path)
  end
end

installSource("base", baseSource)

if #projectsToInstall == 0 then
  print("No project selected. Run update --list, update <project>, or update all.")
else
  for _, project in ipairs(projectsToInstall) do
    installSource("project " .. project, projectsSource .. "/" .. project)
  end
end

print("Update complete. Run reboot if startup changed.")
print("Run report_shell enable to re-enable report-only aliases.")
