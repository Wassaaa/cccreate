local wrapperDir = "/report_aliases"

local aliases = {
  dir = "/rom/programs/list.lua",
  id = "/rom/programs/id.lua",
  list = "/rom/programs/list.lua",
  ls = "/rom/programs/list.lua",
}

local args = { ... }
local command = args[1] or "status"

local function writeWrapper(alias, target)
  if not fs.exists(wrapperDir) then
    fs.makeDir(wrapperDir)
  end

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
  for alias, target in pairs(aliases) do
    local wrapperPath = writeWrapper(alias, target)
    shell.setAlias(alias, wrapperPath)
    print("Reporting " .. alias)
  end

  print("Report-only shell aliases enabled for this shell.")
end

local function disable()
  for alias, _ in pairs(aliases) do
    shell.clearAlias(alias)
    print("Cleared " .. alias)
  end

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
