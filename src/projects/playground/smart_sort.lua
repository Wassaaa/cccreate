local FROM_INVENTORIES = { "back" }
local TO_INVENTORY = "top"
local INTERVAL_SECONDS = 1
local SHORT_ITEM_NAMES = true
local ALLOW_VOIDING_FULL_TARGETS = true

-- Use this only if locked empty drawers do not show up through getItemDetail.
local EXTRA_TARGET_SLOTS = {
  -- ["minecraft:iron_ingot"] = { 1 },
}

local BLOCKED_TARGETS = {}
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

local function itemLabel(itemName)
  if not SHORT_ITEM_NAMES then
    return itemName
  end

  return itemName:match("^[^:]+:(.+)$") or itemName
end

local function countText(count)
  return count and tostring(count) or "?"
end

local function slotState(inv, slot, expectedName)
  local item = nil

  if type(inv.getItemDetail) == "function" then
    local ok, result = pcall(inv.getItemDetail, slot)
    if ok then
      item = result
    end
  else
    item = inv.list()[slot]
  end

  if item and item.name == expectedName then
    local limit = nil

    if type(inv.getItemLimit) == "function" then
      local ok, result = pcall(inv.getItemLimit, slot)
      if ok and type(result) == "number" then
        limit = result
      end
    end

    return item.count, limit
  end

  return nil, nil
end

local function targetKey(itemName, slot)
  return itemName .. "@" .. slot
end

local function blockTarget(itemName, slot, count, limit, reason, quiet)
  local key = targetKey(itemName, slot)

  if not quiet and not BLOCKED_TARGETS[key] then
    print(reason .. " " .. itemLabel(itemName) .. " " .. TO_INVENTORY .. ":" .. slot .. " " .. countText(count) .. "/" .. countText(limit))
  end

  BLOCKED_TARGETS[key] = {
    count = count,
  }
end

local function targetIsBlocked(itemName, slot, count)
  local blocked = BLOCKED_TARGETS[targetKey(itemName, slot)]
  if not blocked then
    return false
  end

  if count and blocked.count and count < blocked.count then
    BLOCKED_TARGETS[targetKey(itemName, slot)] = nil
    return false
  end

  return true
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

local function addOpenTarget(targets, to, itemName, slot)
  local count, limit = slotState(to, slot, itemName)

  if count and limit and count >= limit then
    if not ALLOW_VOIDING_FULL_TARGETS then
      blockTarget(itemName, slot, count, limit, "FULL")
      return
    end
  end

  if targetIsBlocked(itemName, slot, count) then
    return
  end

  addTarget(targets, itemName, slot)
end

local function targetSlots(to)
  local targets = {}

  for slot, item in pairs(to.list()) do
    addOpenTarget(targets, to, item.name, slot)
  end

  if type(to.size) == "function" and type(to.getItemDetail) == "function" then
    for slot = 1, to.size() do
      local ok, item = pcall(to.getItemDetail, slot)
      if ok and item then
        addOpenTarget(targets, to, item.name, slot)
      end
    end
  end

  for itemName, slots in pairs(EXTRA_TARGET_SLOTS) do
    for _, slot in ipairs(slots) do
      addOpenTarget(targets, to, itemName, slot)
    end
  end

  return targets
end

local function moveMatches(fromName, from, to, targets)
  local movedTotal = 0

  for fromSlot, item in pairs(from.list()) do
    local slots = targets[item.name]

    if slots then
      local remaining = item.count

      for _, toSlot in ipairs(slots) do
        if remaining <= 0 then
          break
        end

        local targetBefore, targetLimit = slotState(to, toSlot, item.name)

        if targetBefore and targetLimit and targetBefore >= targetLimit then
          if not ALLOW_VOIDING_FULL_TARGETS then
            blockTarget(item.name, toSlot, targetBefore, targetLimit, "FULL")
            break
          end
        end

        local moved = from.pushItems(TO_INVENTORY, fromSlot, remaining, toSlot)
        if moved > 0 then
          local targetAfter = slotState(to, toSlot, item.name)
          remaining = remaining - moved

          local line = itemLabel(item.name)
            .. " "
            .. fromName
            .. ":"
            .. fromSlot
            .. " "
            .. moved
            .. "/"
            .. item.count
            .. " -> "
            .. TO_INVENTORY
            .. ":"
            .. toSlot
            .. " "
            .. countText(targetBefore)
            .. ">"
            .. countText(targetAfter)

          if targetBefore and targetAfter and targetAfter <= targetBefore then
            if ALLOW_VOIDING_FULL_TARGETS then
              movedTotal = movedTotal + moved
              print("VOID " .. line)
            else
              blockTarget(item.name, toSlot, targetAfter, targetLimit, "NO_GAIN", true)
              print("NO " .. line)
              break
            end
          else
            movedTotal = movedTotal + moved
            print(line)
          end
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
    movedTotal = movedTotal + moveMatches(source.name, source.inventory, to, targets)
  end

  if movedTotal > 0 then
    print("Moved " .. movedTotal .. " item(s).")
  end

  sleep(INTERVAL_SECONDS)
end
