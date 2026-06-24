local DEFAULT_URL = "https://cc-webhook.transcenders.online/report"

local args = { ... }
local url = DEFAULT_URL
local token = args[1]

if args[1] == "--url" then
  url = args[2] or DEFAULT_URL
  token = args[3]
end

if not token or token == "" then
  write("Webhook token: ")
  token = read("*")
end

if not token or token == "" then
  error("Webhook token is required", 0)
end

if not fs.exists("config") then
  fs.makeDir("config")
end

local handle = fs.open("config/webhook.lua", "w")
if not handle then
  error("Could not write config/webhook.lua", 0)
end

handle.write("return {\n")
handle.write("  url = " .. textutils.serialize(url) .. ",\n")
handle.write("  token = " .. textutils.serialize(token) .. ",\n")
handle.write("}\n")
handle.close()

print("Wrote config/webhook.lua")
