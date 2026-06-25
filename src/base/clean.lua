local KEEP = {
  rom = true,
}

local args = { ... }
local assumeYes = args[1] == "--yes" or args[1] == "-y"

local function rootPath(name)
  return fs.combine("/", name)
end

local entries = fs.list("/")
table.sort(entries)

local targets = {}
for _, name in ipairs(entries) do
  if not KEEP[name] then
    table.insert(targets, name)
  end
end

if #targets == 0 then
  print("Nothing to clean. Only /rom is present.")
  return
end

print("This will delete everything except /rom:")
for _, name in ipairs(targets) do
  print("- /" .. name)
end

if not assumeYes then
  write("Type CLEAN to continue: ")
  if read() ~= "CLEAN" then
    print("Clean cancelled.")
    return
  end
end

for _, name in ipairs(targets) do
  local path = rootPath(name)
  print("Deleting " .. path)
  fs.delete(path)
end

print("Clean complete.")
