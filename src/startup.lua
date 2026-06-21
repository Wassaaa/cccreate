-- Runs automatically when the ComputerCraft computer boots.

local function ensureRootInShellPath()
  local currentPath = shell.path()
  for entry in string.gmatch(currentPath, "[^:]+") do
    if entry == "/" then
      return
    end
  end

  shell.setPath("/:" .. currentPath)
end

ensureRootInShellPath()

if fs.exists("/.wrap_commands_enabled") then
  shell.run("wrap_commands", "install")
end

shell.run("main")
