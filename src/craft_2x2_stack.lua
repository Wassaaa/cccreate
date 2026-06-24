local INPUT_ITEM = "minecraft:nether_brick"

local DEFAULT_GRID_SIZE = nil
local DEFAULT_INPUT_INVENTORIES = nil
local DEFAULT_OUTPUT_INVENTORY = nil
local TICK_SECONDS = 0.05

local CRAFT_STACK_SIZE = 64
local CRAFT_COUNT = 64
local OUTPUT_SLOT = 16

local GRID_SLOTS = {
  ["2x2"] = { 1, 2, 5, 6 },
  ["3x3"] = { 1, 2, 3, 5, 6, 7, 9, 10, 11 },
}

local args = { ... }

local function trim(value)
  return tostring(value):match("^%s*(.-)%s*$")
end

local function copyList(values)
  local result = {}

  for _, value in ipairs(values) do
    table.insert(result, value)
  end

  return result
end

local function appendCsv(result, value)
  for part in tostring(value):gmatch("[^,]+") do
    local name = trim(part)
    if name ~= "" then
      table.insert(result, name)
    end
  end
end

local function asNameList(value)
  if not value then
    return nil
  end

  if type(value) == "table" then
    local result = {}
    for _, entry in ipairs(value) do
      appendCsv(result, entry)
    end
    return result
  end

  local result = {}
  appendCsv(result, value)
  return result
end

local function joinNames(names)
  return table.concat(names, ", ")
end

local function normalizeGridSize(value)
  if not value then
    return nil
  end

  local text = string.lower(trim(value))
  if text == "2" or text == "2x2" then
    return "2x2"
  end

  if text == "3" or text == "3x3" then
    return "3x3"
  end
end

local function parseArgs()
  local settings = {}
  local index = 1
  local gridSize = normalizeGridSize(args[index])

  if gridSize then
    settings.gridSize = gridSize
    index = index + 1
  end

  if args[index] then
    settings.outputName = args[index]
    index = index + 1
  end

  local inputNames = {}
  while args[index] do
    appendCsv(inputNames, args[index])
    index = index + 1
  end

  if #inputNames > 0 then
    settings.inputNames = inputNames
  end

  return settings
end

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

local function containsName(names, target)
  for _, name in ipairs(names) do
    if name == target then
      return true
    end
  end

  return false
end

local function remainingNames(names, selectedNames)
  local remaining = {}

  for _, name in ipairs(names) do
    if not containsName(selectedNames, name) then
      table.insert(remaining, name)
    end
  end

  return remaining
end

local function resolveInventoryToken(token, names)
  local index = tonumber(token)
  if index and names[index] then
    return names[index]
  end

  for _, name in ipairs(names) do
    if token == name then
      return name
    end
  end
end

local function parseInventoryChoices(answer, names)
  local selected = {}

  for part in answer:gmatch("[^,]+") do
    local token = trim(part)
    local name = resolveInventoryToken(token, names)

    if not name then
      return nil, token
    end

    if not containsName(selected, name) then
      table.insert(selected, name)
    end
  end

  return selected
end

local function chooseInventory(prompt, names)
  while true do
    print(prompt)
    for index, name in ipairs(names) do
      print(index .. ": " .. name)
    end

    write("> ")
    local answer = trim(read())
    local name = resolveInventoryToken(answer, names)

    if name then
      return name
    end

    print("Choose one of the listed inventory names.")
  end
end

local function chooseGridSize()
  local defaultGridSize = "2x2"

  while true do
    write("Crafting grid 2x2 or 3x3 [" .. defaultGridSize .. "]: ")
    local answer = trim(read())

    if answer == "" then
      answer = defaultGridSize
    end

    local gridSize = normalizeGridSize(answer)
    if gridSize then
      return gridSize, copyList(GRID_SLOTS[gridSize])
    end

    print("Choose 2x2 or 3x3.")
  end
end

local function selectCraftGrid(settings)
  local gridSize = settings.gridSize or normalizeGridSize(DEFAULT_GRID_SIZE)

  if gridSize then
    return gridSize, copyList(GRID_SLOTS[gridSize])
  end

  return chooseGridSize()
end

local function validateInputNames(inputNames, names)
  local result = {}

  for _, inputName in ipairs(inputNames) do
    if containsName(result, inputName) then
      error("Input inventory listed twice: " .. inputName, 0)
    end

    if not containsName(names, inputName) then
      error("Input inventory not found: " .. inputName, 0)
    end

    table.insert(result, inputName)
  end

  if #result == 0 then
    error("Choose at least one input inventory", 0)
  end

  return result
end

local function chooseInputNames(names, outputKnown)
  local inputNames = {}
  local minimumRemaining = outputKnown and 0 or 1

  while true do
    local remaining = remainingNames(names, inputNames)

    if #remaining == 0 then
      if outputKnown and #inputNames > 0 then
        return inputNames
      end

      error("Need one inventory left for output; rerun and leave it unselected", 0)
    end

    if not outputKnown and #inputNames > 0 and #remaining == 1 then
      print("Output will be: " .. remaining[1])
      return inputNames
    end

    print("Inputs: " .. (#inputNames > 0 and joinNames(inputNames) or "(none)"))
    print("Choose input numbers/names. Commas work. Blank when done.")
    for index, name in ipairs(remaining) do
      print(index .. ": " .. name)
    end

    write("> ")
    local answer = trim(read())

    if answer == "" then
      if #inputNames > 0 then
        return inputNames
      end

      print("Choose at least one input.")
    else
      local selected, invalid = parseInventoryChoices(answer, remaining)
      if not selected then
        print("Unknown inventory: " .. invalid)
      elseif #remaining - #selected < minimumRemaining then
        print("Leave at least one inventory unselected for output.")
      else
        for _, name in ipairs(selected) do
          table.insert(inputNames, name)
        end
      end
    end
  end
end

local function selectOutputName(names, inputNames, outputName)
  local available = remainingNames(names, inputNames)

  if #available == 0 then
    error("Need one inventory left for output", 0)
  end

  if outputName then
    if not containsName(available, outputName) then
      error("Output inventory not found or already selected as input: " .. outputName, 0)
    end

    return outputName
  end

  if #available == 1 then
    return available[1]
  end

  return chooseInventory("Choose output inventory.", available)
end

local function selectInventories(settings)
  local names = inventoryNames()

  if #names < 2 then
    error("Need at least two wired inventories: one input and one output", 0)
  end

  local outputName = settings.outputName or DEFAULT_OUTPUT_INVENTORY
  if outputName and not containsName(names, outputName) then
    error("Output inventory not found: " .. outputName, 0)
  end

  local inputNames = settings.inputNames or asNameList(DEFAULT_INPUT_INVENTORIES)
  if inputNames then
    inputNames = validateInputNames(inputNames, names)
  else
    local choices = outputName and remainingNames(names, { outputName }) or names
    inputNames = chooseInputNames(choices, outputName ~= nil)
  end

  outputName = selectOutputName(names, inputNames, outputName)

  return inputNames, outputName
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

local settings = parseArgs()
local gridSize, craftSlots = selectCraftGrid(settings)
local inputNames, outputName = selectInventories(settings)
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
  for _, craftSlot in ipairs(craftSlots) do
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
      if item.name == INPUT_ITEM and isCraftSlot(slot) and item.count <= CRAFT_STACK_SIZE then
        -- Keep collected input in the turtle until all craft slots are full.
      elseif item.name == INPUT_ITEM then
        if not pullUntilEmpty(firstInput, slot) then
          return false
        end
      elseif not pullUntilEmpty(output, slot) then
        return false
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
  for _, slot in ipairs(craftSlots) do
    if inputNeeded(slot) > 0 then
      return fillCraftSlot(slot)
    end
  end

  return true
end

local function craftSlotsReady()
  for _, slot in ipairs(craftSlots) do
    local item = turtle.getItemDetail(slot)
    if not item or item.name ~= INPUT_ITEM or item.count ~= CRAFT_STACK_SIZE then
      return false
    end
  end

  return true
end

print("Grid: " .. gridSize)
print("Inputs: " .. joinNames(inputNames))
print("Output: " .. outputName)
print("Turtle: " .. turtleName)
print("Crafting full " .. gridSize .. " stacks of " .. INPUT_ITEM .. ". Hold Ctrl+T to stop.")

while true do
  while not flushOutput() do
    sleep(TICK_SECONDS)
  end

  if not craftSlotsReady() then
    fillOneCraftSlot()
  end

  if craftSlotsReady() then
    turtle.select(OUTPUT_SLOT)
    if not turtle.craft(CRAFT_COUNT) then
      flushOutput()
      error("Craft failed", 0)
    end

    while not flushOutput() do
      sleep(TICK_SECONDS)
    end
  end

  sleep(TICK_SECONDS)
end
