local inventoryTools = require("lib.inventory_tools")

local DEFAULT_ADDRESS = "out"
local DEFAULT_CRAFT_ADDRESS = "crafter"
local DEFAULT_COUNT_EACH = 1
local DEFAULT_ITEM_LIMIT = 3
local DEFAULT_INVENTORY_SIDE = "bottom"
local DEFAULT_CONFIGURATION = "strict"

local unpackArgs = table.unpack or unpack
local args = { ... }
local command = args[1] or "status"

local function usage()
  print("requester_test status [inventory-side]")
  print("requester_test preview [address] [count-each] [item-limit] [inventory-side]")
  print("requester_test request [address] [count-each] [item-limit] [inventory-side]")
  print("requester_test craft-preview [address] [batch-count] <slot1> ... <slot9>")
  print("requester_test craft [address] [batch-count] <slot1> ... <slot9>")
  print("requester_test pulse <side> [seconds]")
  print("")
  print("Defaults: address=out count-each=1 item-limit=3 inventory-side=bottom")
  print("Craft default address: crafter")
  print("Use -, _, nil, air, or minecraft:air for empty craft slots.")
end

local function sortedCopy(values)
  local copy = {}

  for _, value in ipairs(values or {}) do
    table.insert(copy, tostring(value))
  end

  table.sort(copy)
  return copy
end

local function join(values, separator)
  separator = separator or ", "

  if not values or #values == 0 then
    return "(none)"
  end

  return table.concat(values, separator)
end

local function typeList(name)
  local results = { pcall(peripheral.getType, name) }
  local ok = table.remove(results, 1)

  if not ok then
    return { "error:" .. tostring(results[1]) }
  end

  return results
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

local function describePeripheral(name)
  local types = sortedCopy(typeList(name))
  local methods = methodList(name)
  local typeText = string.lower(join(types, " "))
  local requesterByType = string.find(typeText, "requester", 1, true) ~= nil
    and string.find(typeText, "redstone", 1, true) ~= nil

  local requesterByMethods = hasMethod(methods, "request")
    and (hasMethod(methods, "setRequest") or hasMethod(methods, "getRequest"))
    and (hasMethod(methods, "setAddress") or hasMethod(methods, "getAddress"))

  return {
    name = name,
    types = types,
    methods = methods,
    requesterByType = requesterByType,
    isRequesterCandidate = requesterByType or requesterByMethods,
  }
end

local function requesterCandidates()
  local candidates = {}

  for _, name in ipairs(peripheral.getNames()) do
    local description = describePeripheral(name)

    if description.isRequesterCandidate then
      table.insert(candidates, description)
    end
  end

  table.sort(candidates, function(left, right)
    return left.name < right.name
  end)

  return candidates
end

local function chooseRequester()
  local candidates = requesterCandidates()

  if #candidates == 0 then
    return nil, "No Redstone Requester peripheral found"
  end

  if #candidates > 1 then
    local typedCandidates = {}

    for _, candidate in ipairs(candidates) do
      if candidate.requesterByType then
        table.insert(typedCandidates, candidate)
      end
    end

    if #typedCandidates == 1 then
      candidates = typedCandidates
    end
  end

  if #candidates > 1 then
    print("Multiple requester candidates found:")
    for _, candidate in ipairs(candidates) do
      print("  " .. candidate.name .. " [" .. join(candidate.types) .. "]")
    end
    return nil, "Refusing to choose between multiple requesters"
  end

  local requester = peripheral.wrap(candidates[1].name)
  if not requester then
    return nil, "Failed to wrap " .. candidates[1].name
  end

  return {
    name = candidates[1].name,
    object = requester,
    methods = candidates[1].methods,
    types = candidates[1].types,
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

local function parseInteger(value, defaultValue, minimum, maximum, label)
  if value == nil or value == "" then
    return defaultValue
  end

  local parsed = tonumber(value)
  if not parsed or parsed ~= math.floor(parsed) then
    error(label .. " must be an integer", 0)
  end

  if parsed < minimum or parsed > maximum then
    error(label .. " must be between " .. minimum .. " and " .. maximum, 0)
  end

  return parsed
end

local function inventoryTotals(side)
  if not peripheral.isPresent(side) then
    return nil, "No peripheral on " .. side
  end

  local inventory = peripheral.wrap(side)
  if not inventory or type(inventory.size) ~= "function" or type(inventory.list) ~= "function" then
    return nil, "Peripheral on " .. side .. " is not an inventory"
  end

  local totals = {}
  local order = {}
  local items = inventory.list()

  for slot = 1, inventory.size() do
    local item = items[slot]

    if item and item.name then
      if not totals[item.name] then
        totals[item.name] = 0
        table.insert(order, item.name)
      end

      totals[item.name] = totals[item.name] + (tonumber(item.count) or 0)
    end
  end

  return {
    side = side,
    totals = totals,
    order = order,
  }, nil
end

local function buildSampleRequest(side, itemLimit, countEach)
  local inventory, inventoryError = inventoryTotals(side)
  if not inventory then
    return nil, inventoryError
  end

  local requestItems = {}

  for _, itemName in ipairs(inventory.order) do
    local available = inventory.totals[itemName] or 0

    if available > 0 then
      table.insert(requestItems, {
        name = itemName,
        count = math.min(countEach, available),
      })

      if #requestItems >= itemLimit then
        break
      end
    end
  end

  if #requestItems == 0 then
    return nil, "No items found in " .. side
  end

  return requestItems, nil
end

local function emptyCraftSlot(value)
  if value == nil or value == "" then
    return true
  end

  local normalized = string.lower(tostring(value))
  return normalized == "-"
    or normalized == "_"
    or normalized == "nil"
    or normalized == "air"
    or normalized == "minecraft:air"
end

local function buildCraftSlots(slotArgs, firstSlotIndex)
  local slots = {}
  local nonEmpty = 0

  for slot = 1, 9 do
    local value = slotArgs[firstSlotIndex + slot - 1]

    if emptyCraftSlot(value) then
      slots[slot] = nil
    else
      slots[slot] = value
      nonEmpty = nonEmpty + 1
    end
  end

  if nonEmpty == 0 then
    return nil, "Crafting request needs at least one non-empty recipe slot"
  end

  return slots, nil
end

local function parseCraftArguments(commandArgs)
  local address = DEFAULT_CRAFT_ADDRESS
  local batchCount = 1
  local firstSlotIndex = 2

  if commandArgs[2] and tonumber(commandArgs[2]) then
    batchCount = parseInteger(commandArgs[2], 1, 1, 256, "batch-count")
    firstSlotIndex = 3
  elseif commandArgs[2] and commandArgs[3] and tonumber(commandArgs[3]) then
    address = commandArgs[2]
    batchCount = parseInteger(commandArgs[3], 1, 1, 256, "batch-count")
    firstSlotIndex = 4
  end

  local slots, slotError = buildCraftSlots(commandArgs, firstSlotIndex)
  if not slots then
    return nil, nil, nil, slotError
  end

  return address, batchCount, slots, nil
end

local function printRequestItems(requestItems)
  for index, item in ipairs(requestItems) do
    print("  " .. index .. ". " .. item.name .. " x" .. item.count)
  end
end

local function slotText(value)
  if value == nil then
    return "(empty)"
  end

  return tostring(value)
end

local function printCraftSlots(slots)
  for row = 1, 3 do
    local firstSlot = (row - 1) * 3 + 1
    print(
      "  "
        .. firstSlot
        .. "-"
        .. (firstSlot + 2)
        .. ": "
        .. slotText(slots[firstSlot])
        .. " | "
        .. slotText(slots[firstSlot + 1])
        .. " | "
        .. slotText(slots[firstSlot + 2])
    )
  end
end

local function setRequesterRequest(requester, requestItems)
  local ok, errorMessage = pcall(function()
    requester.object.setRequest(unpackArgs(requestItems, 1, #requestItems))
  end)

  if ok then
    return true, "varargs"
  end

  local firstError = tostring(errorMessage)
  ok, errorMessage = pcall(function()
    requester.object.setRequest(requestItems)
  end)

  if ok then
    return true, "table"
  end

  return false, "setRequest varargs failed: " .. firstError .. "; table failed: " .. tostring(errorMessage)
end

local function setRequesterCraftingRequest(requester, batchCount, slots)
  local ok, errorMessage = pcall(function()
    requester.object.setCraftingRequest(batchCount, unpackArgs(slots, 1, 9))
  end)

  if ok then
    return true
  end

  return false, tostring(errorMessage)
end

local function triggerRequester(requester, requestItems, address)
  local ok, results = safeCall(requester.object, "request")

  if ok then
    return true, "configured", results
  end

  local configuredError = tostring(results)
  ok, results = safeCall(requester.object, "request", requestItems, address)

  if ok then
    return true, "inline", results
  end

  return false, "request() failed: " .. configuredError .. "; request(items, address) failed: " .. tostring(results)
end

local function triggerConfiguredRequester(requester)
  local ok, results = safeCall(requester.object, "request")

  if not ok then
    return false, tostring(results)
  end

  return true, results
end

local function printRequesterStatus(requester)
  print("Requester: " .. requester.name)
  print("  Types: " .. join(requester.types))
  print("  Methods: " .. join(requester.methods))

  local ok, results = safeCall(requester.object, "getAddress")
  if ok then
    print("  Address: " .. tostring(results[1]))
  end

  ok, results = safeCall(requester.object, "getConfiguration")
  if ok then
    print("  Configuration: " .. tostring(results[1]))
  end

  ok, results = safeCall(requester.object, "getRequest")
  if ok then
    print("  Current request: " .. textutils.serialize(results[1]))
  end
end

local function status(side)
  side = side or DEFAULT_INVENTORY_SIDE

  inventoryTools.printSummary(inventoryTools.summarize(side, 6))

  print("")
  print("Redstone:")
  for _, redstoneSide in ipairs(redstone.getSides()) do
    print(
      "  "
        .. redstoneSide
        .. ": in="
        .. tostring(redstone.getInput(redstoneSide))
        .. " analogIn="
        .. tostring(redstone.getAnalogInput(redstoneSide))
        .. " out="
        .. tostring(redstone.getOutput(redstoneSide))
        .. " analogOut="
        .. tostring(redstone.getAnalogOutput(redstoneSide))
    )
  end

  print("")
  local candidates = requesterCandidates()
  print("Requester candidates: " .. #candidates)
  for _, candidate in ipairs(candidates) do
    print("  " .. candidate.name .. " [" .. join(candidate.types) .. "]")
    print("    Methods: " .. join(candidate.methods))
  end

  local requester = chooseRequester()
  if requester then
    print("")
    printRequesterStatus(requester)
  end
end

local function preview(address, countEach, itemLimit, side)
  address = address or DEFAULT_ADDRESS
  countEach = countEach or DEFAULT_COUNT_EACH
  itemLimit = itemLimit or DEFAULT_ITEM_LIMIT
  side = side or DEFAULT_INVENTORY_SIDE

  local requestItems, requestError = buildSampleRequest(side, itemLimit, countEach)
  if not requestItems then
    print("Preview failed: " .. tostring(requestError))
    return false
  end

  print("Address: " .. address)
  print("Inventory side: " .. side)
  print("Configuration: " .. DEFAULT_CONFIGURATION)
  print("Request items:")
  printRequestItems(requestItems)
  return true, requestItems
end

local function request(address, countEach, itemLimit, side)
  address = address or DEFAULT_ADDRESS
  countEach = countEach or DEFAULT_COUNT_EACH
  itemLimit = itemLimit or DEFAULT_ITEM_LIMIT
  side = side or DEFAULT_INVENTORY_SIDE

  local requester, requesterError = chooseRequester()
  if not requester then
    print("Request failed: " .. tostring(requesterError))
    return false
  end

  local ok, requestItems = preview(address, countEach, itemLimit, side)
  if not ok then
    return false
  end

  print("")
  printRequesterStatus(requester)

  local success, results = safeCall(requester.object, "setAddress", address)
  if not success then
    print("Request failed: " .. tostring(results))
    return false
  end
  print("Set address: " .. address)

  success, results = safeCall(requester.object, "setConfiguration", DEFAULT_CONFIGURATION)
  if success then
    print("Set configuration: " .. DEFAULT_CONFIGURATION)
  else
    print("Could not set configuration: " .. tostring(results))
  end

  local requestSet, requestModeOrError = setRequesterRequest(requester, requestItems)
  if not requestSet then
    print("Request failed: " .. requestModeOrError)
    return false
  end

  print("Set request using " .. requestModeOrError .. " form.")

  local triggered, triggerModeOrError, triggerResults = triggerRequester(requester, requestItems, address)
  if not triggered then
    print("Request failed: " .. triggerModeOrError)
    return false
  end

  print("Triggered requester using " .. triggerModeOrError .. " request.")
  if triggerResults and #triggerResults > 0 then
    print("Result: " .. textutils.serialize(triggerResults))
  end

  return true
end

local function craftPreview(address, batchCount, slots)
  address = address or DEFAULT_CRAFT_ADDRESS
  batchCount = batchCount or 1

  print("Craft address: " .. address)
  print("Batch count: " .. batchCount)
  print("Craft slots:")
  printCraftSlots(slots)
  return true
end

local function craft(address, batchCount, slots)
  address = address or DEFAULT_CRAFT_ADDRESS
  batchCount = batchCount or 1

  local requester, requesterError = chooseRequester()
  if not requester then
    print("Craft request failed: " .. tostring(requesterError))
    return false
  end

  craftPreview(address, batchCount, slots)

  print("")
  printRequesterStatus(requester)

  local success, results = safeCall(requester.object, "setAddress", address)
  if not success then
    print("Craft request failed: " .. tostring(results))
    return false
  end
  print("Set address: " .. address)

  success, results = safeCall(requester.object, "setConfiguration", DEFAULT_CONFIGURATION)
  if success then
    print("Set configuration: " .. DEFAULT_CONFIGURATION)
  else
    print("Could not set configuration: " .. tostring(results))
  end

  success, results = setRequesterCraftingRequest(requester, batchCount, slots)
  if not success then
    print("Craft request failed: " .. tostring(results))
    return false
  end
  print("Set crafting request.")

  success, results = triggerConfiguredRequester(requester)
  if not success then
    print("Craft request failed: " .. tostring(results))
    return false
  end

  print("Triggered configured crafting request.")
  if results and #results > 0 then
    print("Result: " .. textutils.serialize(results))
  end

  return true
end

local function pulse(side, seconds)
  if not side then
    print("Pulse failed: side is required")
    usage()
    return false
  end

  seconds = seconds or 0.2

  print("Pulsing redstone on " .. side .. " for " .. seconds .. " second(s)")
  redstone.setOutput(side, true)
  sleep(seconds)
  redstone.setOutput(side, false)
  return true
end

local ok, result = pcall(function()
  if command == "status" then
    return status(args[2])
  elseif command == "preview" then
    return preview(
      args[2] or DEFAULT_ADDRESS,
      parseInteger(args[3], DEFAULT_COUNT_EACH, 1, 256, "count-each"),
      parseInteger(args[4], DEFAULT_ITEM_LIMIT, 1, 9, "item-limit"),
      args[5] or DEFAULT_INVENTORY_SIDE
    )
  elseif command == "request" then
    return request(
      args[2] or DEFAULT_ADDRESS,
      parseInteger(args[3], DEFAULT_COUNT_EACH, 1, 256, "count-each"),
      parseInteger(args[4], DEFAULT_ITEM_LIMIT, 1, 9, "item-limit"),
      args[5] or DEFAULT_INVENTORY_SIDE
    )
  elseif command == "craft-preview" then
    local address, batchCount, slots, slotError = parseCraftArguments(args)

    if not slots then
      print("Craft preview failed: " .. tostring(slotError))
      return false
    end

    return craftPreview(address, batchCount, slots)
  elseif command == "craft" then
    local address, batchCount, slots, slotError = parseCraftArguments(args)

    if not slots then
      print("Craft request failed: " .. tostring(slotError))
      return false
    end

    return craft(address, batchCount, slots)
  elseif command == "pulse" then
    return pulse(args[2], tonumber(args[3]) or 0.2)
  elseif command == "help" then
    usage()
  else
    print("Unknown command: " .. tostring(command))
    usage()
    return false
  end
end)

if not ok then
  print("requester_test failed: " .. tostring(result))
  error(result, 0)
end

if result == false then
  error("requester_test command failed", 0)
end
