local reporter = require("lib.reporter")

local PACKAGER_NAME = "front"
local STAGING_INVENTORY = "minecraft:barrel_4"
local DEFAULT_OUTPUT_INVENTORY = nil
local INPUT_PACKAGE_SLOT = 1
local OUTPUT_SLOT = 16
local CRAFT_BATCH_LIMIT = 64
local FEED_EVENT_TIMEOUT = 3

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

local function sendReport(payload)
  payload.kind = "package_crafter"
  payload.computerId = os.getComputerID()
  payload.label = os.getComputerLabel()
  payload.command = command
  reporter.send(payload)
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

local function pushItemToTurtleSlot(inventory, turtleName, itemName, count, targetSlot)
  local remaining = count

  while remaining > 0 do
    local movedThisPass = false

    for slot, item in pairs(inventory.list()) do
      if item.name == itemName then
        local moved = inventory.pushItems(turtleName, slot, remaining, targetSlot)
        if moved and moved > 0 then
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

local function fillCraftGrid(staging, turtleName, recipe, craftCount)
  local missingName, needed, available = firstMissingRequirement(staging, requiredItems(recipe, craftCount))
  if missingName then
    return false, "Need " .. needed .. " x " .. missingName .. ", found " .. available
  end

  for recipeSlot = 1, 9 do
    local itemName = recipe[recipeSlot]
    if itemName then
      local turtleSlot = GRID_TO_TURTLE_SLOT[recipeSlot]
      local moved = pushItemToTurtleSlot(staging, turtleName, itemName, craftCount, turtleSlot)

      if moved ~= craftCount then
        return false, "Moved only " .. moved .. "/" .. craftCount .. " x " .. itemName
      end
    end
  end

  return true
end

local function pushOutput(output, turtleName)
  local totalMoved = 0

  while true do
    local item = turtle.getItemDetail(OUTPUT_SLOT)
    if not item then
      return totalMoved
    end

    local moved = output.pullItems(turtleName, OUTPUT_SLOT, item.count)
    if not moved or moved <= 0 then
      error("Output refused " .. item.name .. " x" .. item.count, 0)
    end

    totalMoved = totalMoved + moved
  end
end

local function craftOneRecipe(staging, output, turtleName, craft)
  local remaining = craft.count or 1
  local crafted = 0
  local pushedOutput = 0

  while remaining > 0 do
    local batch = math.min(remaining, CRAFT_BATCH_LIMIT)

    requireCleanTurtle()

    local filled, fillError = fillCraftGrid(staging, turtleName, craft.recipe, batch)
    if not filled then
      return crafted, pushedOutput, fillError
    end

    turtle.select(OUTPUT_SLOT)

    if not turtle.craft(batch) then
      error("turtle.craft(" .. batch .. ") failed", 0)
    end

    crafted = crafted + batch
    pushedOutput = pushedOutput + pushOutput(output, turtleName)
    remaining = remaining - batch
  end

  return crafted, pushedOutput, nil
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
    local crafted, pushedOutput, craftError = craftOneRecipe(staging, output, turtleName, craft)

    table.insert(result.crafts, {
      requested = craft.count,
      crafted = crafted,
      pushedOutput = pushedOutput,
      error = craftError,
      recipe = craft.recipe,
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

local function waitOnce()
  if type(turtle) ~= "table" then
    error("This program must run on a crafting turtle", 0)
  end

  print("Waiting for package_received from " .. PACKAGER_NAME .. "...")

  local _, package = os.pullEvent("package_received")
  local result = handlePackage(package)

  sendReport({
    event = "package_received",
    result = result,
    turtleInventory = turtleInventory(),
  })

  print("Package handled: " .. result.action)
  if result.reason then
    print(result.reason)
  end
end

local function waitForPackageReceived(timeout)
  local timer = os.startTimer(timeout)

  while true do
    local event = { os.pullEvent() }

    if event[1] == "package_received" then
      return event[2]
    end

    if event[1] == "timer" and event[2] == timer then
      return nil
    end
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

  local package = waitForPackageReceived(FEED_EVENT_TIMEOUT)
  local result = nil

  if package then
    result = handlePackage(package)
  end

  sendReport({
    event = package and "package_received" or "timeout",
    fed = true,
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

local function watch()
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
elseif command == "watch" then
  watch()
else
  error("Usage: package_crafter status|once|feed-once|watch [output_inventory]", 0)
end
