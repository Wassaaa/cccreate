local coords = require("lib.aircraft.coords")
local actuators = require("lib.aircraft.actuators")
local displays = require("lib.aircraft.displays")
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

local function quantizeSignal(value, maxSignal)
  return clamp(math.floor((tonumber(value) or 0) + 0.5), 0, maxSignal)
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

  error("Unknown actuator role: " .. tostring(requestedRole), 0)
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

local function readScalarState(device)
  return {
    signal = readGetter(device.object, "getSignal"),
    outputSpeed = readGetter(device.object, "getOutputSpeed"),
    speed = readGetter(device.object, "getSpeed"),
  }
end

local function readNumber(read)
  if type(read) == "table" and read.ok and type(read.value) == "number" then
    return read.value
  end

  return nil
end

local function actionSignals(actions, fallback)
  local signals = {}

  for _, action in ipairs(actions or {}) do
    local signal = fallback

    if action.after then
      signal = readNumber(action.after.signal) or signal
    elseif action.during then
      signal = readNumber(action.during.signal) or signal
    end

    if action.role and signal ~= nil then
      signals[action.role] = signal
    end
  end

  return signals
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
    absoluteSignalMax = tonumber(config.absoluteSignalMax) or 15,
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
  local path = "/aircraft_actuator_test.txt"

  reporting.save(report, path, config, { localReport = false })
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  return config.sendWebhook ~= false and "webhook" or "webhook disabled"
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
  local maxSignal = tonumber(config.absoluteSignalMax) or 15
  local requestedSignal = tonumber(options.signal)

  if not requestedSignal then
    error("signal must be a number", 0)
  end

  local roles = selectedRoles(options.role)
  local clampedSignal = quantizeSignal(requestedSignal, maxSignal)
  local restoreSignal = quantizeSignal(tonumber(options.afterSignal) or tonumber(config.brakeSignal) or maxSignal, maxSignal)
  local report = makeBaseReport("aircraft_signal_test", config, scan, routerName)
  report.request = {
    role = options.role,
    signal = requestedSignal,
    clampedSignal = clampedSignal,
    afterSignal = restoreSignal,
    apply = options.apply == true,
    seconds = options.seconds,
  }

  local active = options.apply == true and config.dryRun == false
  report.applied = active
  if options.apply == true and not active then
    report.blockedReason = "config.dryRun is true"
  end
  local displayContext = displays.collect(config, router, scan, options)
  report.displays = displays.describe(displayContext)

  local devices = collectScalarDevices(router, scan, roles, report)
  local setTasks = {}

  for _, device in ipairs(devices) do
    local action = {
      role = device.role,
      coord = device.coord,
      method = "setSignal",
      requestedSignal = requestedSignal,
      signal = clampedSignal,
      before = readScalarState(device),
    }

    if active then
      local actionRef = action
      local deviceRef = device
      table.insert(setTasks, function()
        actionRef.setResult = callSetter(deviceRef, "setSignal", clampedSignal)
      end)
    else
      action.dryRun = true
    end

    table.insert(report.actions, action)
  end

  if active then
    if #setTasks > 0 then
      parallel.waitForAll(unpack(setTasks))
    end

    report.displayDuring = displays.updateSignals(displayContext, actionSignals(report.actions, clampedSignal))

    local seconds = tonumber(options.seconds) or 0.5
    local sampleDelay = math.min(0.1, math.max(0, seconds))

    if sampleDelay > 0 then
      sleep(sampleDelay)
    end

    for index, device in ipairs(devices) do
      report.actions[index].during = readScalarState(device)
    end

    local remaining = seconds - sampleDelay
    if remaining > 0 then
      sleep(remaining)
    end

    local restoreTasks = {}
    for index, device in ipairs(devices) do
      local action = report.actions[index]
      action.restoreMethod = "setSignal"
      action.restoreSignal = restoreSignal
      local actionRef = action
      local deviceRef = device
      table.insert(restoreTasks, function()
        actionRef.restoreResult = callSetter(deviceRef, "setSignal", restoreSignal)
      end)
    end

    if #restoreTasks > 0 then
      parallel.waitForAll(unpack(restoreTasks))
    end

    for index, device in ipairs(devices) do
      local action = report.actions[index]
      action.after = readScalarState(device)
    end

    report.displayAfter = displays.updateSignals(displayContext, actionSignals(report.actions, restoreSignal))
  end

  local path = saveAndSend(config, report)
  print("Aircraft signal test report: " .. path)
  print("applied=" .. tostring(report.applied) .. " actions=" .. tostring(#report.actions))
  if report.blockedReason then
    print("blocked: " .. report.blockedReason)
  end

  return report
end

function actuatorTest.brake(config, options)
  local scan, router, routerName = loadContext(config)
  local roles = selectedRoles(options.role or "all")
  local actuatorSettings = actuators.settings(config, options)
  local actuatorContext = actuators.open(scan, router, actuatorSettings)
  local outputs = actuators.brakeOutputs(actuatorSettings, roles)
  local report = makeBaseReport("aircraft_brake", config, scan, routerName)
  report.request = {
    role = options.role or "all",
    outputLabel = actuatorSettings.outputLabel,
    outputs = copyPlain(outputs),
    apply = options.apply == true,
  }

  local active = options.apply == true and config.dryRun == false
  report.applied = active
  if options.apply == true and not active then
    report.blockedReason = "config.dryRun is true"
  end
  local displayContext = displays.collect(config, router, scan, options)
  report.displays = displays.describe(displayContext)
  report.actuators = actuators.describe(actuatorContext)

  local devices = {}
  for _, role in ipairs(roles) do
    local device = actuatorContext.devices[role]
    if device then
      table.insert(devices, device)
    end
  end

  for _, device in ipairs(devices) do
    local action = {
      role = device.role,
      coord = device.coord,
      method = device.setter,
      output = outputs[device.role],
      before = actuators.readDevice(device),
    }

    if not active then
      action.dryRun = true
    end

    table.insert(report.actions, action)
  end

  for _, role in ipairs(roles) do
    if not actuatorContext.devices[role] then
      table.insert(report.errors, {
        role = role,
        error = actuatorContext.errors and actuatorContext.errors[role] or "missing actuator",
      })
    end
  end

  if active then
    report.setResults = actuators.apply(actuatorContext, outputs)

    for _, action in ipairs(report.actions) do
      local device = actuatorContext.devices[action.role]
      if device then
        action.after = actuators.readDevice(device)
      end
    end

    report.displayAfter = displays.updateSignals(displayContext, outputs)
  end

  local path = saveAndSend(config, report)
  print("Aircraft brake report: " .. path)
  print("applied=" .. tostring(report.applied) .. " actions=" .. tostring(#report.actions))
  if report.blockedReason then
    print("blocked: " .. report.blockedReason)
  end

  return report
end

return actuatorTest
