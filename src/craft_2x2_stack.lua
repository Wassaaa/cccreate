local INPUT = "minecraft:nether_brick"
local OUTPUT = "minecraft:nether_bricks"
local CRAFT_SLOTS = { 1, 2, 5, 6 }
local OUTPUT_SLOT = 16

local chest = peripheral.wrap("front") or error("No inventory in front", 0)

local function findTurtleName()
  for _, name in ipairs(peripheral.getNames()) do
    local modem = peripheral.wrap(name)
    if modem and type(modem.getNameLocal) == "function" and not modem.isWireless() then
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
  end
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

print("Crafting " .. INPUT .. " into " .. OUTPUT .. ". Hold Ctrl+T to stop.")

while true do
  clearTurtle()

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

    if chest.pullItems(turtleName, OUTPUT_SLOT, 64) == 0 then
      error("Could not pull crafted " .. OUTPUT .. " back into front inventory", 0)
    end
  else
    sleep(1)
  end
end
