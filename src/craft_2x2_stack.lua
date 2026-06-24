local INPUT_ITEM = "minecraft:nether_brick"
local OUTPUT_ITEM = "minecraft:nether_bricks"

local DEFAULT_INPUT_INVENTORIES = nil
local TICK_SECONDS = 0.05

local CRAFT_STACK_SIZE = 64
local CRAFT_COUNT = 64
local CRAFT_SLOTS = { 1, 2, 5, 6 }
local OUTPUT_SLOT = 16

local args = { ... }

local function isInventory(name)
  local object = peripheral.wrap(name)
  return object
    and type(object.list) == "function"
    and type(object.size) == "function"
    and type(object.getItemLimit) == "function"
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

local function copyList(values)
  local result = {}

  for _, value in ipairs(values) do
    table.insert(result, value)
  end

  return result
end

local function removeName(names, selectedName)
  for index, name in ipairs(names) do
    if name == selectedName then
      table.remove(names, index)
      return true
    end
  end

  return false
end

local function joinNames(names)
  return table.concat(names, ", ")
end

local function chooseInventory(prompt, names)
  while true do
    print(prompt)
    for index, name in ipairs(names) do
      print(index .. ": " .. name)
    end

    write("> ")
    local answer = read()
    local index = tonumber(answer)

    if index and names[index] then
      return names[index]
    end

    for _, name in ipairs(names) do
      if answer == name then
        return answer
      end
    end

    print("Choose one of the listed inventory names.")
  end
end

local function configuredInputNames()
  if #args > 0 then
    return args
  end

  return DEFAULT_INPUT_INVENTORIES
end

local function validateInputNames(inputNames, names)
  local remaining = copyList(names)
  local seen = {}

  for _, inputName in ipairs(inputNames) do
    if seen[inputName] then
      error("Input inventory listed twice: " .. inputName, 0)
    end

    seen[inputName] = true

    if not removeName(remaining, inputName) then
      error("Input inventory not found: " .. inputName, 0)
    end
  end

  if #inputNames == 0 then
    error("Choose at least one input inventory", 0)
  end

  if #remaining ~= 1 then
    error("Select every input inventory so exactly one inventory remains as output", 0)
  end

  return copyList(inputNames), remaining[1]
end

local function chooseInputNames(names)
  local remaining = copyList(names)
  local inputNames = {}

  while #remaining > 1 do
    local inputName = chooseInventory("Choose next input. Last remaining inventory becomes output.", remaining)
    table.insert(inputNames, inputName)
    removeName(remaining, inputName)
  end

  return inputNames, remaining[1]
end

local function selectInventories()
  local names = inventoryNames()

  if #names < 2 then
    error("Need at least two wired inventories: one input and one output", 0)
  end

  local inputNames = configuredInputNames()
  if inputNames then
    return validateInputNames(inputNames, names)
  end

  return chooseInputNames(names)
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

local inputNames, outputName = selectInventories()
local inputs = {}

for _, inputName in ipairs(inputNames) do
  table.insert(inputs, {
    name = inputName,
    object = peripheral.wrap(inputName),
  })
end

local firstInput = inputs[1].object
local output = peripheral.wrap(outputName)
local turtleName = findTurtleName()

if not turtleName then
  error("Need an active wired modem. Wireless modems cannot do inventory transfers.", 0)
end

local function countInput()
  local total = 0

  for _, input in ipairs(inputs) do
    for _, item in pairs(input.object.list()) do
      if item.name == INPUT_ITEM then
        total = total + item.count
      end
    end
  end

  return total
end

local function isCraftSlot(slot)
  for _, craftSlot in ipairs(CRAFT_SLOTS) do
    if slot == craftSlot then
      return true
    end
  end

  return false
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

local function flushOutput()
  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)

    if item then
      if item.name == OUTPUT_ITEM then
        if not pullUntilEmpty(output, slot) then
          return false
        end
      elseif item.name == INPUT_ITEM and isCraftSlot(slot) and item.count <= CRAFT_STACK_SIZE then
        -- Keep collected input in the turtle until all craft slots are full.
      elseif item.name == INPUT_ITEM then
        if not pullUntilEmpty(firstInput, slot) then
          return false
        end
      else
        error("Unexpected item in turtle slot " .. slot .. ": " .. item.name, 0)
      end
    end
  end

  return true
end

local function inputNeeded(slot)
  local item = turtle.getItemDetail(slot)

  if not item then
    return CRAFT_STACK_SIZE
  end

  if item.name ~= INPUT_ITEM or item.count > CRAFT_STACK_SIZE then
    error("Unexpected item in craft slot " .. slot .. ": " .. item.name, 0)
  end

  return CRAFT_STACK_SIZE - item.count
end

local function inventorySpaceFor(target, itemName)
  local space = 0
  local listed = target.list()

  for slot = 1, target.size() do
    local item = listed[slot]
    local limit = target.getItemLimit(slot)

    if not item then
      space = space + limit
    elseif item.name == itemName and item.count < limit then
      space = space + limit - item.count
    end
  end

  return space
end

local function fillCraftSlot(toSlot)
  local needed = inputNeeded(toSlot)
  if needed == 0 then
    return true
  end

  if countInput() < needed then
    return false
  end

  while needed > 0 do
    local moved = 0

    for _, input in ipairs(inputs) do
      for slot, item in pairs(input.object.list()) do
        if item.name == INPUT_ITEM then
          moved = input.object.pushItems(turtleName, slot, math.min(needed, item.count), toSlot)
          if moved > 0 then
            needed = needed - moved
            break
          end
        end
      end

      if moved > 0 then
        break
      end
    end

    if moved == 0 then
      return false
    end
  end

  return true
end

local function fillOneCraftSlot()
  for _, slot in ipairs(CRAFT_SLOTS) do
    if inputNeeded(slot) > 0 then
      return fillCraftSlot(slot)
    end
  end

  return true
end

local function craftSlotsReady()
  for _, slot in ipairs(CRAFT_SLOTS) do
    local item = turtle.getItemDetail(slot)
    if not item or item.name ~= INPUT_ITEM or item.count ~= CRAFT_STACK_SIZE then
      return false
    end
  end

  return true
end

print("Inputs: " .. joinNames(inputNames))
print("Output: " .. outputName)
print("Turtle: " .. turtleName)
print("Crafting full stacks of " .. INPUT_ITEM .. " into " .. OUTPUT_ITEM .. ". Hold Ctrl+T to stop.")

while true do
  while not flushOutput() do
    sleep(TICK_SECONDS)
  end

  if not craftSlotsReady() then
    fillOneCraftSlot()
  end

  if craftSlotsReady() and inventorySpaceFor(output, OUTPUT_ITEM) >= CRAFT_COUNT then
    turtle.select(OUTPUT_SLOT)
    if not turtle.craft(CRAFT_COUNT) then
      flushOutput()
      error("Craft failed; expected " .. OUTPUT_ITEM, 0)
    end

    local crafted = turtle.getItemDetail(OUTPUT_SLOT)
    if not crafted or crafted.name ~= OUTPUT_ITEM or crafted.count ~= CRAFT_COUNT then
      flushOutput()
      error("Crafted unexpected item", 0)
    end

    while not pullUntilEmpty(output, OUTPUT_SLOT) do
      sleep(TICK_SECONDS)
    end
  end

  sleep(TICK_SECONDS)
end
