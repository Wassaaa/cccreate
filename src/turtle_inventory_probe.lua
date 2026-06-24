local function pack(...)
  return { ... }
end

local function sorted(values)
  table.sort(values)
  return values
end

local function compactList(items)
  local result = {}

  if type(items) ~= "table" then
    return items
  end

  for slot, item in pairs(items) do
    table.insert(result, {
      slot = slot,
      name = item.name,
      count = item.count,
    })
  end

  table.sort(result, function(a, b)
    return a.slot < b.slot
  end)

  return result
end

local function hasMethod(methods, target)
  for _, method in ipairs(methods or {}) do
    if method == target then
      return true
    end
  end

  return false
end

local function printResult(label, ok, ...)
  if ok then
    print(label .. ": " .. textutils.serialize(pack(...)))
  else
    print(label .. " ERROR: " .. tostring((...)))
  end
end

local function probe(label, fn)
  printResult(label, pcall(fn))
end

local function getMethods(name)
  local methods = peripheral.getMethods(name) or {}
  table.sort(methods)
  return methods
end

local label = os.getComputerLabel()
local names = sorted(peripheral.getNames())
local turtleName = nil

print("Turtle inventory peripheral probe")
print("Computer ID: " .. os.getComputerID())
print("Label: " .. tostring(label))
print("Is turtle: " .. tostring(type(turtle) == "table"))
print("Peripherals: " .. textutils.serialize(names))

for _, name in ipairs(names) do
  print(name .. " types: " .. textutils.serialize(pack(peripheral.getType(name))))
end

for _, name in ipairs(names) do
  local modem = peripheral.wrap(name)
  if modem
    and type(modem.getNameLocal) == "function"
    and (type(modem.isWireless) ~= "function" or not modem.isWireless())
  then
    local ok, localName = pcall(modem.getNameLocal)
    if ok and localName then
      turtleName = localName
      print("Local wired name from " .. name .. ": " .. turtleName)
      break
    end
  end
end

if not turtleName then
  print("No local wired turtle name found.")
  return
end

probe("local present", function()
  return peripheral.isPresent(turtleName)
end)

probe("local type", function()
  return peripheral.getType(turtleName)
end)

probe("local method flags", function()
  local methods = getMethods(turtleName)
  return {
    list = hasMethod(methods, "list"),
    size = hasMethod(methods, "size"),
    getItemDetail = hasMethod(methods, "getItemDetail"),
    pushItems = hasMethod(methods, "pushItems"),
    pullItems = hasMethod(methods, "pullItems"),
  }
end)

probe("wrap method types", function()
  local object = peripheral.wrap(turtleName)
  return {
    object = type(object),
    list = type(object and object.list),
    size = type(object and object.size),
    getItemDetail = type(object and object.getItemDetail),
    pushItems = type(object and object.pushItems),
    pullItems = type(object and object.pullItems),
  }
end)

probe("call list", function()
  return compactList(peripheral.call(turtleName, "list"))
end)

probe("call size", function()
  return peripheral.call(turtleName, "size")
end)

probe("call detail 1", function()
  return peripheral.call(turtleName, "getItemDetail", 1)
end)

probe("turtle detail 1", function()
  local item = turtle.getItemDetail(1)
  if not item then
    return nil
  end

  return {
    name = item.name,
    count = item.count,
  }
end)
