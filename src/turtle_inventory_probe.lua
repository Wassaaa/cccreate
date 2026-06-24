local function show(value)
  return textutils.serialize(value)
end

local function compactItem(item)
  if type(item) ~= "table" then
    return item
  end

  return {
    name = item.name,
    count = item.count,
  }
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

local function run(label, fn)
  local values = { pcall(fn) }
  local ok = table.remove(values, 1)

  if ok then
    print(label .. "=" .. show(values))
  else
    print(label .. "=ERROR " .. tostring(values[1]))
  end
end

local function hasMethod(methods, target)
  for _, method in ipairs(methods or {}) do
    if method == target then
      return true
    end
  end

  return false
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
      break
    end
  end
end

print("probe=turtle_inventory")
print("localName=" .. tostring(turtleName))

if not turtleName then
  return
end

run("present", function()
  return peripheral.isPresent(turtleName)
end)

run("type", function()
  return peripheral.getType(turtleName)
end)

run("methods", function()
  local methods = peripheral.getMethods(turtleName) or {}
  return {
    list = hasMethod(methods, "list"),
    size = hasMethod(methods, "size"),
    getItemDetail = hasMethod(methods, "getItemDetail"),
    pushItems = hasMethod(methods, "pushItems"),
    pullItems = hasMethod(methods, "pullItems"),
  }
end)

run("wrap", function()
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

run("callList", function()
  return compactList(peripheral.call(turtleName, "list"))
end)

run("callSize", function()
  return peripheral.call(turtleName, "size")
end)

run("callDetail1", function()
  return compactItem(peripheral.call(turtleName, "getItemDetail", 1))
end)

run("turtleDetail1", function()
  return compactItem(turtle.getItemDetail(1))
end)
