local classify = require("lib.aircraft.classify")
local coords = require("lib.aircraft.coords")
local kineticScada = require("lib.aircraft.kinetic_scada")
local reporting = require("lib.aircraft.reporting")

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
  "displaySink",
}

local SENSOR_ORDER = {
  "navigationSensor",
  "altitudeSensor",
}

local function copyPlain(value, depth)
  if type(value) ~= "table" then
    return value
  end

  depth = depth or 0
  if depth > 8 then
    return tostring(value)
  end

  local result = {}
  for key, child in pairs(value) do
    if type(child) ~= "function" then
      result[copyPlain(key, depth + 1)] = copyPlain(child, depth + 1)
    end
  end

  return result
end

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

local function hasCategory(entry, category)
  return contains(entry and entry.categories, category)
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

local function callReadMethodReport(object, method)
  if type(object[method]) ~= "function" then
    return {
      method = method,
      ok = false,
      error = "missing",
      display = method .. "=missing",
    }
  end

  local results = { pcall(object[method]) }
  local ok = table.remove(results, 1)

  if not ok then
    local display = method .. "=err:" .. tostring(results[1])
    return {
      method = method,
      ok = false,
      error = tostring(results[1]),
      display = display,
    }
  end

  local value
  if #results == 0 then
    value = nil
  elseif #results == 1 then
    value = results[1]
  else
    value = results
  end

  return {
    method = method,
    ok = true,
    value = copyPlain(value),
    display = method .. "=" .. compactValue(value),
  }
end

local function readDisplay(read)
  return read.display or (tostring(read.method) .. "=" .. compactValue(read.value))
end

local function formatDeviceReadout(device)
  if not device.ok then
    return device.error or "read failed"
  end

  if #device.reads == 0 then
    return "no read methods selected"
  end

  local parts = {}
  for _, read in ipairs(device.reads) do
    table.insert(parts, readDisplay(read))
  end

  return table.concat(parts, " ")
end

local function readDeviceReport(router, coord, entry, limit)
  local device = {
    coord = copyPlain(coord),
    label = coords.label(coord),
    ok = false,
    reads = {},
  }

  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok then
    device.error = "wrap error: " .. tostring(objectOrError)
    return device
  end

  if not objectOrError then
    device.error = "no peripheral"
    return device
  end

  local methods = entry and entry.methods or sortedFunctionNames(objectOrError)
  device.ok = true
  device.methods = readMethodList(methods, limit)

  for _, method in ipairs(device.methods) do
    table.insert(device.reads, callReadMethodReport(objectOrError, method))
  end

  return device
end

local function readDevice(router, coord, entry, limit)
  local device = readDeviceReport(router, coord, entry, limit)
  return device.ok, formatDeviceReadout(device)
end

local function readSideSensors(router, report, index, limit)
  local result = {}
  local hints = report.orientation and report.orientation.sideHints or {}

  for side, hint in pairs(hints) do
    if not hint.ambiguous and hint.coord then
      result[side] = readDeviceReport(router, hint.coord, index[coordKey(hint.coord)], limit)
    else
      result[side] = {
        ok = false,
        error = "ambiguous matches=" .. tostring(hint.count),
      }
    end
  end

  return result
end

local function readFamily(router, report, index, family, limit)
  local roles = report.orientation
    and report.orientation.roles
    and report.orientation.roles[family]
  local reads = {}

  if not roles then
    return reads
  end

  for _, role in ipairs(ROLE_ORDER) do
    local mapped = roles[role]
    if mapped and mapped.coord then
      reads[role] = readDeviceReport(router, mapped.coord, index[coordKey(mapped.coord)], limit)
    else
      reads[role] = {
        ok = false,
        error = "missing role",
      }
    end
  end

  return reads
end

local function readCategory(router, report, category, limit)
  local reads = {}

  for _, entry in ipairs(report.peripherals or {}) do
    if hasCategory(entry, category) and entry.coord then
      local key = coordKey(entry.coord)
      reads[key] = readDeviceReport(router, entry.coord, entry, limit)
    end
  end

  return reads
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

local function printKineticScada(scada)
  local summary = scada and scada.summary
  if not summary or (summary.nodes or 0) == 0 then
    print("kineticScada: none")
    return
  end

  print(
    "kineticScada: nodes="
      .. tostring(summary.nodes or 0)
      .. " networks="
      .. tostring(summary.networks or 0)
      .. " subnetworks="
      .. tostring(summary.subnetworks or 0)
      .. " edges="
      .. tostring(summary.edges or 0)
      .. "/"
      .. tostring(summary.resolvedEdges or 0)
      .. " resolved"
  )
  print(
    "  drivers="
      .. tostring(summary.drivers or 0)
      .. " consumers="
      .. tostring(summary.consumers or 0)
      .. " generators="
      .. tostring(summary.generators or 0)
      .. " leaves="
      .. tostring(summary.leaves or 0)
      .. " unnetworked="
      .. tostring(summary.unnetworked or 0)
      .. " warnings="
      .. tostring(summary.warnings or 0)
  )
end

function status.run(config)
  local report = status.collect(config)
  local path = "/aircraft_status.txt"

  reporting.save(report, path, config, { localReport = false })
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  print("Aircraft status report: " .. (config.sendWebhook ~= false and "webhook" or "webhook disabled"))
  printOrientation(report.scan)
  print("side sensors: " .. tostring(report.summary.sideSensors))

  for _, family in ipairs(FAMILY_ORDER) do
    print(family .. ": " .. tostring(report.summary[family] or 0))
  end

  for _, category in ipairs(SENSOR_ORDER) do
    print(category .. ": " .. tostring(report.summary[category] or 0))
  end

  printKineticScada(report.kineticScada)
end

function status.collect(config)
  local scanPath = config.reportPath or "/aircraft_scan.txt"
  local scan = loadScan(scanPath)
  local router, routerName = findRouter()
  local scada = scan.kineticScada or kineticScada.build(scan)

  if not router then
    error("No peripheral_router with wrap(x, y, z) found", 0)
  end

  local index = indexPeripherals(scan)
  local limit = tonumber(config.statusReadLimit) or 8
  local statusReport = {
    kind = "aircraft_status",
    createdAt = os.date("%Y-%m-%d %H:%M:%S"),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    scanPath = scanPath,
    router = {
      name = routerName or (scan.router and scan.router.name),
    },
    scan = {
      orientation = copyPlain(scan.orientation),
      summary = copyPlain(scan.summary),
    },
    kineticScada = copyPlain(scada),
    sideSensors = readSideSensors(router, scan, index, limit),
    families = {},
    sensors = {},
    summary = {
      sideSensors = 0,
      kineticScada = copyPlain(scada and scada.summary),
    },
  }

  for _, _ in pairs(statusReport.sideSensors) do
    statusReport.summary.sideSensors = statusReport.summary.sideSensors + 1
  end

  for _, family in ipairs(FAMILY_ORDER) do
    statusReport.families[family] = readFamily(router, scan, index, family, limit)
    statusReport.summary[family] = 0

    for _, _ in pairs(statusReport.families[family]) do
      statusReport.summary[family] = statusReport.summary[family] + 1
    end
  end

  for _, category in ipairs(SENSOR_ORDER) do
    statusReport.sensors[category] = readCategory(router, scan, category, limit)
    statusReport.summary[category] = 0

    for _, _ in pairs(statusReport.sensors[category]) do
      statusReport.summary[category] = statusReport.summary[category] + 1
    end
  end

  return statusReport
end

return status
