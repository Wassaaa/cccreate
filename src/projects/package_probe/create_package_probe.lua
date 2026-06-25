local reporter = require("lib.reporter")

local PACKAGE_METHODS = {
  "isEditable",
  "getAddress",
  "list",
  "getItemDetail",
  "getOrderData",
}

local ORDER_METHODS = {
  "getOrderID",
  "getIndex",
  "getLinkIndex",
  "isFinal",
  "isFinalLink",
  "list",
  "getCrafts",
  "getItemDetail",
}

local MAX_JSON_DEPTH = 12

local function sorted(values)
  local result = {}

  for _, value in ipairs(values or {}) do
    table.insert(result, tostring(value))
  end

  table.sort(result)
  return result
end

local function keys(value)
  local result = {}

  if type(value) == "table" then
    for key in pairs(value) do
      table.insert(result, tostring(key))
    end
  end

  table.sort(result)
  return result
end

local function jsonSafe(value, depth, seen)
  depth = depth or 0
  seen = seen or {}

  local valueType = type(value)

  if valueType == "nil" or valueType == "string" or valueType == "number" or valueType == "boolean" then
    return value
  end

  if valueType ~= "table" then
    return "<" .. valueType .. ">"
  end

  if seen[value] then
    return "<cycle>"
  end

  if depth >= MAX_JSON_DEPTH then
    return "<max-depth>"
  end

  seen[value] = true

  local result = {}
  for key, item in pairs(value) do
    result[tostring(key)] = jsonSafe(item, depth + 1, seen)
  end

  seen[value] = nil

  return result
end

local function safeCall(object, method, ...)
  if type(object) ~= "table" or type(object[method]) ~= "function" then
    return {
      ok = false,
      error = "missing method",
    }
  end

  local results = { pcall(object[method], ...) }
  local ok = table.remove(results, 1)

  if not ok then
    return {
      ok = false,
      error = tostring(results[1]),
    }
  end

  return {
    ok = true,
    values = results,
  }
end

local function compactItem(item)
  if type(item) ~= "table" then
    return item
  end

  local compact = {
    name = item.name,
    count = item.count,
    maxCount = item.maxCount,
    displayName = item.displayName,
    nbt = item.nbt,
    keys = keys(item),
  }

  if type(item.package) == "table" then
    compact.packageKeys = keys(item.package)
  end

  return compact
end

local function compactList(items)
  if type(items) ~= "table" then
    return items
  end

  local result = {}

  for slot, item in pairs(items) do
    table.insert(result, {
      slot = slot,
      name = item.name,
      count = item.count,
      nbt = item.nbt,
    })
  end

  table.sort(result, function(left, right)
    return tostring(left.slot) < tostring(right.slot)
  end)

  return result
end

local function compactCrafts(crafts)
  if type(crafts) ~= "table" then
    return crafts
  end

  local result = {}

  for index, craft in ipairs(crafts) do
    table.insert(result, {
      index = index,
      count = craft.count,
      recipe = craft.recipe,
    })
  end

  return result
end

local function firstValue(call)
  if call.ok then
    return call.values[1]
  end

  return nil
end

local function summarizeOrder(order)
  if type(order) ~= "table" then
    return nil
  end

  local summary = {
    keys = keys(order),
  }

  for _, method in ipairs(ORDER_METHODS) do
    local call

    if method == "getItemDetail" then
      call = safeCall(order, method, 1)
      if call.ok then
        call.values[1] = compactItem(call.values[1])
      end
    elseif method == "list" then
      call = safeCall(order, method)
      if call.ok then
        call.values[1] = compactList(call.values[1])
      end
    elseif method == "getCrafts" then
      call = safeCall(order, method)
      if call.ok then
        call.values[1] = compactCrafts(call.values[1])
      end
    else
      call = safeCall(order, method)
    end

    summary[method] = call
  end

  return summary
end

local function summarizePackage(package)
  if type(package) ~= "table" then
    return nil
  end

  local summary = {
    keys = keys(package),
  }

  for _, method in ipairs(PACKAGE_METHODS) do
    local call

    if method == "getItemDetail" then
      call = safeCall(package, method, 1)
      if call.ok then
        call.values[1] = compactItem(call.values[1])
      end
    elseif method == "list" then
      call = safeCall(package, method)
      if call.ok then
        call.values[1] = compactList(call.values[1])
      end
    else
      call = safeCall(package, method)
    end

    summary[method] = call
  end

  summary.orderData = summarizeOrder(firstValue(summary.getOrderData))

  return summary
end

local function peripheralTypes(name)
  local results = { pcall(peripheral.getType, name) }
  local ok = table.remove(results, 1)

  if ok then
    return sorted(results)
  end

  return { "error:" .. tostring(results[1]) }
end

local function peripheralMethods(name)
  local ok, methods = pcall(peripheral.getMethods, name)

  if ok and type(methods) == "table" then
    return sorted(methods)
  end

  return {}
end

local function contains(values, target)
  for _, value in ipairs(values or {}) do
    if value == target then
      return true
    end
  end

  return false
end

local function inspectInventoryPeripheral(name, methods)
  local result = {}
  local object = peripheral.wrap(name)

  if contains(methods, "size") then
    result.size = safeCall(object, "size")
  end

  if contains(methods, "list") then
    result.list = safeCall(object, "list")
    if result.list.ok then
      result.list.values[1] = compactList(result.list.values[1])
    end
  end

  if contains(methods, "getItemDetail") then
    result.detail1 = safeCall(object, "getItemDetail", 1)
    if result.detail1.ok then
      local item = result.detail1.values[1]
      result.detail1.values[1] = compactItem(item)
      if type(item) == "table" and type(item.package) == "table" then
        result.detail1Package = summarizePackage(item.package)
      end
    end
  end

  return result
end

local function inspectLogisticsPeripheral(name, methods)
  if not contains(methods, "getPackage") then
    return nil
  end

  local object = peripheral.wrap(name)
  local result = {
    getAddress = safeCall(object, "getAddress"),
    heldPackage = safeCall(object, "getPackage"),
  }

  if result.heldPackage.ok then
    result.heldPackage.values[1] = summarizePackage(result.heldPackage.values[1])
  end

  return result
end

local function inspectPeripheral(name)
  local methods = peripheralMethods(name)
  local entry = {
    name = name,
    types = peripheralTypes(name),
    methods = methods,
  }

  if contains(methods, "list") or contains(methods, "getItemDetail") then
    entry.inventory = inspectInventoryPeripheral(name, methods)
  end

  entry.logistics = inspectLogisticsPeripheral(name, methods)

  return entry
end

local function turtleInventory()
  if type(turtle) ~= "table" then
    return nil
  end

  local result = {}

  for slot = 1, 16 do
    local ok, item = pcall(turtle.getItemDetail, slot, true)
    if ok and item then
      local entry = compactItem(item)

      if type(item.package) == "table" then
        entry.package = summarizePackage(item.package)
      end

      table.insert(result, {
        slot = slot,
        item = entry,
      })
    end
  end

  return result
end

local names = peripheral.getNames()
table.sort(names)

local report = {
  kind = "create_package_probe",
  computerId = os.getComputerID(),
  label = os.getComputerLabel(),
  isTurtle = type(turtle) == "table",
  turtleInventory = turtleInventory(),
  peripherals = {},
}

for _, name in ipairs(names) do
  table.insert(report.peripherals, inspectPeripheral(name))
end

reporter.send(jsonSafe(report))

print("Create package probe complete.")
print("Peripherals: " .. #report.peripherals)
print("Turtle item slots: " .. #(report.turtleInventory or {}))
print("Sent webhook report.")
