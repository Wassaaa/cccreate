local function show(value)
  return textutils.serialize(value)
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

term.clear()
term.setCursorPos(1, 1)

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

run("wrapObject", function()
  return type(peripheral.wrap(turtleName))
end)

run("callList", function()
  return peripheral.call(turtleName, "list")
end)

run("turtleDetail1", function()
  local item = turtle.getItemDetail(1)
  if item then
    return { name = item.name, count = item.count }
  end
end)
