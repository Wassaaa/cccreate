local wrapperDir = "/report_aliases"
local originalAliasesPath = fs.combine(wrapperDir, "original_aliases.lua")

local aliases = {
  dir = "/rom/programs/list.lua",
  id = "/rom/programs/id.lua",
  list = "/rom/programs/list.lua",
  ls = "/rom/programs/list.lua",
}

local args = { ... }
local command = args[1] or "status"

local function ensureWrapperDir()
  if not fs.exists(wrapperDir) then
    fs.makeDir(wrapperDir)
  end
end

local function saveOriginalAliases()
  ensureWrapperDir()

  if fs.exists(originalAliasesPath) then
    return
  end

  local currentAliases = shell.aliases()
  local originals = {}

  for alias, _ in pairs(aliases) do
    originals[alias] = currentAliases[alias] or false
  end

  local handle = fs.open(originalAliasesPath, "w")
  if not handle then
    error("Failed to save original aliases", 0)
  end

  handle.write(textutils.serialize(originals))
  handle.close()
end

local function loadOriginalAliases()
  if not fs.exists(originalAliasesPath) then
    return nil
  end

  local handle = fs.open(originalAliasesPath, "r")
  if not handle then
    return nil
  end

  local contents = handle.readAll()
  handle.close()

  return textutils.unserialize(contents)
end

local function restoreOriginalAliases()
  local originals = loadOriginalAliases()

  for alias, _ in pairs(aliases) do
    shell.clearAlias(alias)
  end

  if not originals then
    return
  end

  for alias, target in pairs(originals) do
    if target then
      shell.setAlias(alias, target)
      print("Restored " .. alias)
    else
      print("Cleared " .. alias)
    end
  end
end

local function writeWrapper(alias, target)
  ensureWrapperDir()

  local path = fs.combine(wrapperDir, alias)
  local handle = fs.open(path, "w")
  if not handle then
    error("Failed to create " .. path, 0)
  end

  handle.writeLine("local args = { ... }")
  handle.writeLine("local unpackArgs = table.unpack or unpack")
  handle.writeLine('shell.run("/ccwrap.lua", "--quiet", "' .. target .. '", unpackArgs(args))')
  handle.close()

  return path
end

local function enable()
  saveOriginalAliases()

  for alias, target in pairs(aliases) do
    local wrapperPath = writeWrapper(alias, target)
    shell.setAlias(alias, wrapperPath)
    print("Reporting " .. alias)
  end

  print("Report-only shell aliases enabled for this shell.")
end

local function disable()
  restoreOriginalAliases()

  if fs.exists(wrapperDir) then
    fs.delete(wrapperDir)
  end

  print("Report-only shell aliases disabled.")
end

local function status()
  for alias, _ in pairs(aliases) do
    print(alias .. " -> " .. tostring(shell.aliases()[alias]))
  end
end

if command == "enable" then
  enable()
elseif command == "disable" then
  disable()
elseif command == "status" then
  status()
else
  print("Usage: report_shell enable|disable|status")
end
