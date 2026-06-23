local INPUT = "minecraft:nether_brick"
local OUTPUT = "minecraft:nether_bricks"
local CRAFT_SLOTS = { 1, 2, 5, 6 }
local OUTPUT_SLOT = 16

local args = { ... }

local function isInventory(name)
  local object = peripheral.wrap(name)
  return object
    and type(object.list) == "function"
    and type(object.pushItems) == "function"
    and type(object.pullItems) == "function"
end

local function findInventory()
  local inventories = {}

  for _, name in ipairs(peripheral.getNames()) do
    if isInventory(name) then
      table.insert(inventories, name)
    end
  end

  if #inventories == 1 then
    return inventories[1]
  end

  if #inventories == 0 then
    error("No inventory found on the wired network", 0)
  end

  error("Multiple inventories found: " .. table.concat(inventories, ", ") .. ". Run with the inventory name.", 0)
end

local chestName = args[1] or findInventory()
local chest = peripheral.wrap(chestName) or error("No inventory named " .. chestName, 0)

if not isInventory(chestName) then
  error(chestName .. " is not an inventory", 0)
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

local turtleName = findTurtleName()
if not turtleName then
  error("Need an active wired modem. Wireless modems cannot do inventory transfers.", 0)
end

local function clearTurtle()
  for slot = 1, 16 do
    chest.pullItems(turtleName, slot, 64)
    if turtle.getItemCount(slot) > 0 then
      return false
    end
  end
  return true
end

local function countInput()
  local total = 0
  for _, item in pairs(chest.list()) do
    if item.name == INPUT then
      total = total + item.count
    end
  end
  return total
end

local function pushInput(toSlot)
  local needed = 16

  while needed > 0 do
    local moved = 0

    for slot, item in pairs(chest.list()) do
      if item.name == INPUT then
        moved = chest.pushItems(turtleName, slot, math.min(needed, item.count), toSlot)
        if moved > 0 then
          needed = needed - moved
          break
        end
      end
    end

    if moved == 0 then
      return false
    end
  end

  return true
end

print("Inventory: " .. chestName)
print("Turtle: " .. turtleName)
print("Crafting " .. INPUT .. " into " .. OUTPUT .. ". Hold Ctrl+T to stop.")

while true do
  if not clearTurtle() then
    error("Could not clear turtle inventory into " .. chestName, 0)
  end

  if countInput() >= 64 then
    for _, slot in ipairs(CRAFT_SLOTS) do
      if not pushInput(slot) then
        clearTurtle()
        error("Could not push " .. INPUT .. " into turtle slot " .. slot, 0)
      end
    end

    turtle.select(OUTPUT_SLOT)
    if not turtle.craft(16) then
      clearTurtle()
      error("Craft failed; expected " .. OUTPUT, 0)
    end

    local crafted = turtle.getItemDetail(OUTPUT_SLOT)
    if not crafted or crafted.name ~= OUTPUT then
      clearTurtle()
      error("Crafted unexpected item", 0)
    end

    if chest.pullItems(turtleName, OUTPUT_SLOT, 64) == 0 then
      error("Could not pull crafted " .. OUTPUT .. " back into front inventory", 0)
    end
  else
    sleep(1)
  end
end
