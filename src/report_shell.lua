local aliases = {
  dir = "ccwrap.lua --quiet /rom/programs/list.lua",
  id = "ccwrap.lua --quiet /rom/programs/id.lua",
  list = "ccwrap.lua --quiet /rom/programs/list.lua",
  ls = "ccwrap.lua --quiet /rom/programs/list.lua",
}

local args = { ... }
local command = args[1] or "status"

local function enable()
  for alias, target in pairs(aliases) do
    shell.setAlias(alias, target)
    print("Reporting " .. alias)
  end

  print("Report-only shell aliases enabled for this shell.")
end

local function disable()
  for alias, _ in pairs(aliases) do
    shell.clearAlias(alias)
    print("Cleared " .. alias)
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
