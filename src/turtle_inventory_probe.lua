local function sorted(values)
  table.sort(values)
  return values
end

local function pack(...)
  return { ... }
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

local function methodSummary(name)
  local methods = peripheral.getMethods(name) or {}
  sorted(methods)
  return methods
end

print("Turtle inventory peripheral probe")
print("Computer ID: " .. os.getComputerID())
print("Label: " .. tostring(os.getComputerLabel()))
print("Is turtle: " .. tostring(type(turtle) == "table"))

print("Peripherals:")
for _, name in ipairs(sorted(peripheral.getNames())) do
  print("- " .. name)
  print("  types: " .. textutils.serialize(pack(peripheral.getType(name))))
  print("  methods: " .. textutils.serialize(methodSummary(name)))
end

local turtleName = nil

for _, name in ipairs(peripheral.getNames()) do
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

probe("peripheral.isPresent(local)", function()
  return peripheral.isPresent(turtleName)
end)

probe("peripheral.getType(local)", function()
  return peripheral.getType(turtleName)
end)

probe("peripheral.getMethods(local)", function()
  return methodSummary(turtleName)
end)

probe("peripheral.wrap(local) inventory methods", function()
  local object = peripheral.wrap(turtleName)
  return type(object),
    type(object and object.list),
    type(object and object.size),
    type(object and object.getItemDetail),
    type(object and object.pushItems),
    type(object and object.pullItems)
end)

probe("peripheral.call(local, list)", function()
  return peripheral.call(turtleName, "list")
end)

probe("peripheral.call(local, size)", function()
  return peripheral.call(turtleName, "size")
end)

probe("peripheral.call(local, getItemDetail, 1)", function()
  return peripheral.call(turtleName, "getItemDetail", 1)
end)

probe("turtle.getItemDetail(1)", function()
  return turtle.getItemDetail(1)
end)
