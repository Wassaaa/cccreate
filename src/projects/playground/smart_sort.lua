local FROM_INVENTORIES = { "bottom" }
local TO_INVENTORY = "back"
local INTERVAL_SECONDS = 1

-- Use this only if locked empty drawers do not show up through getItemDetail.
local EXTRA_TARGET_SLOTS = {
  -- ["minecraft:iron_ingot"] = { 1 },
}

local args = { ... }

local function trim(value)
  return tostring(value):match("^%s*(.-)%s*$")
end

local function appendCsv(result, value)
  for part in tostring(value):gmatch("[^,]+") do
    local name = trim(part)
    if name ~= "" then
      table.insert(result, name)
    end
  end
end

local function nameList(value)
  local result = {}

  if type(value) == "table" then
    for _, entry in ipairs(value) do
      appendCsv(result, entry)
    end
  else
    appendCsv(result, value)
  end

  return result
end

local function inventory(name)
  local wrapped = peripheral.wrap(name)
  if not wrapped or type(wrapped.list) ~= "function" then
    error("No inventory named " .. name, 0)
  end

  return wrapped
end

local function sourceInventory(name)
  local wrapped = inventory(name)
  if type(wrapped.pushItems) ~= "function" then
    error("Inventory cannot push items: " .. name, 0)
  end

  return wrapped
end

local function addTarget(targets, itemName, slot)
  if not itemName or not slot then
    return
  end

  targets[itemName] = targets[itemName] or {}
  for _, existingSlot in ipairs(targets[itemName]) do
    if existingSlot == slot then
      return
    end
  end

  table.insert(targets[itemName], slot)
end

local function targetSlots(to)
  local targets = {}

  for slot, item in pairs(to.list()) do
    addTarget(targets, item.name, slot)
  end

  if type(to.size) == "function" and type(to.getItemDetail) == "function" then
    for slot = 1, to.size() do
      local item = to.getItemDetail(slot)
      if item then
        addTarget(targets, item.name, slot)
      end
    end
  end

  for itemName, slots in pairs(EXTRA_TARGET_SLOTS) do
    for _, slot in ipairs(slots) do
      addTarget(targets, itemName, slot)
    end
  end

  return targets
end

local function moveMatches(fromName, from, targets)
  local movedTotal = 0

  for fromSlot, item in pairs(from.list()) do
    local slots = targets[item.name]

    if slots then
      local remaining = item.count

      for _, toSlot in ipairs(slots) do
        if remaining <= 0 then
          break
        end

        local moved = from.pushItems(TO_INVENTORY, fromSlot, remaining, toSlot)
        if moved > 0 then
          movedTotal = movedTotal + moved
          remaining = remaining - moved
          print("Moved " .. moved .. " x " .. item.name .. " from " .. fromName .. ":" .. fromSlot .. " to " .. TO_INVENTORY .. ":" .. toSlot)
        end
      end
    end
  end

  return movedTotal
end

if args[1] then
  TO_INVENTORY = args[1]
end

if args[2] then
  FROM_INVENTORIES = nameList(args[2])
end

if args[3] then
  INTERVAL_SECONDS = tonumber(args[3]) or INTERVAL_SECONDS
end

if #FROM_INVENTORIES == 0 then
  error("Set at least one source inventory", 0)
end

if INTERVAL_SECONDS <= 0 then
  error("Interval must be greater than 0", 0)
end

local to = inventory(TO_INVENTORY)
local sources = {}

for _, name in ipairs(FROM_INVENTORIES) do
  if name == TO_INVENTORY then
    error("Source and target inventory are both " .. name, 0)
  end

  table.insert(sources, {
    name = name,
    inventory = sourceInventory(name),
  })
end

print("Smart sort running.")
print("To: " .. TO_INVENTORY)
print("From: " .. table.concat(FROM_INVENTORIES, ", "))
print("Interval: " .. INTERVAL_SECONDS .. "s")

while true do
  local targets = targetSlots(to)
  local movedTotal = 0

  for _, source in ipairs(sources) do
    movedTotal = movedTotal + moveMatches(source.name, source.inventory, targets)
  end

  if movedTotal > 0 then
    print("Moved " .. movedTotal .. " item(s).")
  end

  sleep(INTERVAL_SECONDS)
end
