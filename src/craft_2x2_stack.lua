local INPUT_ITEM = "minecraft:nether_brick"
local OUTPUT_ITEM = "minecraft:nether_bricks"

local DEFAULT_INPUT_INVENTORY = nil
local DEFAULT_OUTPUT_INVENTORY = nil
local TICK_SECONDS = 0.05

local CRAFT_COUNT = 16
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

local function inventoryNames()
  local names = {}

  for _, name in ipairs(peripheral.getNames()) do
    if isInventory(name) then
      table.insert(names, name)
    end
  end

  table.sort(names)
  return names
end

local function chooseInventory(prompt, names, exclude)
  while true do
    print(prompt)
    for index, name in ipairs(names) do
      if name ~= exclude then
        print(index .. ": " .. name)
      end
    end

    write("> ")
    local answer = read()
    local index = tonumber(answer)

    if index and names[index] and names[index] ~= exclude then
      return names[index]
    end

    if isInventory(answer) and answer ~= exclude then
      return answer
    end

    print("Choose one of the listed inventory names.")
  end
end

local function selectInventories()
  local inputName = args[1] or DEFAULT_INPUT_INVENTORY
  local outputName = args[2] or DEFAULT_OUTPUT_INVENTORY
  local names = inventoryNames()

  if #names < 2 then
    error("Need at least two wired inventories: one input and one output", 0)
  end

  if inputName and not isInventory(inputName) then
    error("Input inventory not found: " .. inputName, 0)
  end

  if outputName and not isInventory(outputName) then
    error("Output inventory not found: " .. outputName, 0)
  end

  if not inputName and not outputName and #names == 2 then
    outputName = chooseInventory("Which inventory is output?", names)
    inputName = names[1] == outputName and names[2] or names[1]
  else
    if not inputName then
      inputName = chooseInventory("Which inventory is input?", names, outputName)
    end

    if not outputName then
      outputName = chooseInventory("Which inventory is output?", names, inputName)
    end
  end

  if inputName == outputName then
    error("Input and output inventories must be different", 0)
  end

  return inputName, outputName
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

local inputName, outputName = selectInventories()
local input = peripheral.wrap(inputName)
local output = peripheral.wrap(outputName)
local turtleName = findTurtleName()

if not turtleName then
  error("Need an active wired modem. Wireless modems cannot do inventory transfers.", 0)
end

local function countInput()
  local total = 0

  for _, item in pairs(input.list()) do
    if item.name == INPUT_ITEM then
      total = total + item.count
    end
  end

  return total
end

local function pullUntilEmpty(target, slot)
  while turtle.getItemCount(slot) > 0 do
    local moved = target.pullItems(turtleName, slot, turtle.getItemCount(slot))
    if not moved or moved <= 0 then
      return false
    end
  end

  return true
end

local function clearTurtle()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item then
      local target = nil
      if item.name == INPUT_ITEM then
        target = input
      elseif item.name == OUTPUT_ITEM then
        target = output
      else
        error("Unexpected item in turtle slot " .. slot .. ": " .. item.name, 0)
      end

      if not pullUntilEmpty(target, slot) then
        return false
      end
    end
  end

  return true
end

local function pushInput(toSlot)
  local needed = CRAFT_COUNT

  while needed > 0 do
    local moved = 0

    for slot, item in pairs(input.list()) do
      if item.name == INPUT_ITEM then
        moved = input.pushItems(turtleName, slot, math.min(needed, item.count), toSlot)
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

print("Input: " .. inputName)
print("Output: " .. outputName)
print("Turtle: " .. turtleName)
print("Crafting " .. INPUT_ITEM .. " into " .. OUTPUT_ITEM .. ". Hold Ctrl+T to stop.")

while true do
  while not clearTurtle() do
    sleep(TICK_SECONDS)
  end

  if countInput() >= CRAFT_COUNT * #CRAFT_SLOTS then
    for _, slot in ipairs(CRAFT_SLOTS) do
      if not pushInput(slot) then
        clearTurtle()
        error("Could not push " .. INPUT_ITEM .. " into turtle slot " .. slot, 0)
      end
    end

    turtle.select(OUTPUT_SLOT)
    if not turtle.craft(CRAFT_COUNT) then
      clearTurtle()
      error("Craft failed; expected " .. OUTPUT_ITEM, 0)
    end

    local crafted = turtle.getItemDetail(OUTPUT_SLOT)
    if not crafted or crafted.name ~= OUTPUT_ITEM then
      clearTurtle()
      error("Crafted unexpected item", 0)
    end

    while not pullUntilEmpty(output, OUTPUT_SLOT) do
      sleep(TICK_SECONDS)
    end
  end

  sleep(TICK_SECONDS)
end
