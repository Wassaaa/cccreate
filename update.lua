-- Simple CC:Tweaked updater.
-- Edit these values after you create your GitHub repository.
local githubUser = "Wassaaa"
local githubRepo = "cccreate"
local branch = "main"
local basePath = "src"

local baseUrl = "https://raw.githubusercontent.com/" .. githubUser .. "/" .. githubRepo .. "/" .. branch .. "/" .. basePath .. "/"

local files = {
  "startup.lua",
  "main.lua",
  "lib/logger.lua",
}

local function ensureFolder(path)
  local folder = fs.getDir(path)

  if folder ~= "" and not fs.exists(folder) then
    print("Creating folder: " .. folder)
    fs.makeDir(folder)
  end
end

local function downloadFile(path)
  local url = baseUrl .. path

  print("Downloading " .. path)

  local response, errorMessage = http.get(url)
  if not response then
    error("Failed to download " .. path .. ": " .. tostring(errorMessage), 0)
  end

  local contents = response.readAll()
  response.close()

  ensureFolder(path)

  local handle = fs.open(path, "w")
  if not handle then
    error("Failed to open " .. path .. " for writing", 0)
  end

  handle.write(contents)
  handle.close()

  print("Updated " .. path)
end

print("Updating from " .. githubUser .. "/" .. githubRepo .. " (" .. branch .. ")")

for _, path in ipairs(files) do
  downloadFile(path)
end

print("Update complete. Run reboot to restart.")
