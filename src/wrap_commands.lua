local commandMap = {
  cd = "/rom/programs/cd.lua",
  cp = "/rom/programs/copy.lua",
  copy = "/rom/programs/copy.lua",
  del = "/rom/programs/delete.lua",
  delete = "/rom/programs/delete.lua",
  dir = "/rom/programs/list.lua",
  id = "/rom/programs/id.lua",
  list = "/rom/programs/list.lua",
  ls = "/rom/programs/list.lua",
  mkdir = "/rom/programs/mkdir.lua",
  move = "/rom/programs/move.lua",
  mv = "/rom/programs/move.lua",
  rm = "/rom/programs/delete.lua",
}

local flagPath = ".wrap_commands_enabled"

local args = { ... }
local command = args[1] or "status"

local function exists(path)
  return fs.exists(path)
end

local function install()
  for alias, target in pairs(commandMap) do
    if exists(target) then
      shell.setAlias(alias, "ccwrap " .. target)
      print("Wrapped " .. alias .. " -> " .. target)
    else
      print("Skipped " .. alias .. ": missing " .. target)
    end
  end
end

local function uninstall()
  for alias, _ in pairs(commandMap) do
    shell.clearAlias(alias)
    print("Cleared " .. alias)
  end
end

local function setEnabled(enabled)
  if enabled then
    local handle = fs.open(flagPath, "w")
    if handle then
      handle.write("true")
      handle.close()
    end
    print("Command wrapping will be installed on startup.")
    install()
  else
    if fs.exists(flagPath) then
      fs.delete(flagPath)
    end
    print("Command wrapping disabled for future startups.")
    uninstall()
  end
end

local function status()
  print("Startup enabled: " .. tostring(fs.exists(flagPath)))
  for alias, target in pairs(commandMap) do
    print(alias .. " -> " .. tostring(shell.aliases()[alias]) .. " (target " .. target .. ")")
  end
end

if command == "enable" then
  setEnabled(true)
elseif command == "disable" then
  setEnabled(false)
elseif command == "install" then
  install()
elseif command == "uninstall" then
  uninstall()
elseif command == "status" then
  status()
else
  print("Usage: wrap_commands enable|disable|install|uninstall|status")
end
