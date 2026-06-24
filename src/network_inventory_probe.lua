local function pack(...)
  return { ... }
end

local function contains(values, target)
  for _, value in ipairs(values or {}) do
    if value == target then
      return true
    end
  end

  return false
end

local function addName(names, seen, name)
  if name and not seen[name] then
    seen[name] = true
    table.insert(names, name)
  end
end

local function compactItem(item)
  if type(item) ~= "table" then
    return item
  end

  return {
    name = item.name,
    count = item.count,
    nbt = item.nbt,
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
      nbt = item.nbt,
    })
  end

  table.sort(result, function(a, b)
    return a.slot < b.slot
  end)

  return result
end

local function safeCall(name, method, ...)
  local ok, result = pcall(peripheral.call, name, method, ...)
  if ok then
    return {
      ok = true,
      value = result,
    }
  end

  return {
    ok = false,
    error = tostring(result),
  }
end

local function methodFlags(methods)
  return {
    list = contains(methods, "list"),
    size = contains(methods, "size"),
    getItemDetail = contains(methods, "getItemDetail"),
    getItemLimit = contains(methods, "getItemLimit"),
    pushItems = contains(methods, "pushItems"),
    pullItems = contains(methods, "pullItems"),
    craft = contains(methods, "craft"),
    getID = contains(methods, "getID"),
    getLabel = contains(methods, "getLabel"),
  }
end

local function hasInventoryMethods(flags)
  return flags.list or flags.size or flags.getItemDetail or flags.pushItems or flags.pullItems
end

local function likelyTurtle(name, types)
  if string.find(name, "turtle", 1, true) then
    return true
  end

  for _, typeName in ipairs(types or {}) do
    if typeName == "turtle" or typeName == "computer" then
      return true
    end
  end

  return false
end

local function inspectName(name)
  local methodOk, methods = pcall(peripheral.getMethods, name)
  if not methodOk or type(methods) ~= "table" then
    methods = {}
  end

  table.sort(methods)

  local types = pack(peripheral.getType(name))
  local flags = methodFlags(methods)
  local entry = {
    name = name,
    types = types,
    methodCount = #methods,
    flags = flags,
  }

  if hasInventoryMethods(flags) or likelyTurtle(name, types) then
    entry.methods = methods
    entry.size = safeCall(name, "size")

    local list = safeCall(name, "list")
    if list.ok then
      list.value = compactList(list.value)
    end
    entry.list = list

    local detail = safeCall(name, "getItemDetail", 1)
    if detail.ok then
      detail.value = compactItem(detail.value)
    end
    entry.detail1 = detail
  end

  return entry
end

local names = {}
local seen = {}
local modems = {}

for _, name in ipairs(peripheral.getNames()) do
  addName(names, seen, name)

  local object = peripheral.wrap(name)
  if object and type(object.getNamesRemote) == "function" then
    local modem = {
      name = name,
      isWireless = type(object.isWireless) == "function" and object.isWireless() or nil,
    }

    local okLocal, localName = pcall(object.getNameLocal)
    if okLocal then
      modem.localName = localName
    end

    local okRemote, remoteNames = pcall(object.getNamesRemote)
    if okRemote and type(remoteNames) == "table" then
      table.sort(remoteNames)
      modem.remoteNames = remoteNames

      for _, remoteName in ipairs(remoteNames) do
        addName(names, seen, remoteName)
      end
    else
      modem.remoteError = tostring(remoteNames)
    end

    table.insert(modems, modem)
  end
end

table.sort(names)

local report = {
  kind = "network_inventory_probe",
  computerId = os.getComputerID(),
  label = os.getComputerLabel(),
  isTurtle = type(turtle) == "table",
  modems = modems,
  names = {},
}

for _, name in ipairs(names) do
  table.insert(report.names, inspectName(name))
end

print(textutils.serialize(report))
