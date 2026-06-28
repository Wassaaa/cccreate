local coords = require("lib.aircraft.coords")
local reporting = require("lib.aircraft.reporting")

local actuatorTest = {}

local ROLE_ORDER = {
  "front_left",
  "front_right",
  "rear_left",
  "rear_right",
}

local function now()
  return os.date("%Y-%m-%d %H:%M:%S")
end

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

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  elseif value > maxValue then
    return maxValue
  end

  return value
end

local function selectedRoles(requestedRole)
  if requestedRole == "all" then
    return ROLE_ORDER
  end

  for _, role in ipairs(ROLE_ORDER) do
    if requestedRole == role then
      return { role }
    end
  end

  error("Unknown scalar role: " .. tostring(requestedRole), 0)
end

local function readGetter(object, method)
  if type(object[method]) ~= "function" then
    return {
      ok = false,
      error = "missing",
    }
  end

  local values = { pcall(object[method]) }
  local ok = table.remove(values, 1)

  if not ok then
    return {
      ok = false,
      error = tostring(values[1]),
    }
  end

  if #values == 1 then
    return {
      ok = true,
      value = copyPlain(values[1]),
    }
  end

  return {
    ok = true,
    value = copyPlain(values),
  }
end

local function wrapRole(router, scan, role)
  local mapped = scan.orientation
    and scan.orientation.roles
    and scan.orientation.roles.scalarActuator
    and scan.orientation.roles.scalarActuator[role]

  if not mapped or not mapped.coord then
    return nil, "No scalar actuator role mapping for " .. tostring(role)
  end

  local ok, objectOrError = pcall(router.wrap, mapped.coord.x, mapped.coord.y, mapped.coord.z)
  if not ok then
    return nil, "wrap error: " .. tostring(objectOrError)
  end

  if not objectOrError then
    return nil, "no peripheral at " .. coords.label(mapped.coord)
  end

  return {
    role = role,
    coord = copyPlain(mapped.coord),
    object = objectOrError,
  }
end

local function callSetter(device, method, ...)
  if type(device.object[method]) ~= "function" then
    return {
      ok = false,
      error = "missing " .. method,
    }
  end

  local values = { pcall(device.object[method], ...) }
  local ok = table.remove(values, 1)

  if not ok then
    return {
      ok = false,
      error = tostring(values[1]),
    }
  end

  return {
    ok = true,
    value = copyPlain(values),
  }
end

local function makeBaseReport(kind, config, scan, routerName)
  return {
    kind = kind,
    createdAt = now(),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    dryRun = config.dryRun ~= false,
    absoluteSignalMax = tonumber(config.absoluteSignalMax) or 10,
    scanPath = config.reportPath or "/aircraft_scan.txt",
    router = {
      name = routerName or (scan.router and scan.router.name),
    },
    orientation = copyPlain(scan.orientation),
    actions = {},
    errors = {},
  }
end

local function loadContext(config)
  local scan = loadScan(config.reportPath or "/aircraft_scan.txt")
  local router, routerName = findRouter()

  if not router then
    error("No peripheral_router with wrap(x, y, z) found", 0)
  end

  return scan, router, routerName
end

local function saveAndSend(config, report)
  local path = config.actuatorReportPath or "/aircraft_actuator_test.txt"

  reporting.save(report, path)
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  return path
end

local function collectScalarDevices(router, scan, roles, report)
  local devices = {}

  for _, role in ipairs(roles) do
    local device, errorMessage = wrapRole(router, scan, role)

    if device then
      table.insert(devices, device)
    else
      table.insert(report.errors, {
        role = role,
        error = errorMessage,
      })
    end
  end

  return devices
end

function actuatorTest.signal(config, options)
  local scan, router, routerName = loadContext(config)
  local maxSignal = tonumber(config.absoluteSignalMax) or 10
  local requestedSignal = tonumber(options.signal)

  if not requestedSignal then
    error("signal must be a number", 0)
  end

  local roles = selectedRoles(options.role)
  local clampedSignal = clamp(requestedSignal, 0, maxSignal)
  local report = makeBaseReport("aircraft_signal_test", config, scan, routerName)
  report.request = {
    role = options.role,
    signal = requestedSignal,
    clampedSignal = clampedSignal,
    apply = options.apply == true,
    seconds = options.seconds,
  }

  local active = options.apply == true and config.dryRun == false
  report.applied = active
  if options.apply == true and not active then
    report.blockedReason = "config.dryRun is true"
  end

  local devices = collectScalarDevices(router, scan, roles, report)

  for _, device in ipairs(devices) do
    local action = {
      role = device.role,
      coord = device.coord,
      method = "setSignal",
      requestedSignal = requestedSignal,
      signal = clampedSignal,
      before = {
        signal = readGetter(device.object, "getSignal"),
        outputSpeed = readGetter(device.object, "getOutputSpeed"),
        speed = readGetter(device.object, "getSpeed"),
      },
    }

    if active then
      action.setResult = callSetter(device, "setSignal", clampedSignal)
    else
      action.dryRun = true
    end

    table.insert(report.actions, action)
  end

  if active then
    sleep(tonumber(options.seconds) or 0.5)

    for index, device in ipairs(devices) do
      local action = report.actions[index]
      action.releaseResult = callSetter(device, "releaseSignal")
      action.after = {
        signal = readGetter(device.object, "getSignal"),
        outputSpeed = readGetter(device.object, "getOutputSpeed"),
        speed = readGetter(device.object, "getSpeed"),
      }
    end
  end

  local path = saveAndSend(config, report)
  print("Aircraft signal test report: " .. path)
  print("applied=" .. tostring(report.applied) .. " actions=" .. tostring(#report.actions))
  if report.blockedReason then
    print("blocked: " .. report.blockedReason)
  end

  return report
end

function actuatorTest.zero(config, options)
  local scan, router, routerName = loadContext(config)
  local roles = selectedRoles(options.role or "all")
  local report = makeBaseReport("aircraft_zero_test", config, scan, routerName)
  report.request = {
    role = options.role or "all",
    apply = options.apply == true,
  }

  local active = options.apply == true and config.dryRun == false
  report.applied = active
  if options.apply == true and not active then
    report.blockedReason = "config.dryRun is true"
  end

  local devices = collectScalarDevices(router, scan, roles, report)

  for _, device in ipairs(devices) do
    local action = {
      role = device.role,
      coord = device.coord,
      method = "releaseSignal",
      before = {
        signal = readGetter(device.object, "getSignal"),
        outputSpeed = readGetter(device.object, "getOutputSpeed"),
        speed = readGetter(device.object, "getSpeed"),
      },
    }

    if active then
      action.releaseResult = callSetter(device, "releaseSignal")
      action.after = {
        signal = readGetter(device.object, "getSignal"),
        outputSpeed = readGetter(device.object, "getOutputSpeed"),
        speed = readGetter(device.object, "getSpeed"),
      }
    else
      action.dryRun = true
    end

    table.insert(report.actions, action)
  end

  local path = saveAndSend(config, report)
  print("Aircraft zero test report: " .. path)
  print("applied=" .. tostring(report.applied) .. " actions=" .. tostring(#report.actions))
  if report.blockedReason then
    print("blocked: " .. report.blockedReason)
  end

  return report
end

return actuatorTest
