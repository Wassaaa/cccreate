local inventoryTools = {}

local SIDES = { "front", "back", "top", "bottom", "left", "right" }

local function typeName(value)
  if type(value) == "table" then
    return table.concat(value, ",")
  end

  return tostring(value)
end

local function isInventory(peripheralObject)
  return peripheralObject
    and type(peripheralObject.size) == "function"
    and type(peripheralObject.list) == "function"
    and type(peripheralObject.pushItems) == "function"
end

local function wrapInventory(side)
  if not peripheral.isPresent(side) then
    return nil, "No peripheral on " .. side
  end

  local object = peripheral.wrap(side)
  if not isInventory(object) then
    return nil, "Peripheral on " .. side .. " is not an inventory"
  end

  return object, nil
end

local function sortedSlots(size)
  local slots = {}

  for slot = 1, size do
    table.insert(slots, slot)
  end

  return slots
end

function inventoryTools.summarize(side, sampleLimit)
  sampleLimit = sampleLimit or 10

  local summary = {
    side = side,
    present = peripheral.isPresent(side),
    type = nil,
    isInventory = false,
    size = 0,
    usedSlots = 0,
    totalItems = 0,
    sample = {},
  }

  if not summary.present then
    return summary
  end

  summary.type = typeName(peripheral.getType(side))

  local object = peripheral.wrap(side)
  if not isInventory(object) then
    return summary
  end

  summary.isInventory = true
  summary.size = object.size()

  local items = object.list()
  for _, slot in ipairs(sortedSlots(summary.size)) do
    local item = items[slot]
    if item then
      summary.usedSlots = summary.usedSlots + 1
      summary.totalItems = summary.totalItems + item.count

      if #summary.sample < sampleLimit then
        table.insert(summary.sample, {
          slot = slot,
          name = item.name,
          count = item.count,
        })
      end
    end
  end

  return summary
end

function inventoryTools.printSummary(summary)
  print("Side: " .. summary.side)

  if not summary.present then
    print("  No peripheral")
    return
  end

  print("  Type: " .. tostring(summary.type))

  if not summary.isInventory then
    print("  Not an inventory")
    return
  end

  print("  Slots: " .. summary.usedSlots .. " used / " .. summary.size .. " total")
  print("  Total items: " .. summary.totalItems)

  if #summary.sample == 0 then
    print("  Empty")
    return
  end

  print("  Sample:")
  for _, item in ipairs(summary.sample) do
    print("    " .. item.slot .. ": " .. item.name .. " x" .. item.count)
  end
end

function inventoryTools.firstOccupiedSlot(side)
  local inventory, errorMessage = wrapInventory(side)
  if not inventory then
    return nil, nil, errorMessage
  end

  local items = inventory.list()
  for _, slot in ipairs(sortedSlots(inventory.size())) do
    if items[slot] then
      return slot, items[slot], nil
    end
  end

  return nil, nil, "No items in " .. side
end

function inventoryTools.moveFirst(sourceSide, targetSide, limit)
  limit = limit or 64

  local source, sourceError = wrapInventory(sourceSide)
  if not source then
    return 0, sourceError
  end

  local target, targetError = wrapInventory(targetSide)
  if not target then
    return 0, targetError
  end

  local slot, item, slotError = inventoryTools.firstOccupiedSlot(sourceSide)
  if not slot then
    return 0, slotError
  end

  local moved = source.pushItems(targetSide, slot, limit)
  if moved == 0 then
    return 0, "No items moved. Target may be full or unable to accept " .. item.name
  end

  return moved, nil, {
    sourceSide = sourceSide,
    targetSide = targetSide,
    sourceSlot = slot,
    itemName = item.name,
  }
end

function inventoryTools.moveStacks(sourceSide, targetSide, maxStacks)
  maxStacks = maxStacks or 1

  local movedStacks = {}
  local totalMoved = 0

  for _ = 1, maxStacks do
    local moved, errorMessage, detail = inventoryTools.moveFirst(sourceSide, targetSide, 64)
    if moved == 0 then
      return totalMoved, movedStacks, errorMessage
    end

    totalMoved = totalMoved + moved
    detail.moved = moved
    table.insert(movedStacks, detail)
  end

  return totalMoved, movedStacks, nil
end

function inventoryTools.sides()
  return SIDES
end

return inventoryTools
