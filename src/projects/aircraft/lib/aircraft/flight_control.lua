local coords = require("lib.aircraft.coords")
local hud = require("lib.aircraft.hud")
local reporting = require("lib.aircraft.reporting")

local flightControl = {}
local CONTROLLER_VERSION = "clock-stop-v2"

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

local function atan2(y, x)
  if math.atan2 then
    return math.atan2(y, x)
  end

  if x > 0 then
    return math.atan(y / x)
  elseif x < 0 and y >= 0 then
    return math.atan(y / x) + math.pi
  elseif x < 0 and y < 0 then
    return math.atan(y / x) - math.pi
  elseif x == 0 and y > 0 then
    return math.pi / 2
  elseif x == 0 and y < 0 then
    return -math.pi / 2
  end

  return 0
end

local function wrapRadians(delta)
  local tau = math.pi * 2

  while delta > math.pi do
    delta = delta - tau
  end

  while delta < -math.pi do
    delta = delta + tau
  end

  return delta
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

local function callGetter(object, method)
  if type(object[method]) ~= "function" then
    return nil, "missing " .. method
  end

  local values = { pcall(object[method]) }
  local ok = table.remove(values, 1)
  if not ok then
    return nil, tostring(values[1])
  end

  if #values == 1 and type(values[1]) == "table" then
    return copyPlain(values[1]), nil
  end

  return copyPlain(values), nil
end

local function callSetter(object, method, ...)
  if type(object[method]) ~= "function" then
    return {
      ok = false,
      error = "missing " .. method,
    }
  end

  local values = { pcall(object[method], ...) }
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

local function loadContext(config)
  local scan = loadScan(config.reportPath or "/aircraft_scan.txt")
  local router, routerName = findRouter()

  if not router then
    error("No peripheral_router with wrap(x, y, z) found", 0)
  end

  return scan, router, routerName
end

local function wrapCoord(router, coord, label)
  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok then
    error(label .. " wrap error at " .. coords.label(coord) .. ": " .. tostring(objectOrError), 0)
  end

  if not objectOrError then
    error(label .. " missing at " .. coords.label(coord), 0)
  end

  return objectOrError
end

local function findGimbal(scan, router)
  local hints = scan.orientation and scan.orientation.sideHints or {}

  for side, hint in pairs(hints) do
    if not hint.ambiguous and hint.coord then
      local object = wrapCoord(router, hint.coord, "gimbal " .. tostring(side))
      if type(object.getGravity) == "function" and type(object.getAngularRates) == "function" then
        return {
          side = side,
          coord = copyPlain(hint.coord),
          object = object,
        }
      end
    end
  end

  error("No gimbal-like side sensor found in scan. Run aircraft scan first.", 0)
end

local function wrapScalarDevices(scan, router)
  local mapped = scan.orientation
    and scan.orientation.roles
    and scan.orientation.roles.scalarActuator

  if not mapped then
    error("No scalar actuator role map in scan. Run aircraft scan first.", 0)
  end

  local devices = {}
  for _, role in ipairs(ROLE_ORDER) do
    local entry = mapped[role]
    if not entry or not entry.coord then
      error("Missing scalar role " .. role .. " in scan", 0)
    end

    devices[role] = {
      role = role,
      coord = copyPlain(entry.coord),
      object = wrapCoord(router, entry.coord, role),
    }
  end

  return devices
end

local function saveAndSend(config, report)
  local path = config.stabilizeReportPath or "/aircraft_stabilize.txt"

  reporting.save(report, path)
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  return path
end

local function baseReport(kind, config, scan, routerName)
  return {
    kind = kind,
    createdAt = now(),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    dryRun = config.dryRun ~= false,
    controllerVersion = CONTROLLER_VERSION,
    scanPath = config.reportPath or "/aircraft_scan.txt",
    router = {
      name = routerName or (scan.router and scan.router.name),
    },
    orientation = copyPlain(scan.orientation),
  }
end

local function readGimbal(gimbal)
  local rates, rateError = callGetter(gimbal.object, "getAngularRates")
  local gravity, gravityError = callGetter(gimbal.object, "getGravity")

  if rateError then
    error("gimbal getAngularRates failed: " .. tostring(rateError), 0)
  end

  if gravityError then
    error("gimbal getGravity failed: " .. tostring(gravityError), 0)
  end

  return {
    angularRates = rates,
    gravity = gravity,
  }
end

local function numberAt(values, index)
  local value = values and values[index]
  if type(value) ~= "number" then
    return 0
  end

  return value
end

local function gravityTilt(gravity)
  local gx = numberAt(gravity, 1)
  local gy = numberAt(gravity, 2)
  local gz = numberAt(gravity, 3)
  local down = -gy

  return {
    axis1 = atan2(gx, down),
    axis2 = atan2(gz, down),
    x = gx,
    y = gy,
    z = gz,
  }
end

local function stabilizeConfig(config, options)
  local defaults = config.stabilize or {}

  return {
    seconds = tonumber(options.seconds) or tonumber(defaults.seconds) or 1,
    interval = tonumber(options.interval) or tonumber(defaults.interval) or 0.1,
    basePower = tonumber(options.basePower) or tonumber(defaults.basePower) or 0,
    maxSignal = tonumber(config.absoluteSignalMax) or 15,
    brakeSignal = tonumber(config.brakeSignal) or tonumber(config.absoluteSignalMax) or 15,
    axis1Kp = tonumber(options.axis1Kp) or tonumber(options.kp) or tonumber(defaults.axis1Kp) or 4,
    axis2Kp = tonumber(options.axis2Kp) or tonumber(options.kp) or tonumber(defaults.axis2Kp) or 4,
    axis1Kd = tonumber(options.axis1Kd) or tonumber(options.kd) or tonumber(defaults.axis1Kd) or 0.12,
    axis2Kd = tonumber(options.axis2Kd) or tonumber(options.kd) or tonumber(defaults.axis2Kd) or 0.2,
    axis1Sign = tonumber(options.axis1Sign) or tonumber(defaults.axis1Sign) or -1,
    axis2Sign = tonumber(options.axis2Sign) or tonumber(defaults.axis2Sign) or 1,
    maxCorrection = tonumber(options.maxCorrection) or tonumber(defaults.maxCorrection) or 1.5,
    maxAttitudeDelta = tonumber(options.maxAttitudeDelta) or tonumber(defaults.maxAttitudeDelta)
      or tonumber(config.maxAttitudeDelta)
      or 2,
    brakeOnExit = defaults.brakeOnExit ~= false,
  }
end

local function mixerSignals(settings, state, level)
  local rawRate1 = numberAt(state.angularRates, 1)
  local rawRate2 = numberAt(state.angularRates, 2)
  local currentTilt = gravityTilt(state.gravity)
  local neutralTilt = gravityTilt(level.gravity)
  local rawError1 = currentTilt.axis1 - neutralTilt.axis1
  local rawError2 = currentTilt.axis2 - neutralTilt.axis2

  local error1 = wrapRadians(rawError1) * settings.axis1Sign
  local error2 = wrapRadians(rawError2) * settings.axis2Sign
  local rate1 = rawRate1 * settings.axis1Sign
  local rate2 = rawRate2 * settings.axis2Sign
  local rawCorrection1 = -(settings.axis1Kp * error1 + settings.axis1Kd * rate1)
  local rawCorrection2 = -(settings.axis2Kp * error2 + settings.axis2Kd * rate2)
  local correction1 = clamp(rawCorrection1, -settings.maxCorrection, settings.maxCorrection)
  local correction2 = clamp(rawCorrection2, -settings.maxCorrection, settings.maxCorrection)
  local power = {
    front_left = settings.basePower + correction1 - correction2,
    front_right = settings.basePower - correction1 - correction2,
    rear_left = settings.basePower + correction1 + correction2,
    rear_right = settings.basePower - correction1 + correction2,
  }
  local signals = {}

  for role, value in pairs(power) do
    local clampedPower = clamp(value, 0, settings.maxSignal)
    signals[role] = quantizeSignal(settings.brakeSignal - clampedPower, settings.maxSignal)
  end

  return {
    angle1 = currentTilt.axis1,
    angle2 = currentTilt.axis2,
    rate1 = rate1,
    rate2 = rate2,
    rawRate1 = rawRate1,
    rawRate2 = rawRate2,
    neutral1 = neutralTilt.axis1,
    neutral2 = neutralTilt.axis2,
    currentTilt = currentTilt,
    neutralTilt = neutralTilt,
    rawError1 = rawError1,
    rawError2 = rawError2,
    error1 = error1,
    error2 = error2,
    rawCorrection1 = rawCorrection1,
    rawCorrection2 = rawCorrection2,
    correction1 = correction1,
    correction2 = correction2,
    correctionLimited = correction1 ~= rawCorrection1 or correction2 ~= rawCorrection2,
    power = power,
    signals = signals,
  }
end

local function applySignals(devices, signals)
  local results = {}
  local tasks = {}

  for _, role in ipairs(ROLE_ORDER) do
    local roleName = role
    table.insert(tasks, function()
      results[roleName] = callSetter(devices[roleName].object, "setSignal", signals[roleName])
    end)
  end

  parallel.waitForAll(unpack(tasks))

  return results
end

local function brakeDevices(devices, signal)
  local results = {}
  local tasks = {}

  for _, role in ipairs(ROLE_ORDER) do
    local roleName = role
    table.insert(tasks, function()
      results[roleName] = callSetter(devices[roleName].object, "setSignal", signal)
    end)
  end

  parallel.waitForAll(unpack(tasks))

  return results
end

function flightControl.levelSet(config)
  local scan, router, routerName = loadContext(config)
  local gimbal = findGimbal(scan, router)
  local state = readGimbal(gimbal)
  local report = baseReport("aircraft_level_set", config, scan, routerName)

  report.gimbal = {
    side = gimbal.side,
    coord = gimbal.coord,
  }
  report.state = state
  report.level = {
    gravity = copyPlain(state.gravity),
    gravityTilt = gravityTilt(state.gravity),
    mode = "sampled_gravity",
    createdAt = report.createdAt,
  }

  local path = saveAndSend(config, report)
  print("Aircraft level report: " .. path)
  print("level gravity=" .. textutils.serialize(report.level.gravity))

  return report
end

function flightControl.levelZero(config)
  local gravity = { 0, -1, 0 }
  local createdAt = now()
  local report = {
    kind = "aircraft_level_zero",
    createdAt = createdAt,
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    dryRun = config.dryRun ~= false,
    level = {
      gravity = copyPlain(gravity),
      gravityTilt = gravityTilt(gravity),
      mode = "world_zero",
      createdAt = createdAt,
    },
  }

  local path = saveAndSend(config, report)
  print("Aircraft world-level report: " .. path)
  print("level gravity=" .. textutils.serialize(report.level.gravity))

  return report
end

function flightControl.stabilize(config, options)
  if type(config.level) ~= "table" or type(config.level.gravity) ~= "table" then
    error("No saved level. Run aircraft level-zero for world-level or level-set while the craft is level.", 0)
  end

  local scan, router, routerName = loadContext(config)
  local gimbal = findGimbal(scan, router)
  local devices = wrapScalarDevices(scan, router)
  local settings = stabilizeConfig(config, options)

  local active = options.apply == true and config.dryRun == false
  local hudContext = hud.open(config, options)
  local report = baseReport("aircraft_stabilize", config, scan, routerName)

  report.applied = active
  report.request = {
    apply = options.apply == true,
    seconds = settings.seconds,
    interval = settings.interval,
    basePower = settings.basePower,
  }
  report.settings = copyPlain(settings)
  report.level = copyPlain(config.level)
  report.gimbal = {
    side = gimbal.side,
    coord = gimbal.coord,
  }
  report.hud = hud.describe(hudContext)
  report.frames = {}
  report.timing = {
    requestedSeconds = settings.seconds,
    interval = settings.interval,
    mode = "os_clock",
  }

  if options.apply == true and not active then
    report.blockedReason = "config.dryRun is true"
  end

  local function runLoop()
    local startTime = os.clock()
    local deadline = startTime + settings.seconds
    local frameIndex = 1

    while true do
      if active and frameIndex > 1 and os.clock() >= deadline then
        report.timing.stopReason = "duration_clock"
        break
      end

      local state = readGimbal(gimbal)
      local mixed = mixerSignals(settings, state, config.level)
      local frame = {
        index = frameIndex,
        elapsed = os.clock() - startTime,
        state = state,
        mixed = mixed,
      }
      local attitudeExceeded = math.abs(mixed.error1) > settings.maxAttitudeDelta
        or math.abs(mixed.error2) > settings.maxAttitudeDelta

      if attitudeExceeded then
        frame.aborted = true
        frame.abortReason = "attitude error exceeded maxAttitudeDelta"
        report.aborted = true
        report.abortReason = frame.abortReason
      elseif active then
        frame.setResults = applySignals(devices, mixed.signals)
      else
        frame.dryRun = true
      end

      frame.hud = hud.update(hudContext, frame, settings, active, attitudeExceeded)
      table.insert(report.frames, frame)

      if attitudeExceeded then
        break
      end

      if not active then
        break
      end

      local remaining = deadline - os.clock()
      if remaining <= 0 then
        report.timing.stopReason = "duration_clock"
        break
      end

      sleep(math.min(settings.interval, remaining))
      frameIndex = frameIndex + 1
    end

    report.timing.elapsed = os.clock() - startTime
    if not report.timing.stopReason then
      report.timing.stopReason = report.abortReason or "loop_complete"
    end
  end

  local ok, result = pcall(runLoop)
  if active and settings.brakeOnExit then
    report.brakeOnExit = brakeDevices(devices, settings.brakeSignal)
  end

  if not ok then
    report.error = tostring(result)
  end

  local path = saveAndSend(config, report)
  print("Aircraft stabilize report: " .. path)
  print("applied=" .. tostring(report.applied) .. " frames=" .. tostring(#report.frames))
  if report.blockedReason then
    print("blocked: " .. report.blockedReason)
  end
  if report.error then
    error(report.error, 0)
  end

  return report
end

return flightControl
