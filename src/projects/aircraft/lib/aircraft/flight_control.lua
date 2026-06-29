local coords = require("lib.aircraft.coords")
local controller = require("lib.aircraft.controller")
local displays = require("lib.aircraft.displays")
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

local function quantizeSignal(value, maxSignal, residuals, key)
  local clamped = clamp(tonumber(value) or 0, 0, maxSignal)
  local adjusted = clamped

  if residuals and key then
    adjusted = adjusted + (tonumber(residuals[key]) or 0)
  end

  local signal = clamp(math.floor(adjusted + 0.5), 0, maxSignal)

  if residuals and key then
    residuals[key] = adjusted - signal
  end

  return signal
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

local function hasCategory(entry, category)
  for _, value in ipairs(entry and entry.categories or {}) do
    if value == category then
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

local function readOptionalGetter(object, method)
  if type(object[method]) ~= "function" then
    return nil
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

local function tryGimbalAt(router, coord)
  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok or not objectOrError then
    return nil
  end

  if type(objectOrError.getGravity) == "function"
      and type(objectOrError.getAnglesRad) == "function"
      and type(objectOrError.getAngularRatesRad) == "function" then
    return objectOrError
  end

  return nil
end

local function findGimbal(scan, router)
  local hints = scan.orientation and scan.orientation.sideHints or {}

  for side, hint in pairs(hints) do
    if not hint.ambiguous and hint.coord then
      local object = tryGimbalAt(router, hint.coord)
      if object then
        return {
          side = side,
          source = "side_hint",
          coord = copyPlain(hint.coord),
          object = object,
        }
      end
    end
  end

  for _, entry in ipairs(scan.peripherals or {}) do
    if entry.coord and hasCategory(entry, "attitudeSensor") then
      local object = tryGimbalAt(router, entry.coord)
      if object then
        return {
          side = nil,
          source = "scan_attitude_sensor",
          coord = copyPlain(entry.coord),
          object = object,
        }
      end
    end
  end

  error("No gimbal-like attitude sensor found in scan. Run aircraft scan first.", 0)
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

local function wrapOptionalRoleDevices(scan, router, family)
  local mapped = scan.orientation
    and scan.orientation.roles
    and scan.orientation.roles[family]
  local devices = {}
  local errors = {}

  if not mapped then
    return devices, errors
  end

  for _, role in ipairs(ROLE_ORDER) do
    local entry = mapped[role]

    if entry and entry.coord then
      local ok, objectOrError = pcall(router.wrap, entry.coord.x, entry.coord.y, entry.coord.z)
      if ok and objectOrError then
        devices[role] = {
          role = role,
          coord = copyPlain(entry.coord),
          object = objectOrError,
        }
      elseif ok then
        errors[role] = "missing at " .. coords.label(entry.coord)
      else
        errors[role] = "wrap error at " .. coords.label(entry.coord) .. ": " .. tostring(objectOrError)
      end
    end
  end

  return devices, errors
end

local function saveAndSend(config, report)
  local path = config.stabilizeReportPath or "/aircraft_stabilize.txt"

  reporting.save(report, path, config)
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
  local rates = nil
  local rateError = nil
  local gravity = nil
  local gravityError = nil
  local anglesRad = nil
  local anglesRadRead = nil

  parallel.waitForAll(
    function()
      rates, rateError = callGetter(gimbal.object, "getAngularRatesRad")
    end,
    function()
      gravity, gravityError = callGetter(gimbal.object, "getGravity")
    end,
    function()
      anglesRadRead = readOptionalGetter(gimbal.object, "getAnglesRad")
      if anglesRadRead and anglesRadRead.ok then
        anglesRad = anglesRadRead.value
      end
    end
  )

  if rateError then
    error("gimbal getAngularRatesRad failed: " .. tostring(rateError), 0)
  end

  if gravityError then
    error("gimbal getGravity failed: " .. tostring(gravityError), 0)
  end

  return {
    angularRates = rates,
    gravity = gravity,
    anglesRad = anglesRad,
    anglesRadRead = anglesRadRead,
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

local function directTilt(anglesRad)
  if type(anglesRad) ~= "table" then
    return nil
  end

  local pitch = numberAt(anglesRad, 1)
  local roll = numberAt(anglesRad, 2)

  return {
    axis1 = roll,
    axis2 = pitch,
    pitch = pitch,
    roll = roll,
  }
end

local function stabilizeConfig(config, options)
  local defaults = config.stabilize or {}
  local display = config.display or {}
  local killSwitch = config.killSwitch or {}
  local nixiesEnabled = display.stabilizeEnabled == true
  local killSwitchEnabled = killSwitch.enabled == true

  if options.nixies ~= nil then
    nixiesEnabled = options.nixies == true
  end
  if options.killSwitch ~= nil then
    killSwitchEnabled = options.killSwitch == true
  end

  return {
    forever = options.forever == true,
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
    axis1RateSign = tonumber(options.axis1RateSign) or tonumber(defaults.axis1RateSign) or -1,
    axis2RateSign = tonumber(options.axis2RateSign) or tonumber(defaults.axis2RateSign) or -1,
    rateSource = tostring(defaults.rateSource or "gimbal_angular_rate"),
    axis1Trim = tonumber(options.axis1Trim) or tonumber(defaults.axis1Trim) or 0,
    axis2Trim = tonumber(options.axis2Trim) or tonumber(defaults.axis2Trim) or 0,
    maxCorrection = tonumber(options.maxCorrection) or tonumber(defaults.maxCorrection) or 1.5,
    signalDither = defaults.signalDither ~= false,
    maxAttitudeDelta = tonumber(options.maxAttitudeDelta)
      or (tonumber(options.maxAttitudeDeg) and tonumber(options.maxAttitudeDeg) * math.pi / 180)
      or tonumber(defaults.maxAttitudeDelta)
      or tonumber(config.maxAttitudeDelta)
      or 2,
    brakeOnExit = defaults.brakeOnExit ~= false,
    reportFrameLimit = tonumber(options.reportFrameLimit) or tonumber(defaults.reportFrameLimit) or 600,
    killSwitch = {
      enabled = killSwitchEnabled,
      side = tostring(killSwitch.side or "front"),
      activeHigh = killSwitch.activeHigh ~= false,
    },
    nixiesEnabled = nixiesEnabled,
    nixieInterval = tonumber(options.nixieInterval) or tonumber(display.stabilizeInterval) or 1,
  }
end

local function readKillSwitch(settings)
  local killSwitch = settings.killSwitch or {}
  if not killSwitch.enabled then
    return {
      enabled = false,
      triggered = false,
    }
  end

  local side = tostring(killSwitch.side or "front")
  if type(redstone) ~= "table" or type(redstone.getInput) ~= "function" then
    return {
      enabled = true,
      side = side,
      activeHigh = killSwitch.activeHigh ~= false,
      ok = false,
      input = nil,
      triggered = true,
      error = "redstone.getInput unavailable",
    }
  end

  local ok, inputOrError = pcall(redstone.getInput, side)
  if not ok then
    return {
      enabled = true,
      side = side,
      activeHigh = killSwitch.activeHigh ~= false,
      ok = false,
      input = nil,
      triggered = true,
      error = tostring(inputOrError),
    }
  end

  local input = inputOrError == true
  local activeHigh = killSwitch.activeHigh ~= false
  local triggered = input == activeHigh

  return {
    enabled = true,
    side = side,
    activeHigh = activeHigh,
    ok = true,
    input = input,
    triggered = triggered,
  }
end

local function slewValue(current, target, maxDelta)
  current = tonumber(current) or 0
  target = tonumber(target) or 0

  if not maxDelta or maxDelta <= 0 then
    return target
  end

  return current + clamp(target - current, -maxDelta, maxDelta)
end

local function smoothControl(context, control, previousControl, dt)
  if not control or control.enabled ~= true then
    return control
  end

  local settings = context and context.settings or {}
  local result = copyPlain(control)
  local elapsed = tonumber(dt) or 0
  local targetSlew = tonumber(settings.targetSlewDegPerSecond) or 0
  local throttleSlew = tonumber(settings.throttleSlewPowerPerSecond) or 0

  result.rawAxis1Target = tonumber(control.axis1Target) or 0
  result.rawAxis2Target = tonumber(control.axis2Target) or 0
  result.rawThrottlePower = tonumber(control.throttlePower) or 0

  if elapsed > 0 and previousControl then
    local targetStep = targetSlew * math.pi / 180 * elapsed
    local throttleStep = throttleSlew * elapsed

    result.axis1Target = slewValue(previousControl.axis1Target, result.rawAxis1Target, targetStep)
    result.axis2Target = slewValue(previousControl.axis2Target, result.rawAxis2Target, targetStep)
    result.throttlePower = slewValue(previousControl.throttlePower, result.rawThrottlePower, throttleStep)
  end

  return result
end

local function recoveryControl(test, elapsed)
  if type(test) ~= "table" then
    return nil
  end

  local pulseSeconds = tonumber(test.pulseSeconds) or 1
  local active = elapsed < pulseSeconds

  return {
    enabled = true,
    synthetic = true,
    pulseActive = active,
    pulseSeconds = pulseSeconds,
    axis1 = active and (tonumber(test.axis1) or 0) or 0,
    axis2 = active and (tonumber(test.axis2) or 0) or 0,
    throttle = active and (tonumber(test.throttle) or 0) or 0,
    throttlePower = active and (tonumber(test.throttlePower) or 0) or 0,
    axis1Target = active and (tonumber(test.axis1Target) or 0) or 0,
    axis2Target = active and (tonumber(test.axis2Target) or 0) or 0,
    axis1Power = active and (tonumber(test.axis1Power) or 0) or 0,
    axis2Power = active and (tonumber(test.axis2Power) or 0) or 0,
    reads = {},
  }
end

local function recoveryContext(test)
  return {
    enabled = true,
    settings = {
      targetSlewDegPerSecond = tonumber(test and test.targetSlewDegPerSecond) or 30,
      throttleSlewPowerPerSecond = tonumber(test and test.throttleSlewPowerPerSecond) or 8,
    },
  }
end

local function targetAssistPower(controlPower, error, target)
  controlPower = tonumber(controlPower) or 0
  error = tonumber(error) or 0
  target = tonumber(target) or 0

  if math.abs(target) < 0.0001 then
    return controlPower
  end

  if controlPower * error >= 0 then
    return 0
  end

  local scale = clamp(math.abs(error) / math.abs(target), 0, 1)
  return controlPower * scale
end

local function mixerSignals(settings, state, level, control, previousMotion, dt, signalResiduals)
  control = control or {}

  local rawRate1 = numberAt(state.angularRates, 3)
  local rawRate2 = numberAt(state.angularRates, 1)
  local currentTilt = gravityTilt(state.gravity)
  local neutralTilt = gravityTilt(level.gravity)
  local currentDirectTilt = directTilt(state.anglesRad)
  local neutralDirectTilt = directTilt(level.anglesRad) or {
    axis1 = 0,
    axis2 = 0,
    pitch = 0,
    roll = 0,
  }
  local rawError1 = currentTilt.axis1 - neutralTilt.axis1
  local rawError2 = currentTilt.axis2 - neutralTilt.axis2
  local measured1 = wrapRadians(rawError1) * settings.axis1Sign
  local measured2 = wrapRadians(rawError2) * settings.axis2Sign
  local directError1 = nil
  local directError2 = nil
  local directMeasured1 = nil
  local directMeasured2 = nil
  local directDiff1 = nil
  local directDiff2 = nil

  if currentDirectTilt then
    directError1 = wrapRadians(currentDirectTilt.axis1 - neutralDirectTilt.axis1)
    directError2 = wrapRadians(currentDirectTilt.axis2 - neutralDirectTilt.axis2)
    directMeasured1 = directError1 * settings.axis1Sign
    directMeasured2 = directError2 * settings.axis2Sign
    directDiff1 = wrapRadians(directError1 - rawError1)
    directDiff2 = wrapRadians(directError2 - rawError2)
  end

  local target1 = tonumber(control.axis1Target) or 0
  local target2 = tonumber(control.axis2Target) or 0
  local rawControlPower1 = tonumber(control.axis1Power) or 0
  local rawControlPower2 = tonumber(control.axis2Power) or 0
  local error1 = measured1 - target1
  local error2 = measured2 - target2
  local controlPower1 = targetAssistPower(rawControlPower1, error1, target1)
  local controlPower2 = targetAssistPower(rawControlPower2, error2, target2)
  local rate1 = 0
  local rate2 = 0

  if settings.rateSource == "gimbal_angular_rate" then
    rate1 = rawRate1
    rate2 = rawRate2
  elseif previousMotion and dt and dt > 0 then
    rate1 = wrapRadians(measured1 - previousMotion.measured1) / dt
    rate2 = wrapRadians(measured2 - previousMotion.measured2) / dt
  end

  local rawCorrection1 = -(settings.axis1Kp * error1 + settings.axis1Kd * rate1) + settings.axis1Trim + controlPower1
  local rawCorrection2 = -(settings.axis2Kp * error2 + settings.axis2Kd * rate2) + settings.axis2Trim + controlPower2
  local correction1 = clamp(rawCorrection1, -settings.maxCorrection, settings.maxCorrection)
  local correction2 = clamp(rawCorrection2, -settings.maxCorrection, settings.maxCorrection)
  local basePower = settings.basePower + (tonumber(control.throttlePower) or 0)
  local power = {
    front_left = basePower + correction1 - correction2,
    front_right = basePower - correction1 - correction2,
    rear_left = basePower + correction1 + correction2,
    rear_right = basePower - correction1 + correction2,
  }
  local signals = {}
  local desiredSignals = {}

  for role, value in pairs(power) do
    local clampedPower = clamp(value, 0, settings.maxSignal)
    desiredSignals[role] = clamp(settings.brakeSignal - clampedPower, 0, settings.maxSignal)
    signals[role] = quantizeSignal(
      desiredSignals[role],
      settings.maxSignal,
      settings.signalDither and signalResiduals or nil,
      role
    )
  end

  return {
    angle1 = currentTilt.axis1,
    angle2 = currentTilt.axis2,
    rate1 = rate1,
    rate2 = rate2,
    rateSource = settings.rateSource,
    rawRate1 = rawRate1,
    rawRate2 = rawRate2,
    neutral1 = neutralTilt.axis1,
    neutral2 = neutralTilt.axis2,
    currentTilt = currentTilt,
    neutralTilt = neutralTilt,
    directAngle1 = currentDirectTilt and currentDirectTilt.axis1,
    directAngle2 = currentDirectTilt and currentDirectTilt.axis2,
    directPitch = currentDirectTilt and currentDirectTilt.pitch,
    directRoll = currentDirectTilt and currentDirectTilt.roll,
    directError1 = directError1,
    directError2 = directError2,
    directMeasured1 = directMeasured1,
    directMeasured2 = directMeasured2,
    directDiff1 = directDiff1,
    directDiff2 = directDiff2,
    rawError1 = rawError1,
    rawError2 = rawError2,
    measured1 = measured1,
    measured2 = measured2,
    target1 = target1,
    target2 = target2,
    rawControlPower1 = rawControlPower1,
    rawControlPower2 = rawControlPower2,
    controlPower1 = controlPower1,
    controlPower2 = controlPower2,
    error1 = error1,
    error2 = error2,
    rawCorrection1 = rawCorrection1,
    rawCorrection2 = rawCorrection2,
    trim1 = settings.axis1Trim,
    trim2 = settings.axis2Trim,
    correction1 = correction1,
    correction2 = correction2,
    correctionLimited = correction1 ~= rawCorrection1 or correction2 ~= rawCorrection2,
    basePower = basePower,
    control = copyPlain(control),
    power = power,
    desiredSignals = desiredSignals,
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

local function readRotorTelemetry(rotorDevices)
  local result = {
    roles = {},
  }

  for _, role in ipairs(ROLE_ORDER) do
    local roleTelemetry = {}
    local rotor = rotorDevices and rotorDevices[role]

    if rotor then
      roleTelemetry.rotorThrust = readOptionalGetter(rotor.object, "getThrust")
    end

    result.roles[role] = roleTelemetry
  end

  return result
end

local function pressedControls(control)
  local pressed = {}

  for _, name in ipairs({ "shift", "space", "w", "a", "s", "d" }) do
    local read = control and control.reads and control.reads[name]
    if read and read.pressed then
      table.insert(pressed, name)
    end
  end

  return pressed
end

local function compactControllerFrame(control)
  if not control then
    return nil
  end

  return {
    enabled = control.enabled == true,
    synthetic = control.synthetic == true,
    pulseActive = control.pulseActive == true,
    pulseSeconds = control.pulseSeconds,
    throttle = control.throttle,
    throttlePower = control.throttlePower,
    axis1 = control.axis1,
    axis2 = control.axis2,
    rawAxis1Target = control.rawAxis1Target,
    rawAxis2Target = control.rawAxis2Target,
    rawThrottlePower = control.rawThrottlePower,
    axis1Target = control.axis1Target,
    axis2Target = control.axis2Target,
    axis1Power = control.axis1Power,
    axis2Power = control.axis2Power,
    pressed = pressedControls(control),
  }
end

local function compactMixedFrame(mixed)
  if not mixed then
    return nil
  end

  return {
    angle1 = mixed.angle1,
    angle2 = mixed.angle2,
    directAngle1 = mixed.directAngle1,
    directAngle2 = mixed.directAngle2,
    directPitch = mixed.directPitch,
    directRoll = mixed.directRoll,
    directError1 = mixed.directError1,
    directError2 = mixed.directError2,
    directMeasured1 = mixed.directMeasured1,
    directMeasured2 = mixed.directMeasured2,
    directDiff1 = mixed.directDiff1,
    directDiff2 = mixed.directDiff2,
    rate1 = mixed.rate1,
    rate2 = mixed.rate2,
    rateSource = mixed.rateSource,
    rawRate1 = mixed.rawRate1,
    rawRate2 = mixed.rawRate2,
    rawError1 = mixed.rawError1,
    rawError2 = mixed.rawError2,
    measured1 = mixed.measured1,
    measured2 = mixed.measured2,
    target1 = mixed.target1,
    target2 = mixed.target2,
    rawControlPower1 = mixed.rawControlPower1,
    rawControlPower2 = mixed.rawControlPower2,
    controlPower1 = mixed.controlPower1,
    controlPower2 = mixed.controlPower2,
    error1 = mixed.error1,
    error2 = mixed.error2,
    rawCorrection1 = mixed.rawCorrection1,
    rawCorrection2 = mixed.rawCorrection2,
    correction1 = mixed.correction1,
    correction2 = mixed.correction2,
    correctionLimited = mixed.correctionLimited == true,
    basePower = mixed.basePower,
    power = copyPlain(mixed.power),
    desiredSignals = copyPlain(mixed.desiredSignals),
    signals = copyPlain(mixed.signals),
  }
end

local function compactStabilizeFrame(frame)
  return {
    index = frame.index,
    elapsed = frame.elapsed,
    dryRun = frame.dryRun == true,
    aborted = frame.aborted == true,
    abortReason = frame.abortReason,
    killSwitch = copyPlain(frame.killSwitch),
    controller = compactControllerFrame(frame.controller),
    mixed = compactMixedFrame(frame.mixed),
    telemetry = copyPlain(frame.telemetry),
  }
end

local function recoverySummary(report)
  local test = report.recoveryTest
  local frames = report.frames

  if type(test) ~= "table" or type(frames) ~= "table" then
    return nil
  end

  local pulseSeconds = tonumber(test.pulseSeconds) or 0
  local peakAxis1 = 0
  local peakAxis2 = 0
  local peakAfterPulseAxis1 = 0
  local peakAfterPulseAxis2 = 0
  local last = nil

  for _, frame in ipairs(frames) do
    local mixed = frame.mixed or {}
    local axis1 = math.abs(tonumber(mixed.measured1) or 0)
    local axis2 = math.abs(tonumber(mixed.measured2) or 0)
    peakAxis1 = math.max(peakAxis1, axis1)
    peakAxis2 = math.max(peakAxis2, axis2)

    if (tonumber(frame.elapsed) or 0) >= pulseSeconds then
      peakAfterPulseAxis1 = math.max(peakAfterPulseAxis1, axis1)
      peakAfterPulseAxis2 = math.max(peakAfterPulseAxis2, axis2)
    end

    last = frame
  end

  local lastMixed = last and last.mixed or {}

  return {
    peakAxis1 = peakAxis1,
    peakAxis2 = peakAxis2,
    peakAfterPulseAxis1 = peakAfterPulseAxis1,
    peakAfterPulseAxis2 = peakAfterPulseAxis2,
    finalAxis1 = lastMixed.measured1,
    finalAxis2 = lastMixed.measured2,
    finalRate1 = lastMixed.rate1,
    finalRate2 = lastMixed.rate2,
  }
end

function flightControl.levelSet(config)
  local scan, router, routerName = loadContext(config)
  local gimbal = findGimbal(scan, router)
  local state = readGimbal(gimbal)
  local report = baseReport("aircraft_level_set", config, scan, routerName)

  report.gimbal = {
    side = gimbal.side,
    source = gimbal.source,
    coord = gimbal.coord,
  }
  report.state = state
  report.level = {
    gravity = copyPlain(state.gravity),
    anglesRad = copyPlain(state.anglesRad),
    gravityTilt = gravityTilt(state.gravity),
    directTilt = directTilt(state.anglesRad),
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
      anglesRad = { 0, 0 },
      gravityTilt = gravityTilt(gravity),
      directTilt = {
        axis1 = 0,
        axis2 = 0,
        pitch = 0,
        roll = 0,
      },
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
  local rotorDevices, rotorErrors = wrapOptionalRoleDevices(scan, router, "rotorBearing")
  local settings = stabilizeConfig(config, options)
  local controllerContext = controller.open(config, options)
  local testControlContext = recoveryContext(options.recoveryTest)

  local active = options.apply == true and config.dryRun == false
  local hudContext = hud.open(config, options, router, scan)
  local nixieOptions = copyPlain(options)
  nixieOptions.display = settings.nixiesEnabled
  nixieOptions.textOnly = true
  local nixieContext = displays.collect(config, router, scan, nixieOptions)
  local lastNixieElapsed = nil
  local report = baseReport("aircraft_stabilize", config, scan, routerName)

  report.applied = active
  report.request = {
    apply = options.apply == true,
    seconds = settings.seconds,
    forever = settings.forever,
    interval = settings.interval,
    basePower = settings.basePower,
  }
  report.settings = copyPlain(settings)
  report.level = copyPlain(config.level)
  report.gimbal = {
    side = gimbal.side,
    source = gimbal.source,
    coord = gimbal.coord,
  }
  report.hud = hud.describe(hudContext)
  report.controller = controller.describe(controllerContext)
  report.recoveryTest = copyPlain(options.recoveryTest)
  report.killSwitch = copyPlain(settings.killSwitch)
  report.nixies = displays.describe(nixieContext)
  report.rotorTelemetry = {
    errors = copyPlain(rotorErrors),
  }
  report.frames = {}
  report.timing = {
    requestedSeconds = settings.seconds,
    forever = settings.forever,
    interval = settings.interval,
    reportFrameLimit = settings.reportFrameLimit,
    mode = "scheduled_os_clock",
  }

  if options.apply == true and not active then
    report.blockedReason = "config.dryRun is true"
  end

  local function updateNixies(frame, force)
    if not settings.nixiesEnabled then
      return {
        updated = false,
        skipped = "stabilize nixies disabled",
      }
    end

    local elapsed = frame.elapsed or 0
    if not force and lastNixieElapsed and elapsed - lastNixieElapsed < settings.nixieInterval then
      return {
        updated = false,
        skipped = "nixie interval",
      }
    end

    local startTime = os.clock()
    lastNixieElapsed = elapsed
    local result = displays.updateSignals(nixieContext, frame.mixed and frame.mixed.signals)
    result.elapsed = os.clock() - startTime

    return result
  end

  local function runLoop()
    local startTime = os.clock()
    local deadline = nil
    if not settings.forever then
      deadline = startTime + settings.seconds
    end
    local nextFrameTime = startTime
    local frameIndex = 1
    local previousMotion = nil
    local signalResiduals = {}
    local previousControl = {
      axis1Target = 0,
      axis2Target = 0,
      throttlePower = 0,
    }

    while true do
      if active and deadline and frameIndex > 1 and os.clock() >= deadline then
        report.timing.stopReason = "duration_clock"
        break
      end

      local state = readGimbal(gimbal)
      local elapsed = os.clock() - startTime
      local dt = previousMotion and (elapsed - previousMotion.elapsed) or settings.interval
      local rawControl = recoveryControl(options.recoveryTest, elapsed) or controller.sample(controllerContext)
      local controlContext = options.recoveryTest and testControlContext or controllerContext
      local control = smoothControl(controlContext, rawControl, previousControl, dt)
      local mixed = mixerSignals(settings, state, config.level, control, previousMotion, dt, signalResiduals)
      local killSwitch = readKillSwitch(settings)
      local frame = {
        index = frameIndex,
        elapsed = elapsed,
        state = state,
        killSwitch = killSwitch,
        controller = control,
        mixed = mixed,
      }
      local attitudeExceeded = math.abs(mixed.error1) > settings.maxAttitudeDelta
        or math.abs(mixed.error2) > settings.maxAttitudeDelta

      if killSwitch.triggered then
        frame.aborted = true
        if killSwitch.ok == false then
          frame.abortReason = "kill switch read failed"
        else
          frame.abortReason = "kill switch active"
        end
        report.aborted = true
        report.abortReason = frame.abortReason
      elseif attitudeExceeded then
        frame.aborted = true
        frame.abortReason = "attitude error exceeded maxAttitudeDelta"
        report.aborted = true
        report.abortReason = frame.abortReason
      elseif active then
        frame.setResults = applySignals(devices, mixed.signals)
      else
        frame.dryRun = true
      end

      local forceDisplay = attitudeExceeded or killSwitch.triggered
      frame.nixies = updateNixies(frame, forceDisplay)
      if hud.shouldUpdate(hudContext, frame, forceDisplay) then
        frame.telemetry = readRotorTelemetry(rotorDevices)
      end
      frame.hud = hud.update(hudContext, frame, settings, active, forceDisplay)
      if settings.reportFrameLimit == 0 then
        report.timing.framesDropped = (report.timing.framesDropped or 0) + 1
      else
        table.insert(report.frames, compactStabilizeFrame(frame))
        if #report.frames > settings.reportFrameLimit then
          table.remove(report.frames, 1)
          report.timing.framesDropped = (report.timing.framesDropped or 0) + 1
        end
      end

      if attitudeExceeded or killSwitch.triggered then
        break
      end

      if not active then
        break
      end

      previousMotion = {
        elapsed = frame.elapsed,
        measured1 = mixed.measured1,
        measured2 = mixed.measured2,
      }
      previousControl = {
        axis1Target = control.axis1Target,
        axis2Target = control.axis2Target,
        throttlePower = control.throttlePower,
      }
      frameIndex = frameIndex + 1
      nextFrameTime = nextFrameTime + settings.interval

      local delay
      if deadline then
        local remaining = deadline - os.clock()
        if remaining <= 0 then
          report.timing.stopReason = "duration_clock"
          break
        end

        delay = math.min(remaining, nextFrameTime - os.clock())
      else
        delay = nextFrameTime - os.clock()
      end
      if delay > 0 then
        sleep(delay)
      end
    end

    report.timing.elapsed = os.clock() - startTime
    if not report.timing.stopReason then
      report.timing.stopReason = report.abortReason or "loop_complete"
    end
  end

  local ok, result = pcall(runLoop)
  if active and settings.brakeOnExit then
    report.brakeOnExit = brakeDevices(devices, settings.brakeSignal)
    if settings.nixiesEnabled then
      report.nixieBrakeOnExit = displays.updateSignals(nixieContext, {
        front_left = settings.brakeSignal,
        front_right = settings.brakeSignal,
        rear_left = settings.brakeSignal,
        rear_right = settings.brakeSignal,
      })
    end
  end

  if not ok then
    report.error = tostring(result)
    report.timing.stopReason = "error"
  end

  report.recoverySummary = recoverySummary(report)

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
