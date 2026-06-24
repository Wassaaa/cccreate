local inventoryTools = require("lib.inventory_tools")

local SOURCE_SIDE = "bottom"
local TARGET_SIDE = "back"

local args = { ... }
local command = args[1] or "status"

local function usage()
  print("inventory_example status")
  print("inventory_example move [item-count]")
  print("inventory_example move-stacks [stack-count]")
  print("inventory_example return [item-count]")
end

local function printConfiguredSides()
  print("Source inventory: " .. SOURCE_SIDE)
  print("Target inventory: " .. TARGET_SIDE)
end

local function status()
  printConfiguredSides()
  print("")
  inventoryTools.printSummary(inventoryTools.summarize(SOURCE_SIDE, 12))
  print("")
  inventoryTools.printSummary(inventoryTools.summarize(TARGET_SIDE, 12))
end

local function moveOne(sourceSide, targetSide, count)
  count = tonumber(count) or 64

  local moved, errorMessage, detail = inventoryTools.moveFirst(sourceSide, targetSide, count)
  if moved == 0 then
    print("Move failed: " .. tostring(errorMessage))
    return false
  end

  print("Moved " .. moved .. " item(s)")
  print("  Item: " .. detail.itemName)
  print("  From: " .. detail.sourceSide .. " slot " .. detail.sourceSlot)
  print("  To: " .. detail.targetSide)
  return true
end

local function moveStacks(count)
  count = tonumber(count) or 1

  local totalMoved, movedStacks, errorMessage = inventoryTools.moveStacks(SOURCE_SIDE, TARGET_SIDE, count)

  for _, move in ipairs(movedStacks) do
    print("Moved " .. move.moved .. " x " .. move.itemName .. " from slot " .. move.sourceSlot)
  end

  if errorMessage then
    print("Stopped: " .. tostring(errorMessage))
  end

  print("Total moved: " .. totalMoved)
end

if command == "status" then
  status()
elseif command == "move" then
  moveOne(SOURCE_SIDE, TARGET_SIDE, args[2])
elseif command == "move-stacks" then
  moveStacks(args[2])
elseif command == "return" then
  moveOne(TARGET_SIDE, SOURCE_SIDE, args[2])
elseif command == "help" then
  usage()
else
  print("Unknown command: " .. tostring(command))
  usage()
end
