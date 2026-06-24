local args = { ... }
local command = args[1] or "status"

local DIRECTIONS = {
  up = true,
  down = true,
  top = true,
  bottom = true,
  front = true,
  back = true,
  left = true,
  right = true,
  north = true,
  south = true,
  east = true,
  west = true,
}

local function usage()
  print("ap_inventory_manager_test status [sample-limit]")
  print("ap_inventory_manager_test find <item-name>")
  print("ap_inventory_manager_test plan-give <direction> <container-slot> [count] [player-slot] [item-name]")
  print("ap_inventory_manager_test give <direction> <container-slot> [count] [player-slot] [item-name]")
  print("ap_inventory_manager_test plan-take <direction> <player-slot> [count] [container-slot] [item-name]")
  print("ap_inventory_manager_test take <direction> <player-slot> [count] [container-slot] [item-name]")
  print("")
  print("Directions are relative or cardinal from the Inventory Manager block.")
  print("Relative: front, back, left, right, top, bottom.")
  print("Cardinal: north, south, east, west, up, down.")
  print("Use - for optional slots or item names.")
end

local function join(values, separator)
  separator = separator or ", "

  if not values or #values == 0 then
    return "(none)"
  end

  return table.concat(values, separator)
end

local function sortedCopy(values)
  local copy = {}

  for _, value in ipairs(values or {}) do
    table.insert(copy, tostring(value))
  end

  table.sort(copy)
  return copy
end

local function typeList(name)
  local results = { pcall(peripheral.getType, name) }
  local ok = table.remove(results, 1)

  if not ok then
    return { "error:" .. tostring(results[1]) }
  end

  return sortedCopy(results)
end

local function methodList(name)
  local ok, methods = pcall(peripheral.getMethods, name)

  if not ok or type(methods) ~= "table" then
    return {}
  end

  return sortedCopy(methods)
end

local function hasMethod(methods, methodName)
  for _, method in ipairs(methods) do
    if method == methodName then
      return true
    end
  end

  return false
end

local function looksLikeInventoryManager(types, methods)
  local typeText = string.lower(join(types, " "))
  local typeMatch = string.find(typeText, "inventory_manager", 1, true) ~= nil
    or string.find(typeText, "inventorymanager", 1, true) ~= nil

  local methodMatch = hasMethod(methods, "getOwner")
    and hasMethod(methods, "getItems")
    and hasMethod(methods, "addItemToPlayer")
    and hasMethod(methods, "removeItemFromPlayer")

  return typeMatch or methodMatch
end

local function managerCandidates()
  local candidates = {}

  for _, name in ipairs(peripheral.getNames()) do
    local types = typeList(name)
    local methods = methodList(name)

    if looksLikeInventoryManager(types, methods) then
      table.insert(candidates, {
        name = name,
        types = types,
        methods = methods,
      })
    end
  end

  table.sort(candidates, function(left, right)
    return left.name < right.name
  end)

  return candidates
end

local function chooseManager()
  local candidates = managerCandidates()

  if #candidates == 0 then
    return nil, "No Advanced Peripherals Inventory Manager found"
  end

  if #candidates > 1 then
    print("Multiple Inventory Manager candidates found:")
    for _, candidate in ipairs(candidates) do
      print("  " .. candidate.name .. " [" .. join(candidate.types) .. "]")
    end
    return nil, "Refusing to choose between multiple Inventory Managers"
  end

  local manager = peripheral.wrap(candidates[1].name)
  if not manager then
    return nil, "Failed to wrap " .. candidates[1].name
  end

  return {
    name = candidates[1].name,
    types = candidates[1].types,
    methods = candidates[1].methods,
    object = manager,
  }, nil
end

local function safeCall(target, methodName, ...)
  if type(target[methodName]) ~= "function" then
    return false, "Missing method " .. methodName
  end

  local results = { pcall(target[methodName], ...) }
  local ok = table.remove(results, 1)

  if not ok then
    return false, tostring(results[1])
  end

  return true, results
end

local function parseInteger(value, label, defaultValue, minimum, maximum)
  if value == nil or value == "" or value == "-" then
    return defaultValue
  end

  local parsed = tonumber(value)
  if not parsed or parsed ~= math.floor(parsed) then
    error(label .. " must be an integer", 0)
  end

  if minimum and parsed < minimum then
    error(label .. " must be at least " .. minimum, 0)
  end

  if maximum and parsed > maximum then
    error(label .. " must be at most " .. maximum, 0)
  end

  return parsed
end

local function optionalText(value)
  if value == nil or value == "" or value == "-" then
    return nil
  end

  return value
end

local function validateDirection(direction)
  if not direction or not DIRECTIONS[direction] then
    error("direction must be relative or cardinal from the Inventory Manager block", 0)
  end

  return direction
end

local function itemLine(item)
  if not item then
    return "(empty)"
  end

  local parts = {}

  if item.slot then
    table.insert(parts, "slot " .. tostring(item.slot))
  elseif item.fromSlot then
    table.insert(parts, "slot " .. tostring(item.fromSlot))
  end

  table.insert(parts, tostring(item.name or "(unknown)"))

  if item.count then
    table.insert(parts, "x" .. tostring(item.count))
  end

  if item.nbt then
    table.insert(parts, "nbt=" .. tostring(item.nbt))
  end

  return table.concat(parts, " ")
end

local function normalizeItems(items)
  local normalized = {}

  for key, item in pairs(items or {}) do
    if type(item) == "table" then
      local copy = {}
      for itemKey, value in pairs(item) do
        copy[itemKey] = value
      end

      if not copy.slot and tonumber(key) then
        copy.slot = tonumber(key)
      end

      table.insert(normalized, copy)
    end
  end

  table.sort(normalized, function(left, right)
    return (left.slot or 0) < (right.slot or 0)
  end)

  return normalized
end

local function printManagerSummary(manager)
  print("Inventory Manager: " .. manager.name)
  print("  Types: " .. join(manager.types))
  print("  Methods: " .. join(manager.methods))

  local ok, results = safeCall(manager.object, "getOwner")
  if ok then
    print("  Owner: " .. tostring(results[1]))
  else
    print("  Owner error: " .. tostring(results))
  end
end

local function printInventorySample(manager, sampleLimit)
  sampleLimit = sampleLimit or 16

  local ok, results = safeCall(manager.object, "getItems")
  if not ok then
    print("getItems failed: " .. tostring(results))
    return
  end

  local items = normalizeItems(results[1])
  print("Player inventory sample: " .. math.min(#items, sampleLimit) .. " shown / " .. #items .. " occupied")

  for index, item in ipairs(items) do
    if index > sampleLimit then
      break
    end

    print("  " .. itemLine(item))
  end
end

local function printOptionalMethod(manager, label, methodName)
  local ok, results = safeCall(manager.object, methodName)

  if ok then
    print(label .. ": " .. textutils.serialize(results[1]))
  else
    print(label .. ": unavailable (" .. tostring(results) .. ")")
  end
end

local function status(sampleLimit)
  local candidates = managerCandidates()
  print("Inventory Manager candidates: " .. #candidates)
  for _, candidate in ipairs(candidates) do
    print("  " .. candidate.name .. " [" .. join(candidate.types) .. "]")
  end

  local manager, managerError = chooseManager()
  if not manager then
    print("Status failed: " .. tostring(managerError))
    return false
  end

  print("")
  printManagerSummary(manager)
  printOptionalMethod(manager, "Main hand", "getItemInHand")
  printOptionalMethod(manager, "Offhand", "getItemInOffHand")
  printOptionalMethod(manager, "Armor", "getArmor")
  print("")
  printInventorySample(manager, sampleLimit)
  return true
end

local function findItem(itemName)
  itemName = optionalText(itemName)
  if not itemName then
    print("find failed: item-name is required")
    return false
  end

  local manager, managerError = chooseManager()
  if not manager then
    print("Find failed: " .. tostring(managerError))
    return false
  end

  local ok, results = safeCall(manager.object, "getItems")
  if not ok then
    print("Find failed: " .. tostring(results))
    return false
  end

  local found = 0
  for _, item in ipairs(normalizeItems(results[1])) do
    if item.name == itemName then
      print("  " .. itemLine(item))
      found = found + 1
    end
  end

  print("Found " .. found .. " stack(s) of " .. itemName)
  return true
end

local function makeGiveFilter(containerSlot, count, playerSlot, itemName)
  local filter = {
    slot = containerSlot,
    count = count,
  }

  if playerSlot then
    filter.toSlot = playerSlot
  end

  if itemName then
    filter.name = itemName
  end

  return filter
end

local function makeTakeFilter(playerSlot, count, containerSlot, itemName)
  local filter = {
    fromSlot = playerSlot,
    count = count,
  }

  if containerSlot then
    filter.toSlot = containerSlot
  end

  if itemName then
    filter.name = itemName
  end

  return filter
end

local function transfer(mode, direction, filter, dryRun)
  direction = validateDirection(direction)

  local manager, managerError = chooseManager()
  if not manager then
    print("Transfer failed: " .. tostring(managerError))
    return false
  end

  printManagerSummary(manager)
  print("Direction: " .. direction)
  print("Filter: " .. textutils.serialize(filter))

  if dryRun then
    print("Dry run only. No items moved.")
    return true
  end

  local methodName = mode == "give" and "addItemToPlayer" or "removeItemFromPlayer"
  local ok, results = safeCall(manager.object, methodName, direction, filter)

  if not ok then
    print("Transfer failed: " .. tostring(results))
    return false
  end

  print("Transfer result: " .. textutils.serialize(results))
  return true
end

local function runGive(dryRun)
  local direction = args[2]
  local containerSlot = parseInteger(args[3], "container-slot", nil, 1)
  local count = parseInteger(args[4], "count", 1, 1, 64)
  local playerSlot = parseInteger(args[5], "player-slot", nil, 1)
  local itemName = optionalText(args[6])

  if not containerSlot then
    print("give failed: container-slot is required")
    usage()
    return false
  end

  return transfer("give", direction, makeGiveFilter(containerSlot, count, playerSlot, itemName), dryRun)
end

local function runTake(dryRun)
  local direction = args[2]
  local playerSlot = parseInteger(args[3], "player-slot", nil, 1)
  local count = parseInteger(args[4], "count", 1, 1, 64)
  local containerSlot = parseInteger(args[5], "container-slot", nil, 1)
  local itemName = optionalText(args[6])

  if not playerSlot then
    print("take failed: player-slot is required")
    usage()
    return false
  end

  return transfer("take", direction, makeTakeFilter(playerSlot, count, containerSlot, itemName), dryRun)
end

local ok, result = pcall(function()
  if command == "status" then
    return status(parseInteger(args[2], "sample-limit", 16, 1, 64))
  elseif command == "find" then
    return findItem(args[2])
  elseif command == "plan-give" then
    return runGive(true)
  elseif command == "give" then
    return runGive(false)
  elseif command == "plan-take" then
    return runTake(true)
  elseif command == "take" then
    return runTake(false)
  elseif command == "help" then
    usage()
    return true
  else
    print("Unknown command: " .. tostring(command))
    usage()
    return false
  end
end)

if not ok then
  print("ap_inventory_manager_test failed: " .. tostring(result))
  error(result, 0)
end

if result == false then
  error("ap_inventory_manager_test command failed", 0)
end
