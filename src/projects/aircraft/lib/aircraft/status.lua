local classify = require("lib.aircraft.classify")
local coords = require("lib.aircraft.coords")

local status = {}

local ROLE_ORDER = {
  "front_left",
  "front_right",
  "rear_left",
  "rear_right",
}

local FAMILY_ORDER = {
  "scalarActuator",
  "rotorBearing",
}

local function safePeripheralTypes(name)
  local values = { pcall(peripheral.getType, name) }
  local ok = table.remove(values, 1)

  if not ok then
    return {}
  end

  return values
end

local function isRouterType(types)
  for _, typeName in ipairs(types or {}) do
    if string.find(string.lower(tostring(typeName)), "peripheral_router", 1, true) then
      return true
    end
  end

  return false
end

local function findRouter()
  for _, peripheralName in ipairs(peripheral.getNames()) do
    local types = safePeripheralTypes(peripheralName)

    if isRouterType(types) then
      local wrapped = peripheral.wrap(peripheralName)
      if wrapped and type(wrapped.wrap) == "function" then
        return wrapped, peripheralName
      end
    end
  end

  local router = peripheral.find("peripheral_router")
  if router and type(router.wrap) == "function" then
    return router, nil
  end

  return nil, nil
end

local function loadScan(path)
  if not fs.exists(path) then
    error("No aircraft scan at " .. path .. ". Run aircraft scan first.", 0)
  end

  local handle = fs.open(path, "r")
  if not handle then
    error("Could not open " .. path, 0)
  end

  local contents = handle.readAll()
  handle.close()

  local report = textutils.unserialize(contents)
  if type(report) ~= "table" or report.kind ~= "aircraft_scan" then
    error(path .. " is not an aircraft_scan report", 0)
  end

  return report
end

local function coordKey(coord)
  return coord.key or coords.key(coord.x, coord.y, coord.z)
end

local function indexPeripherals(report)
  local index = {}

  for _, entry in ipairs(report.peripherals or {}) do
    index[coordKey(entry.coord)] = entry
  end

  return index
end

local function sortedFunctionNames(object)
  local names = {}

  for name, value in pairs(object or {}) do
    if type(value) == "function" then
      table.insert(names, name)
    end
  end

  table.sort(names)
  return names
end

local function contains(values, target)
  for _, value in ipairs(values or {}) do
    if value == target then
      return true
    end
  end

  return false
end

local function readMethodList(methods, limit)
  local result = classify.sampleMethodList(methods, limit)

  for _, method in ipairs(methods or {}) do
    local startsSafe = string.sub(method, 1, 3) == "get" or string.sub(method, 1, 2) == "is"

    if startsSafe and not contains(result, method) then
      table.insert(result, method)
      if #result >= limit then
        break
      end
    end
  end

  return result
end

local function compactValue(value)
  if value == nil then
    return "nil"
  end

  if type(value) == "number" then
    return tostring(math.floor(value * 1000 + 0.5) / 1000)
  end

  if type(value) == "string" or type(value) == "boolean" then
    return tostring(value)
  end

  local ok, serialized = pcall(textutils.serialize, value)
  if ok then
    serialized = string.gsub(serialized, "\n", " ")
    if #serialized > 60 then
      return string.sub(serialized, 1, 57) .. "..."
    end

    return serialized
  end

  return tostring(value)
end

local function callReadMethod(object, method)
  if type(object[method]) ~= "function" then
    return method .. "=missing"
  end

  local results = { pcall(object[method]) }
  local ok = table.remove(results, 1)

  if not ok then
    return method .. "=err:" .. tostring(results[1])
  end

  if #results == 0 then
    return method .. "=nil"
  elseif #results == 1 then
    return method .. "=" .. compactValue(results[1])
  end

  return method .. "=" .. compactValue(results)
end

local function readDevice(router, coord, entry, limit)
  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok then
    return false, "wrap error: " .. tostring(objectOrError)
  end

  if not objectOrError then
    return false, "no peripheral"
  end

  local methods = entry and entry.methods or sortedFunctionNames(objectOrError)
  local reads = {}

  for _, method in ipairs(readMethodList(methods, limit)) do
    table.insert(reads, callReadMethod(objectOrError, method))
  end

  if #reads == 0 then
    return true, "no read methods selected"
  end

  return true, table.concat(reads, " ")
end

local function printOrientation(report)
  local orientation = report.orientation or {}

  print(
    "orientation front="
      .. coords.axisLabel(orientation.frontVector)
      .. " left="
      .. coords.axisLabel(orientation.leftVector)
      .. " up="
      .. coords.axisLabel(orientation.upVector)
  )

  if orientation.sources then
    print(
      "sources front="
        .. tostring(orientation.sources.frontVector)
        .. " left="
        .. tostring(orientation.sources.leftVector)
        .. " up="
        .. tostring(orientation.sources.upVector)
    )
  end
end

local function printDeviceLine(router, index, label, coord, limit)
  local entry = index[coordKey(coord)]
  local ok, result = readDevice(router, coord, entry, limit)
  local prefix = ok and "  " or "  ! "

  print(prefix .. label .. " " .. coords.label(coord) .. " " .. result)
end

local function printGimbal(router, report, index, limit)
  local hints = report.orientation and report.orientation.sideHints or {}

  for side, hint in pairs(hints) do
    if not hint.ambiguous and hint.coord then
      printDeviceLine(router, index, "side_" .. side, hint.coord, limit)
    end
  end
end

local function printFamily(router, report, index, family, limit)
  local roles = report.orientation
    and report.orientation.roles
    and report.orientation.roles[family]

  print(family .. ":")

  if not roles then
    print("  no role map")
    return
  end

  for _, role in ipairs(ROLE_ORDER) do
    local mapped = roles[role]

    if mapped and mapped.coord then
      printDeviceLine(router, index, role, mapped.coord, limit)
    else
      print("  " .. role .. " missing")
    end
  end
end

function status.run(config)
  local scanPath = config.reportPath or "/aircraft_scan.txt"
  local report = loadScan(scanPath)
  local router, routerName = findRouter()

  if not router then
    error("No peripheral_router with wrap(x, y, z) found", 0)
  end

  local index = indexPeripherals(report)
  local limit = tonumber(config.statusReadLimit) or 8

  print("Aircraft status from " .. scanPath)
  print("Router: " .. tostring(routerName or (report.router and report.router.name)))
  printOrientation(report)
  print("side sensors:")
  printGimbal(router, report, index, limit)

  for _, family in ipairs(FAMILY_ORDER) do
    printFamily(router, report, index, family, limit)
  end
end

return status
