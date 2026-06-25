local M = {}

local PACKAGER_NAME = "front"
local DEFAULT_STAGING_INVENTORY = nil
local DEFAULT_OUTPUT_INVENTORY = nil
local OUTPUT_SLOT = 16
local CRAFT_BATCH_LIMIT = 64
local STAGING_WAIT_SECONDS = 5
local STAGING_POLL_SECONDS = 0.05
local MAX_REPORT_DEPTH = 12
local RECIPE_CACHE_PATH = "/config/package_crafter_recipes.lua"
local RECIPE_CACHE_VERSION = 2

local GRID_TO_TURTLE_SLOT = {
  1, 2, 3,
  5, 6, 7,
  9, 10, 11,
}

local unpackArgs = table.unpack or unpack

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

local function safeCall(object, method, ...)
  if type(object) ~= "table" or type(object[method]) ~= "function" then
    return nil
  end

  local values = { pcall(object[method], ...) }
  local ok = table.remove(values, 1)

  if not ok then
    return nil
  end

  return unpackArgs(values)
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
  local indexes = {}

  if type(crafts) ~= "table" then
    return result
  end

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

local function isInventory(object)
  return object
    and type(object.list) == "function"
    and type(object.pushItems) == "function"
    and type(object.pullItems) == "function"
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

local function turtleInventory()
  local result = {}

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

function M.run(options)
  options = options or {}

  local reporting = options.reporting == true
  local reporter = reporting and require("lib.reporter") or nil
  local programName = options.programName or "package_crafter"
  local args = options.args or {}
  local firstInventory = args[1]
  local secondInventory = args[2]
  local stagingName = secondInventory and firstInventory or DEFAULT_STAGING_INVENTORY
  local outputName = secondInventory or firstInventory or DEFAULT_OUTPUT_INVENTORY
  local pendingCraftsByOrder = {}
  local stackLimitsByName = {}
  local recipeMetricsBySignature = {}
  local packageQueue = {}
  local nextPackageSequence = 0

  local function sendReport(payload)
    if not reporting then
      return
    end

    payload.kind = "package_crafter"
    payload.program = programName
    payload.computerId = os.getComputerID()
    payload.label = os.getComputerLabel()

    local ok, sentOrError = pcall(function()
      return reporter.send(jsonSafe(payload))
    end)

    if not ok then
      print("Report failed: " .. tostring(sentOrError))
      return false
    end

    return sentOrError == true
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

    if type(loaded) == "table"
      and loaded.version == RECIPE_CACHE_VERSION
      and type(loaded.recipes) == "table"
    then
      recipeMetricsBySignature = loaded.recipes
    end
  end

  local function saveRecipeCache()
    local folder = fs.getDir(RECIPE_CACHE_PATH)
    if folder ~= "" and not fs.exists(folder) then
      fs.makeDir(folder)
    end

    local handle = fs.open(RECIPE_CACHE_PATH, "w")
    if handle then
      handle.write(textutils.serialize({
        version = RECIPE_CACHE_VERSION,
        recipes = recipeMetricsBySignature,
      }))
      handle.close()
    end
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

  local function inventoryNames(excluded)
    local names = {}
    excluded = excluded or {}

    for _, name in ipairs(peripheral.getNames()) do
      if not excluded[name] and isInventory(peripheral.wrap(name)) then
        table.insert(names, name)
      end
    end

    table.sort(names)
    return names
  end

  local function excludedInventories(...)
    local excluded = {}
    local turtleName = findTurtleName()

    if turtleName then
      excluded[turtleName] = true
    end

    for index = 1, select("#", ...) do
      local name = select(index, ...)
      if name then
        excluded[name] = true
      end
    end

    return excluded
  end

  local function containsName(names, target)
    for _, name in ipairs(names) do
      if name == target then
        return true
      end
    end

    return false
  end

  local function chooseInventory(label, names)
    print("Choose " .. label .. " inventory:")
    for index, name in ipairs(names) do
      print(index .. ": " .. name)
    end

    while true do
      write("> ")
      local answer = read()
      local index = tonumber(answer)

      if index and names[index] then
        return names[index]
      end

      if containsName(names, answer) then
        return answer
      end

      print("Choose one listed inventory.")
    end
  end

  local function requireMovableInventory(label, name)
    if not isInventory(peripheral.wrap(name)) then
      error(label .. " inventory not found or not movable: " .. tostring(name), 0)
    end

    return name
  end

  local function resolveStagingName()
    if stagingName then
      if stagingName == outputName then
        error("Staging inventory cannot also be output inventory: " .. stagingName, 0)
      end

      return requireMovableInventory("Staging", stagingName)
    end

    local names = inventoryNames(excludedInventories(outputName))

    if #names == 1 then
      stagingName = names[1]
      print("Staging: " .. stagingName)
      return stagingName
    end

    if #names == 0 then
      error("Need a staging inventory on the wired network", 0)
    end

    stagingName = chooseInventory("staging", names)
    return stagingName
  end

  local function resolveOutputName()
    if outputName then
      if outputName == stagingName then
        error("Output inventory cannot also be staging inventory: " .. outputName, 0)
      end

      return requireMovableInventory("Output", outputName)
    end

    local names = inventoryNames(excludedInventories(stagingName))

    if #names == 1 then
      outputName = names[1]
      print("Output: " .. outputName)
      return outputName
    end

    if #names == 0 then
      error("Need an output inventory besides staging " .. tostring(stagingName), 0)
    end

    outputName = chooseInventory("output", names)
    return outputName
  end

  local function readOrder(package)
    if not package then
      return nil, "event did not include a package object"
    end

    local order = safeCall(package, "getOrderData")
    if type(order) ~= "table" then
      return nil, "package has no order data"
    end

    return {
      id = safeCall(order, "getOrderID"),
      index = safeCall(order, "getIndex"),
      linkIndex = safeCall(order, "getLinkIndex"),
      isFinal = safeCall(order, "isFinal"),
      isFinalLink = safeCall(order, "isFinalLink"),
      crafts = compactCrafts(safeCall(order, "getCrafts") or {}),
    }
  end

  local function packageFromEvent(event)
    for index = 2, #event do
      if isPackageObject(event[index]) then
        return event[index], index
      end
    end
  end

  local function packageRecordFromEvent(event)
    local package, packageArgIndex = packageFromEvent(event)
    local order, orderError = readOrder(package)

    nextPackageSequence = nextPackageSequence + 1

    return {
      sequence = nextPackageSequence,
      source = event[2],
      packageArgIndex = packageArgIndex,
      order = order,
      orderError = orderError,
    }
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

  local function collectRemainderItems(slots)
    local items = {}

    for _, slot in ipairs(slots) do
      if slot ~= OUTPUT_SLOT then
        local item = turtle.getItemDetail(slot, true)

        if item then
          table.insert(items, {
            slot = slot,
            name = item.name,
            count = item.count,
            nbt = item.nbt,
          })
        end
      end
    end

    return items
  end

  local function pushRemainderItems(output, turtleName, remainderItems)
    local movedItems = {}

    for _, item in ipairs(remainderItems) do
      local movedTotal = pullSlotFully(output, turtleName, item.slot, item.name, item.count, "remainder")

      table.insert(movedItems, {
        slot = item.slot,
        name = item.name,
        count = movedTotal,
      })
    end

    return movedItems
  end

  local function appendAll(target, source)
    for _, item in ipairs(source) do
      table.insert(target, item)
    end
  end

  local function learnRecipeMetrics(staging, output, turtleName, craft, signature, controlledSlots)
    local ready, itemsOrError = waitForRequirements(staging, requiredItems(craft.recipe, 1))
    if not ready then
      return nil, 0, {}, itemsOrError
    end

    local filled, fillError = fillCraftGrid(staging, turtleName, craft.recipe, 1, itemsOrError)
    if not filled then
      return nil, 0, {}, fillError
    end

    turtle.select(OUTPUT_SLOT)

    local craftedOk, craftError = turtle.craft(1)
    if not craftedOk then
      return nil, 0, {}, "turtle.craft(1) probe failed: " .. tostring(craftError)
    end

    local outputItem = turtle.getItemDetail(OUTPUT_SLOT, true)
    if not outputItem then
      return nil, 0, {}, "Probe craft succeeded but output slot was empty"
    end

    local remainderItems = collectRemainderItems(controlledSlots)
    local metrics = {
      outputPerStep = math.max(1, outputItem.count),
      outputMaxCount = outputItem.maxCount or 64,
      hasRemainders = #remainderItems > 0,
    }

    if metrics.hasRemainders then
      metrics.remainders = {}
      for _, item in ipairs(remainderItems) do
        table.insert(metrics.remainders, {
          slot = item.slot,
          name = item.name,
        })
      end
    end

    recipeMetricsBySignature[signature] = metrics
    saveRecipeCache()

    local pushedOutput = pushOutput(output, turtleName, outputItem)
    local movedRemainders = pushRemainderItems(output, turtleName, remainderItems)

    return metrics, pushedOutput, movedRemainders
  end

  local function canUsePersistentGrid(metrics)
    return metrics
      and metrics.outputPerStep == 1
      and metrics.outputMaxCount == 1
      and metrics.hasRemainders == false
  end

  local function ensurePersistentInput(staging, turtleName, itemName, targetSlot, remainingCrafts, items)
    local current = turtle.getItemDetail(targetSlot)

    if current then
      if current.name ~= itemName then
        return false, "Turtle slot " .. targetSlot .. " has " .. current.name .. ", expected " .. itemName
      end

      return true
    end

    local limit = itemStackLimit(staging, itemName, items)
    local moveCount = math.min(remainingCrafts, limit)
    local moved = pushItemToTurtleSlot(staging, turtleName, itemName, moveCount, targetSlot, items)

    if moved ~= moveCount then
      return false, "Moved only " .. moved .. "/" .. moveCount .. " x " .. itemName
    end

    return true
  end

  local function craftWithPersistentGrid(staging, output, turtleName, recipe, remaining, controlledSlots)
    local crafted = 0
    local pushedOutput = 0
    local remainders = {}
    local ready, itemsOrError = waitForRequirements(staging, requiredItems(recipe, remaining))

    if not ready then
      return crafted, pushedOutput, itemsOrError, remainders
    end

    local items = itemsOrError

    while remaining > 0 do
      if turtle.getItemDetail(OUTPUT_SLOT) then
        return crafted, pushedOutput, "Output slot is not empty before craft", remainders
      end

      for recipeSlot = 1, 9 do
        local itemName = recipe[recipeSlot]
        if itemName then
          local turtleSlot = GRID_TO_TURTLE_SLOT[recipeSlot]
          local ok, fillError = ensurePersistentInput(staging, turtleName, itemName, turtleSlot, remaining, items)

          if not ok then
            return crafted, pushedOutput, fillError, remainders
          end
        end
      end

      turtle.select(OUTPUT_SLOT)

      local craftedOk, craftError = turtle.craft(1)
      if not craftedOk then
        return crafted, pushedOutput, "turtle.craft(1) failed: " .. tostring(craftError), remainders
      end

      local outputItem = turtle.getItemDetail(OUTPUT_SLOT, true)
      if not outputItem then
        return crafted, pushedOutput, "Craft succeeded but output slot was empty", remainders
      end

      crafted = crafted + 1
      pushedOutput = pushedOutput + pushOutput(output, turtleName, outputItem)
      remaining = remaining - 1
    end

    local unexpectedRemainders = collectRemainderItems(controlledSlots)
    if #unexpectedRemainders > 0 then
      return crafted, pushedOutput, "Persistent craft left unexpected items in recipe slots", remainders
    end

    return crafted, pushedOutput, nil, remainders
  end

  local function craftOneRecipe(staging, output, turtleName, craft)
    local remaining = craft.count or 1
    local crafted = 0
    local pushedOutput = 0
    local remainders = {}
    local signature = recipeSignature(craft.recipe)
    local metrics = recipeMetricsBySignature[signature]
    local controlledSlots = recipeTurtleSlots(craft.recipe)

    if not metrics and remaining > 0 then
      requireSlotsEmpty(controlledSlots)

      local probeMetrics, probeOutput, probeRemainders, probeError =
        learnRecipeMetrics(staging, output, turtleName, craft, signature, controlledSlots)

      if not probeMetrics then
        return crafted, pushedOutput, probeError, remainders
      end

      metrics = probeMetrics
      crafted = crafted + 1
      pushedOutput = pushedOutput + probeOutput
      appendAll(remainders, probeRemainders)
      remaining = remaining - 1
    end

    while remaining > 0 do
      if canUsePersistentGrid(metrics) then
        local gridCrafted, gridOutput, gridError, gridRemainders =
          craftWithPersistentGrid(staging, output, turtleName, craft.recipe, remaining, controlledSlots)

        crafted = crafted + gridCrafted
        pushedOutput = pushedOutput + gridOutput
        appendAll(remainders, gridRemainders)
        return crafted, pushedOutput, gridError, remainders
      end

      requireSlotsEmpty(controlledSlots)

      local outputPerStep = metrics.outputPerStep or 1
      local outputMaxCount = metrics.outputMaxCount or 64
      local outputSafeLimit = math.max(1, math.floor(outputMaxCount / outputPerStep))

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

      local remainderItems = {}
      if metrics.hasRemainders then
        remainderItems = collectRemainderItems(controlledSlots)
      end

      crafted = crafted + batch
      pushedOutput = pushedOutput + pushOutput(output, turtleName, outputItem)
      appendAll(remainders, pushRemainderItems(output, turtleName, remainderItems))
      remaining = remaining - batch
    end

    return crafted, pushedOutput, nil, remainders
  end

  local function handlePackageRecord(record)
    local order = record.order
    local result = {
      action = "ignored",
      order = order,
      sequence = record.sequence,
    }

    if not order then
      result.reason = record.orderError
      return result
    end

    if #order.crafts > 0 and order.id then
      pendingCraftsByOrder[order.id] = order.crafts
    elseif order.id and pendingCraftsByOrder[order.id] then
      order.crafts = pendingCraftsByOrder[order.id]
    end

    if not order.isFinal or not order.isFinalLink then
      result.reason = "waiting for final package/link"
      return result
    end

    if #order.crafts == 0 then
      result.reason = "final package had no craft recipes"
      return result
    end

    local selectedStagingName = resolveStagingName()
    local selectedOutputName = resolveOutputName()
    local staging = requireInventory(selectedStagingName)
    local output = requireInventory(selectedOutputName)
    local turtleName = findTurtleName()

    if not turtleName then
      error("Need active wired modem local name for turtle inventory transfers", 0)
    end

    result.action = "crafted"
    result.crafts = {}

    for _, craft in ipairs(order.crafts) do
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

    if order.id then
      pendingCraftsByOrder[order.id] = nil
    end

    if reporting then
      result.stagingAfter = inventorySummary(selectedStagingName)
      result.outputAfter = inventorySummary(selectedOutputName)
    end

    return result
  end

  local function enqueuePackageEvent(event)
    local record = packageRecordFromEvent(event)
    table.insert(packageQueue, record)
    os.queueEvent("package_crafter_queued")
  end

  local function listenForPackages()
    while true do
      local event = { os.pullEvent() }

      if event[1] == "package_received" then
        enqueuePackageEvent(event)
      end
    end
  end

  local function nextQueuedPackage()
    while #packageQueue == 0 do
      os.pullEvent("package_crafter_queued")
    end

    return table.remove(packageQueue, 1)
  end

  local function reportResult(record, result)
    if not reporting then
      return
    end

    sendReport({
      event = "package_received",
      received = {
        source = record.source,
        packageArgIndex = record.packageArgIndex,
        sequence = record.sequence,
        queued = #packageQueue,
      },
      result = result,
      turtleInventory = turtleInventory(),
    })
  end

  local function printQueuedResult(record, result)
    local queueText = ""

    if #packageQueue > 0 then
      queueText = " q=" .. #packageQueue
    end

    print("Package #" .. record.sequence .. ": " .. result.action .. queueText)
    if result.reason then
      print(result.reason)
    end
  end

  local function processQueuedPackages()
    while true do
      local record = nextQueuedPackage()
      local ok, resultOrError = pcall(function()
        requireCleanTurtle()
        return handlePackageRecord(record)
      end)

      if not ok then
        if reporting then
          sendReport({
            error = tostring(resultOrError),
            received = {
              source = record.source,
              packageArgIndex = record.packageArgIndex,
              sequence = record.sequence,
              queued = #packageQueue,
            },
            turtleInventory = turtleInventory(),
          })
        end

        error(resultOrError, 0)
      end

      reportResult(record, resultOrError)
      printQueuedResult(record, resultOrError)
    end
  end

  local function watch()
    resolveStagingName()
    resolveOutputName()
    requireCleanTurtle()

    print("Watching package_received events.")
    print("Packager: " .. PACKAGER_NAME)
    print("Staging: " .. tostring(stagingName))
    print("Output: " .. tostring(outputName))
    print("Hold Ctrl+T to stop.")

    parallel.waitForAny(listenForPackages, processQueuedPackages)
  end

  if type(turtle) ~= "table" then
    error("This program must run on a crafting turtle", 0)
  end

  if args[3] then
    error("Usage: " .. programName .. " [output] or [staging output]", 0)
  end

  loadRecipeCache()
  watch()
end

return M
