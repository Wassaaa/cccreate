local reporter = require("lib.reporter")

local PACKAGER_NAME = "front"
local STAGING_INVENTORY = "minecraft:barrel_4"
local DEFAULT_OUTPUT_INVENTORY = nil
local INPUT_PACKAGE_SLOT = 1
local OUTPUT_SLOT = 16
local CRAFT_BATCH_LIMIT = 64
local FEED_EVENT_TIMEOUT = 3
local SNIFF_EVENT_TIMEOUT = 10
local STAGING_WAIT_SECONDS = 5
local STAGING_POLL_SECONDS = 0.05
local MAX_REPORT_DEPTH = 16
local RECIPE_CACHE_PATH = "/config/package_crafter_recipes.lua"
local PROBE_UNKNOWN_RECIPES_WITH_SINGLE_CRAFT = false
local UNKNOWN_RECIPE_OUTPUT_PER_STEP = 1
local UNKNOWN_RECIPE_OUTPUT_MAX_COUNT = 64

local GRID_TO_TURTLE_SLOT = {
  1, 2, 3,
  5, 6, 7,
  9, 10, 11,
}

local args = { ... }
local command = args[1] or "status"
local outputName = args[2] or DEFAULT_OUTPUT_INVENTORY
local unpackArgs = table.unpack or unpack

local pendingCraftsByOrder = {}
local stackLimitsByName = {}
local recipeMetricsBySignature = {}

local function isPackageObject(value)
  return type(value) == "table"
    and type(value.getOrderData) == "function"
    and type(value.list) == "function"
end

local function recipeSignature(recipe)
  local parts = {}

  for index = 1, 9 do
    parts[index] = recipe and recipe[index] or "-"
  end

  return table.concat(parts, "|")
end

local function loadRecipeCache()
  if not fs.exists(RECIPE_CACHE_PATH) then
    return
  end

  local handle = fs.open(RECIPE_CACHE_PATH, "r")
  if not handle then
    return
  end

  local loaded = textutils.unserialize(handle.readAll())
  handle.close()

  if type(loaded) == "table" then
    recipeMetricsBySignature = loaded
  end
end

local function saveRecipeCache()
  local folder = fs.getDir(RECIPE_CACHE_PATH)
  if folder ~= "" and not fs.exists(folder) then
    fs.makeDir(folder)
  end

  local handle = fs.open(RECIPE_CACHE_PATH, "w")
  if handle then
    handle.write(textutils.serialize(recipeMetricsBySignature))
    handle.close()
  end
end

loadRecipeCache()

local function safeCall(object, method, ...)
  if type(object) ~= "table" or type(object[method]) ~= "function" then
    return nil, "missing method " .. tostring(method)
  end

  local values = { pcall(object[method], ...) }
  local ok = table.remove(values, 1)

  if not ok then
    return nil, tostring(values[1])
  end

  return unpackArgs(values)
end

local function isInventory(object)
  return object
    and type(object.list) == "function"
    and type(object.pushItems) == "function"
    and type(object.pullItems) == "function"
end

local function requireInventory(name)
  local object = peripheral.wrap(name)

  if not isInventory(object) then
    error("Inventory not found or not movable: " .. tostring(name), 0)
  end

  return object
end

local function inventoryNames()
  local names = {}

  for _, name in ipairs(peripheral.getNames()) do
    if name ~= STAGING_INVENTORY and isInventory(peripheral.wrap(name)) then
      table.insert(names, name)
    end
  end

  table.sort(names)
  return names
end

local function containsName(names, target)
  for _, name in ipairs(names) do
    if name == target then
      return true
    end
  end

  return false
end

local function resolveOutputName(required)
  if outputName then
    if outputName == STAGING_INVENTORY then
      error("Output inventory cannot be the staging inventory: " .. outputName, 0)
    end

    if not isInventory(peripheral.wrap(outputName)) then
      error("Output inventory not found or not movable: " .. tostring(outputName), 0)
    end

    return outputName
  end

  local names = inventoryNames()

  if #names == 1 then
    outputName = names[1]
    print("Output: " .. outputName)
    return outputName
  end

  if not required then
    return nil
  end

  if #names == 0 then
    error("Need an output inventory besides staging " .. STAGING_INVENTORY, 0)
  end

  print("Choose output inventory:")
  for index, name in ipairs(names) do
    print(index .. ": " .. name)
  end

  while true do
    write("> ")
    local answer = read()
    local index = tonumber(answer)

    if index and names[index] then
      outputName = names[index]
      return outputName
    end

    if containsName(names, answer) then
      outputName = answer
      return outputName
    end

    print("Choose one listed output.")
  end
end

local function findTurtleName()
  for _, name in ipairs(peripheral.getNames()) do
    local modem = peripheral.wrap(name)
    if modem
      and type(modem.getNameLocal) == "function"
      and (type(modem.isWireless) ~= "function" or not modem.isWireless())
    then
      local localName = modem.getNameLocal()
      if localName then
        return localName
      end
    end
  end
end

local function sortedPeripheralNames()
  local names = peripheral.getNames()
  table.sort(names)
  return names
end

local function compactList(items)
  local result = {}

  if type(items) ~= "table" then
    return result
  end

  for slot, item in pairs(items) do
    table.insert(result, {
      slot = slot,
      name = item.name,
      count = item.count,
      nbt = item.nbt,
    })
  end

  table.sort(result, function(left, right)
    return left.slot < right.slot
  end)

  return result
end

local function copyRecipe(recipe)
  local result = {}

  for index = 1, 9 do
    result[index] = recipe and recipe[index] or nil
  end

  return result
end

local function compactCrafts(crafts)
  local result = {}

  if type(crafts) ~= "table" then
    return result
  end

  local indexes = {}
  for index in pairs(crafts) do
    if type(index) == "number" then
      table.insert(indexes, index)
    end
  end

  table.sort(indexes)

  for _, index in ipairs(indexes) do
    local craft = crafts[index]
    table.insert(result, {
      index = index,
      count = craft.count or 1,
      recipe = copyRecipe(craft.recipe),
    })
  end

  return result
end

local function summarizeOrder(order)
  if type(order) ~= "table" then
    return nil
  end

  local crafts = safeCall(order, "getCrafts") or {}

  return {
    id = safeCall(order, "getOrderID"),
    index = safeCall(order, "getIndex"),
    linkIndex = safeCall(order, "getLinkIndex"),
    isFinal = safeCall(order, "isFinal"),
    isFinalLink = safeCall(order, "isFinalLink"),
    items = compactList(safeCall(order, "list")),
    crafts = compactCrafts(crafts),
  }
end

local function summarizePackage(package)
  if type(package) ~= "table" then
    return {
      error = "event did not include a package object",
    }
  end

  return {
    address = safeCall(package, "getAddress"),
    isEditable = safeCall(package, "isEditable"),
    contents = compactList(safeCall(package, "list")),
    order = summarizeOrder(safeCall(package, "getOrderData")),
  }
end

local function turtleInventory()
  local result = {}

  if type(turtle) ~= "table" then
    return result
  end

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot, true)
    if item then
      table.insert(result, {
        slot = slot,
        name = item.name,
        count = item.count,
        nbt = item.nbt,
      })
    end
  end

  return result
end

local function inventorySummary(name)
  local object = peripheral.wrap(name)

  if not object or type(object.list) ~= "function" then
    return {
      name = name,
      present = peripheral.isPresent(name),
      isInventory = false,
    }
  end

  return {
    name = name,
    present = true,
    isInventory = isInventory(object),
    size = type(object.size) == "function" and object.size() or nil,
    items = compactList(object.list()),
  }
end

local function jsonSafe(value, depth, seen)
  depth = depth or 0
  seen = seen or {}

  local valueType = type(value)

  if valueType == "nil" or valueType == "string" or valueType == "number" or valueType == "boolean" then
    return value
  end

  if valueType ~= "table" then
    return "<" .. valueType .. ">"
  end

  if seen[value] then
    return "<cycle>"
  end

  if depth >= MAX_REPORT_DEPTH then
    return "<max-depth>"
  end

  seen[value] = true

  local result = {}
  for key, item in pairs(value) do
    result[tostring(key)] = jsonSafe(item, depth + 1, seen)
  end

  seen[value] = nil
  return result
end

local function sendReport(payload)
  payload.kind = "package_crafter"
  payload.computerId = os.getComputerID()
  payload.label = os.getComputerLabel()
  payload.command = command
  reporter.send(jsonSafe(payload))
end

local function statusReport()
  local packager = peripheral.wrap(PACKAGER_NAME)
  local turtleName = findTurtleName()

  local report = {
    config = {
      packager = PACKAGER_NAME,
      staging = STAGING_INVENTORY,
      output = outputName,
    },
    isTurtle = type(turtle) == "table",
    turtleName = turtleName,
    turtleInventory = turtleInventory(),
    peripherals = sortedPeripheralNames(),
    outputCandidates = inventoryNames(),
    staging = inventorySummary(STAGING_INVENTORY),
  }

  if outputName then
    report.output = inventorySummary(outputName)
  end

  if packager then
    report.packager = {
      name = PACKAGER_NAME,
      types = { peripheral.getType(PACKAGER_NAME) },
      methods = peripheral.getMethods(PACKAGER_NAME),
      address = safeCall(packager, "getAddress"),
      connectedInventory = compactList(safeCall(packager, "list")),
      heldPackage = summarizePackage(safeCall(packager, "getPackage")),
    }
  else
    report.packager = {
      name = PACKAGER_NAME,
      error = "not present",
    }
  end

  sendReport(report)

  print("Package crafter status sent.")
  print("Packager: " .. PACKAGER_NAME)
  print("Staging: " .. STAGING_INVENTORY)
  print("Output: " .. tostring(outputName))
  print("Turtle: " .. tostring(turtleName))
end

local function requireCleanTurtle()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then
      error("Turtle slot " .. slot .. " is not empty: " .. item.name .. " x" .. item.count, 0)
    end
  end
end

local function recipeTurtleSlots(recipe)
  local slots = { OUTPUT_SLOT }
  local seen = {
    [OUTPUT_SLOT] = true,
  }

  for recipeSlot = 1, 9 do
    if recipe[recipeSlot] then
      local turtleSlot = GRID_TO_TURTLE_SLOT[recipeSlot]
      if not seen[turtleSlot] then
        seen[turtleSlot] = true
        table.insert(slots, turtleSlot)
      end
    end
  end

  return slots
end

local function requireSlotsEmpty(slots)
  for _, slot in ipairs(slots) do
    local item = turtle.getItemDetail(slot)
    if item then
      error("Turtle slot " .. slot .. " is not empty: " .. item.name .. " x" .. item.count, 0)
    end
  end
end

local function countInInventory(inventory, itemName)
  local total = 0

  for _, item in pairs(inventory.list()) do
    if item.name == itemName then
      total = total + item.count
    end
  end

  return total
end

local function requiredItems(recipe, craftCount)
  local required = {}

  for index = 1, 9 do
    local itemName = recipe[index]
    if itemName then
      required[itemName] = (required[itemName] or 0) + craftCount
    end
  end

  return required
end

local function firstMissingRequirement(inventory, required)
  for itemName, needed in pairs(required) do
    local available = countInInventory(inventory, itemName)
    if available < needed then
      return itemName, needed, available
    end
  end
end

local function countInList(items, itemName)
  local total = 0

  for _, item in pairs(items) do
    if item.name == itemName then
      total = total + item.count
    end
  end

  return total
end

local function firstMissingRequirementInList(items, required)
  for itemName, needed in pairs(required) do
    local available = countInList(items, itemName)
    if available < needed then
      return itemName, needed, available
    end
  end
end

local function waitForRequirements(inventory, required)
  local attempts = math.max(1, math.ceil(STAGING_WAIT_SECONDS / STAGING_POLL_SECONDS))
  local lastName = nil
  local lastNeeded = nil
  local lastAvailable = nil

  for _ = 1, attempts do
    local items = inventory.list()
    local itemName, needed, available = firstMissingRequirementInList(items, required)

    if not itemName then
      return true, items
    end

    lastName = itemName
    lastNeeded = needed
    lastAvailable = available
    sleep(STAGING_POLL_SECONDS)
  end

  return false, "Need " .. lastNeeded .. " x " .. lastName .. ", found " .. lastAvailable
end

local function itemStackLimit(inventory, itemName, items)
  if stackLimitsByName[itemName] then
    return stackLimitsByName[itemName]
  end

  items = items or inventory.list()

  for slot, item in pairs(items) do
    if item.name == itemName then
      if type(inventory.getItemDetail) == "function" then
        local detail = inventory.getItemDetail(slot)
        if detail and type(detail.maxCount) == "number" then
          stackLimitsByName[itemName] = detail.maxCount
          return detail.maxCount
        end
      end

      stackLimitsByName[itemName] = 64
      return 64
    end
  end

  return 64
end

local function maxBatchForRecipe(inventory, recipe, requested, items)
  local batch = math.min(requested, CRAFT_BATCH_LIMIT)

  for recipeSlot = 1, 9 do
    local itemName = recipe[recipeSlot]
    if itemName then
      batch = math.min(batch, itemStackLimit(inventory, itemName, items))
    end
  end

  return math.max(1, batch)
end

local function pushItemToTurtleSlot(inventory, turtleName, itemName, count, targetSlot, items)
  local remaining = count

  while remaining > 0 do
    local movedThisPass = false

    for slot, item in pairs(items) do
      if item.name == itemName then
        local moved = inventory.pushItems(turtleName, slot, remaining, targetSlot)
        if moved and moved > 0 then
          item.count = item.count - moved
          if item.count <= 0 then
            items[slot] = nil
          end

          remaining = remaining - moved
          movedThisPass = true

          if remaining == 0 then
            return count
          end
        end
      end
    end

    if not movedThisPass then
      return count - remaining
    end
  end

  return count
end

local function fillCraftGrid(staging, turtleName, recipe, craftCount, items)
  for recipeSlot = 1, 9 do
    local itemName = recipe[recipeSlot]
    if itemName then
      local turtleSlot = GRID_TO_TURTLE_SLOT[recipeSlot]
      local moved = pushItemToTurtleSlot(staging, turtleName, itemName, craftCount, turtleSlot, items)

      if moved ~= craftCount then
        return false, "Moved only " .. moved .. "/" .. craftCount .. " x " .. itemName
      end
    end
  end

  return true
end

local function pullSlotFully(output, turtleName, slot, itemName, count, label)
  local remaining = count
  local movedTotal = 0

  while remaining > 0 do
    local moved = output.pullItems(turtleName, slot, remaining)

    if not moved or moved <= 0 then
      error("Output refused " .. label .. " " .. itemName .. " x" .. remaining, 0)
    end

    movedTotal = movedTotal + moved
    remaining = remaining - moved
  end

  return movedTotal
end

local function pushOutput(output, turtleName, outputItem)
  return pullSlotFully(output, turtleName, OUTPUT_SLOT, outputItem.name, outputItem.count, "output")
end

local function appendAll(target, source)
  for _, item in ipairs(source) do
    table.insert(target, item)
  end
end

local function pushRemainders(output, turtleName, slots)
  local movedItems = {}

  for _, slot in ipairs(slots) do
    if slot ~= OUTPUT_SLOT then
      local item = turtle.getItemDetail(slot)

      if item then
        local movedTotal = pullSlotFully(output, turtleName, slot, item.name, item.count, "remainder")

        table.insert(movedItems, {
          slot = slot,
          name = item.name,
          count = movedTotal,
        })
      end
    end
  end

  return movedItems
end

local function craftOneRecipe(staging, output, turtleName, craft)
  local remaining = craft.count or 1
  local crafted = 0
  local pushedOutput = 0
  local remainders = {}
  local signature = recipeSignature(craft.recipe)
  local metrics = recipeMetricsBySignature[signature]
  local outputPerStep = metrics and metrics.outputPerStep or (not PROBE_UNKNOWN_RECIPES_WITH_SINGLE_CRAFT and UNKNOWN_RECIPE_OUTPUT_PER_STEP or nil)
  local outputMaxCount = metrics and metrics.outputMaxCount or UNKNOWN_RECIPE_OUTPUT_MAX_COUNT
  local controlledSlots = recipeTurtleSlots(craft.recipe)

  while remaining > 0 do
    requireSlotsEmpty(controlledSlots)

    local outputSafeLimit = 1
    if outputPerStep then
      outputSafeLimit = math.max(1, math.floor(outputMaxCount / outputPerStep))
    end

    local desired = math.min(remaining, outputSafeLimit)
    local ready, itemsOrError = waitForRequirements(staging, requiredItems(craft.recipe, desired))
    if not ready then
      return crafted, pushedOutput, itemsOrError, remainders
    end

    local items = itemsOrError

    local batch = maxBatchForRecipe(staging, craft.recipe, desired, items)
    local filled, fillError = fillCraftGrid(staging, turtleName, craft.recipe, batch, items)
    if not filled then
      return crafted, pushedOutput, fillError, remainders
    end

    turtle.select(OUTPUT_SLOT)

    local craftedOk, craftError = turtle.craft(batch)
    if not craftedOk then
      return crafted, pushedOutput, "turtle.craft(" .. batch .. ") failed: " .. tostring(craftError), remainders
    end

    local outputItem = turtle.getItemDetail(OUTPUT_SLOT, true)
    if not outputItem then
      return crafted, pushedOutput, "Craft succeeded but output slot was empty", remainders
    end

    if not metrics then
      outputPerStep = math.max(1, math.floor(outputItem.count / batch))
      outputMaxCount = outputItem.maxCount or outputMaxCount
      recipeMetricsBySignature[signature] = {
        outputPerStep = outputPerStep,
        outputMaxCount = outputMaxCount,
      }
      saveRecipeCache()
      metrics = recipeMetricsBySignature[signature]
    end

    crafted = crafted + batch
    pushedOutput = pushedOutput + pushOutput(output, turtleName, outputItem)
    appendAll(remainders, pushRemainders(output, turtleName, controlledSlots))
    remaining = remaining - batch
  end

  return crafted, pushedOutput, nil, remainders
end

local function canCraftFromSummary(summary)
  return summary.order
    and summary.order.isFinal == true
    and summary.order.isFinalLink == true
    and #summary.order.crafts > 0
end

local function handlePackage(package)
  local summary = summarizePackage(package)
  local result = {
    package = summary,
    action = "ignored",
  }

  if not summary.order then
    result.reason = "package has no order data"
    return result
  end

  if #summary.order.crafts > 0 then
    pendingCraftsByOrder[summary.order.id] = summary.order.crafts
  elseif pendingCraftsByOrder[summary.order.id] then
    summary.order.crafts = pendingCraftsByOrder[summary.order.id]
  end

  if not summary.order.isFinal or not summary.order.isFinalLink then
    result.reason = "waiting for final package/link"
    return result
  end

  if #summary.order.crafts == 0 then
    result.reason = "final package had no craft recipes"
    return result
  end

  if not outputName then
    result.action = "planned"
    result.reason = "no output inventory configured"
    return result
  end

  local staging = requireInventory(STAGING_INVENTORY)
  local output = requireInventory(outputName)
  local turtleName = findTurtleName()

  if not turtleName then
    error("Need active wired modem local name for turtle inventory transfers", 0)
  end

  result.action = "crafted"
  result.crafts = {}

  for _, craft in ipairs(summary.order.crafts) do
    local crafted, pushedOutput, craftError, remainders = craftOneRecipe(staging, output, turtleName, craft)

    table.insert(result.crafts, {
      requested = craft.count,
      crafted = crafted,
      pushedOutput = pushedOutput,
      error = craftError,
      remainders = remainders,
      recipe = copyRecipe(craft.recipe),
    })

    if craftError then
      result.action = "partial"
      result.reason = craftError
      return result
    end
  end

  pendingCraftsByOrder[summary.order.id] = nil
  result.stagingAfter = inventorySummary(STAGING_INVENTORY)
  result.outputAfter = inventorySummary(outputName)
  return result
end

local eventSummary = nil
local packageFromEvent = nil

local function waitOnce()
  if type(turtle) ~= "table" then
    error("This program must run on a crafting turtle", 0)
  end

  resolveOutputName(true)
  requireCleanTurtle()

  print("Waiting for package_received from " .. PACKAGER_NAME .. "...")

  local event = { os.pullEvent("package_received") }
  local package = packageFromEvent(event)
  local result = handlePackage(package)

  sendReport({
    event = "package_received",
    received = {
      source = event[2],
    },
    events = {
      eventSummary(event),
    },
    result = result,
    turtleInventory = turtleInventory(),
  })

  print("Package handled: " .. result.action)
  if result.reason then
    print(result.reason)
  end
end

local function eventArgSummary(value)
  local valueType = type(value)

  if valueType == "table" then
    if isPackageObject(value) then
      return {
        kind = "package",
        package = summarizePackage(value),
      }
    end

    local keys = {}
    for key, item in pairs(value) do
      table.insert(keys, tostring(key) .. ":" .. type(item))
    end
    table.sort(keys)

    return {
      kind = "table",
      keys = keys,
    }
  end

  if valueType == "nil" or valueType == "string" or valueType == "number" or valueType == "boolean" then
    return value
  end

  return "<" .. valueType .. ">"
end

function eventSummary(event)
  local args = {}

  for index = 2, #event do
    table.insert(args, eventArgSummary(event[index]))
  end

  return {
    name = event[1],
    args = args,
  }
end

function packageFromEvent(event)
  for index = 2, #event do
    if isPackageObject(event[index]) then
      return event[index], index
    end
  end
end

local function waitForPackageReceived(timeout)
  local timer = os.startTimer(timeout)
  local events = {}

  while true do
    local event = { os.pullEvent() }

    if event[1] == "package_received" then
      table.insert(events, eventSummary(event))
      local package, packageArgIndex = packageFromEvent(event)
      return package, events, {
        source = event[2],
        packageArgIndex = packageArgIndex,
      }
    end

    if event[1] == "timer" and event[2] == timer then
      return nil, events
    end

    table.insert(events, eventSummary(event))
  end
end

local function feedOnce()
  if type(turtle) ~= "table" then
    error("This program must run on a turtle", 0)
  end

  local item = turtle.getItemDetail(INPUT_PACKAGE_SLOT, true)
  if not item then
    error("Turtle slot " .. INPUT_PACKAGE_SLOT .. " is empty", 0)
  end

  if type(item.package) ~= "table" then
    error("Turtle slot " .. INPUT_PACKAGE_SLOT .. " does not contain a Create package", 0)
  end

  local before = {
    turtleSlot = {
      slot = INPUT_PACKAGE_SLOT,
      name = item.name,
      count = item.count,
      nbt = item.nbt,
      package = summarizePackage(item.package),
    },
    staging = inventorySummary(STAGING_INVENTORY),
  }

  turtle.select(INPUT_PACKAGE_SLOT)
  local dropped = turtle.drop(1)

  if not dropped then
    error("Packager did not accept the package from turtle slot " .. INPUT_PACKAGE_SLOT, 0)
  end

  local package, events, received = waitForPackageReceived(FEED_EVENT_TIMEOUT)
  local result = nil

  if package then
    result = handlePackage(package)
  end

  sendReport({
    event = package and "package_received" or "timeout",
    fed = true,
    events = events,
    received = received,
    before = before,
    result = result,
    after = {
      staging = inventorySummary(STAGING_INVENTORY),
      turtleInventory = turtleInventory(),
      packager = {
        connectedInventory = compactList(safeCall(peripheral.wrap(PACKAGER_NAME), "list")),
        heldPackage = summarizePackage(safeCall(peripheral.wrap(PACKAGER_NAME), "getPackage")),
      },
    },
  })

  if result then
    print("Fed package; handled: " .. result.action)
    if result.reason then
      print(result.reason)
    end
  else
    print("Fed package; no package_received event within " .. FEED_EVENT_TIMEOUT .. "s")
  end
end

local function sniff()
  print("Sniffing events for " .. SNIFF_EVENT_TIMEOUT .. "s...")
  local package, events, received = waitForPackageReceived(SNIFF_EVENT_TIMEOUT)
  local result = nil

  if package then
    result = handlePackage(package)
  end

  sendReport({
    event = package and "package_received" or "timeout",
    events = events,
    received = received,
    result = result,
    staging = inventorySummary(STAGING_INVENTORY),
    turtleInventory = turtleInventory(),
  })

  print("Sniffed " .. #events .. " event(s).")
  if result then
    print("Package handled: " .. result.action)
    if result.reason then
      print(result.reason)
    end
  end
end

local function watch()
  resolveOutputName(true)

  print("Watching package_received events.")
  print("Packager: " .. PACKAGER_NAME)
  print("Staging: " .. STAGING_INVENTORY)
  print("Output: " .. tostring(outputName))
  print("Hold Ctrl+T to stop.")

  while true do
    local ok, err = pcall(waitOnce)
    if not ok then
      sendReport({
        error = tostring(err),
        turtleInventory = turtleInventory(),
      })
      error(err, 0)
    end
  end
end

if command == "status" then
  statusReport()
elseif command == "once" then
  waitOnce()
elseif command == "feed-once" then
  feedOnce()
elseif command == "sniff" then
  sniff()
elseif command == "watch" then
  watch()
else
  error("Usage: package_crafter status|once|feed-once|sniff|watch [output_inventory]", 0)
end
