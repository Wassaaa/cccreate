local MOD_ID = "create"
local INPUT_SIDE = "bottom"
local OUTPUT_SIDE = "back"

local args = { ... }

local function trim(value)
  return tostring(value):match("^%s*(.-)%s*$")
end

local function normalizeModId(value)
  local text = trim(value or MOD_ID)
  return text:gsub(":$", "")
end

local function inventory(side)
  local wrapped = peripheral.wrap(side)
  if not wrapped or type(wrapped.list) ~= "function" or type(wrapped.pushItems) ~= "function" then
    error("No inventory on " .. side, 0)
  end

  return wrapped
end

local modId = normalizeModId(args[1])
if modId == "" then
  error("Set MOD_ID or pass a mod id argument", 0)
end

local prefix = modId .. ":"
local input = inventory(INPUT_SIDE)
inventory(OUTPUT_SIDE)

local total = 0
local stacks = 0

for slot, item in pairs(input.list()) do
  if item.name and item.name:sub(1, #prefix) == prefix then
    local moved = input.pushItems(OUTPUT_SIDE, slot, item.count)

    if moved > 0 then
      total = total + moved
      stacks = stacks + 1
      print("Moved " .. moved .. " x " .. item.name .. " from slot " .. slot)
    else
      print("Could not move " .. item.name .. " from slot " .. slot)
    end
  end
end

print("Moved " .. total .. " " .. modId .. " item(s) from " .. stacks .. " stack(s).")
