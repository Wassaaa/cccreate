local coords = require("lib.aircraft.coords")
local actuators = require("lib.aircraft.actuators")
local controller = require("lib.aircraft.controller")
local displays = require("lib.aircraft.displays")
local hud = require("lib.aircraft.hud")
local reporting = require("lib.aircraft.reporting")

local flightControl = {}
local CONTROLLER_VERSION = "clock-stop-v2"
local TIMING_WINDOW = 20
local TIMING_EPSILON = 0.001

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

local function radians(degrees)
  return (tonumber(degrees) or 0) * math.pi / 180
end

local function degrees(radiansValue)
  return (tonumber(radiansValue) or 0) * 180 / math.pi
end

local function vector(x, y, z)
  return {
    x = tonumber(x) or 0,
    y = tonumber(y) or 0,
    z = tonumber(z) or 0,
  }
end

local function vectorLength(value)
  return math.sqrt(coords.dot(value, value))
end

local function vectorScale(value, amount)
  amount = tonumber(amount) or 0

  return {
    x = value.x * amount,
    y = value.y * amount,
    z = value.z * amount,
  }
end

local function vectorNormalize(value, fallback)
  local length = vectorLength(value)
  if length < 0.000001 then
    return fallback and copyPlain(fallback) or vector(0, 0, 0), 0
  end

  return vectorScale(value, 1 / length), length
end

local function vectorToList(value)
  return {
    value.x,
    value.y,
    value.z,
  }
end

local function rotateByQuaternion(q, value)
  local qx = tonumber(q and q[1]) or 0
  local qy = tonumber(q and q[2]) or 0
  local qz = tonumber(q and q[3]) or 0
  local qw = tonumber(q and q[4]) or 1

  local tx = 2 * (qy * value.z - qz * value.y)
  local ty = 2 * (qz * value.x - qx * value.z)
  local tz = 2 * (qx * value.y - qy * value.x)

  return {
    x = value.x + qw * tx + (qy * tz - qz * ty),
    y = value.y + qw * ty + (qz * tx - qx * tz),
    z = value.z + qw * tz + (qx * ty - qy * tx),
  }
end

local function rotateByInverseQuaternion(q, value)
  local inverse = {
    -(tonumber(q and q[1]) or 0),
    -(tonumber(q and q[2]) or 0),
    -(tonumber(q and q[3]) or 0),
    tonumber(q and q[4]) or 1,
  }

  return rotateByQuaternion(inverse, value)
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

local function isRedstoneRouterType(types)
  for _, typeName in ipairs(types or {}) do
    if string.find(string.lower(tostring(typeName)), "redstone_router", 1, true) then
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

local function findRedstoneRouter()
  for _, peripheralName in ipairs(peripheral.getNames()) do
    local types = safePeripheralTypes(peripheralName)

    if isRedstoneRouterType(types) then
      local wrapped = peripheral.wrap(peripheralName)
      if wrapped and type(wrapped.getRedstone) == "function" then
        return wrapped, peripheralName
      end
    end
  end

  local router = peripheral.find("redstone_router")
  if router and type(router.getRedstone) == "function" then
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

local function tryGimbalAt(router, coord)
  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok or not objectOrError then
    return nil
  end

  if type(objectOrError.getAnglesRad) == "function"
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

local function tryNavigationAt(router, coord)
  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok or not objectOrError then
    return nil
  end

  if type(objectOrError.getOrientation) == "function" then
    return objectOrError
  end

  return nil
end

local function tryAltitudeAt(router, coord)
  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok or not objectOrError then
    return nil
  end

  if type(objectOrError.getHeight) == "function" then
    return objectOrError
  end

  return nil
end

local function findFirstCategoryDevice(scan, router, category, tryWrap, label)
  local mapped = scan.orientation
    and scan.orientation.sensors
    and scan.orientation.sensors[category]

  if mapped and mapped.coord then
    local object = tryWrap(router, mapped.coord)
    if object then
      return {
        source = "scan_sensor",
        coord = copyPlain(mapped.coord),
        object = object,
      }, nil
    end
  end

  for _, entry in ipairs(scan.peripherals or {}) do
    if entry.coord and hasCategory(entry, category) then
      local object = tryWrap(router, entry.coord)
      if object then
        return {
          source = "scan_category",
          coord = copyPlain(entry.coord),
          object = object,
        }, nil
      end
    end
  end

  return nil, "No " .. label .. " found in scan"
end

local function wrapOptionalSensors(scan, router)
  local sensors = {}
  local errors = {}

  sensors.navigation, errors.navigation = findFirstCategoryDevice(
    scan,
    router,
    "navigationSensor",
    tryNavigationAt,
    "navigation table"
  )
  sensors.altitude, errors.altitude = findFirstCategoryDevice(
    scan,
    router,
    "altitudeSensor",
    tryAltitudeAt,
    "altitude sensor"
  )

  return sensors, errors
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

local function wrapManualGyroDevices(scan, router)
  local rotorDevices, rotorErrors = wrapOptionalRoleDevices(scan, router, "rotorBearing")
  local devices = {}
  local errors = copyPlain(rotorErrors)

  for _, role in ipairs(ROLE_ORDER) do
    local rotor = rotorDevices[role]
    if rotor then
      if type(rotor.object.setManualTarget) == "function"
          and type(rotor.object.clearManualTarget) == "function" then
        devices[role] = rotor
      else
        errors[role] = "rotor bearing at "
          .. coords.label(rotor.coord)
          .. " does not expose manual gyro target methods"
      end
    elseif not errors[role] then
      errors[role] = "missing rotor bearing role"
    end
  end

  return devices, errors
end

local function saveAndSend(config, report)
  local path = "/aircraft_stabilize.txt"

  reporting.save(report, path, config, { localReport = false })
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  return config.sendWebhook ~= false and "webhook" or "webhook disabled"
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
  local angles = nil
  local angleError = nil
  local rates = nil
  local rateError = nil

  parallel.waitForAll(
    function()
      angles, angleError = callGetter(gimbal.object, "getAnglesRad")
    end,
    function()
      rates, rateError = callGetter(gimbal.object, "getAngularRatesRad")
    end
  )

  if angleError then
    error("gimbal getAnglesRad failed: " .. tostring(angleError), 0)
  end

  if rateError then
    error("gimbal getAngularRatesRad failed: " .. tostring(rateError), 0)
  end

  return {
    angles = angles,
    angularRates = rates,
  }
end

local function numberAt(values, index)
  local value = values and values[index]
  if type(value) ~= "number" then
    return 0
  end

  return value
end

local function attitudeAngles(angles)
  local pitch = numberAt(angles, 1)
  local roll = numberAt(angles, 2)

  -- The gimbal reports { pitch about body-X, roll about body-Z }.
  -- The mixer axis1 is left/right correction, so positive roll maps negative.
  return {
    axis1 = -roll,
    axis2 = pitch,
    pitch = pitch,
    roll = roll,
  }
end

local function attitudeRates(rates)
  local pitchRate = numberAt(rates, 1)
  local yawRate = numberAt(rates, 2)
  local rollRate = numberAt(rates, 3)

  -- Do not mirror the angle negation here; -rollRate was anti-damping axis1.
  return {
    axis1 = rollRate,
    axis2 = pitchRate,
    yaw = yawRate,
    pitch = pitchRate,
    roll = rollRate,
  }
end

local function normalizeKillSwitchSource(source)
  local normalized = string.lower(tostring(source or "side"))
  if normalized == "keyboard" or normalized == "controller" then
    normalized = "key"
  end

  if normalized == "key" or normalized == "side" or normalized == "router" then
    return normalized
  end

  return "side"
end

local function yawSign(value)
  local number = tonumber(value)
  if number and number < 0 then
    return -1
  end

  return 1
end

local function stabilizeConfig(config, options)
  local defaults = config.stabilize or {}
  local yaw = config.yaw or {}
  local display = config.display or {}
  local killSwitch = config.killSwitch or {}
  local actuatorSettings = actuators.settings(config, options)
  local interval = tonumber(options.interval) or tonumber(defaults.interval) or 0.05
  local nixiesEnabled = display.stabilizeEnabled == true
  local killSwitchEnabled = killSwitch.enabled == true
  local yawEnabled = yaw.enabled ~= false
  local yawMaxTiltDeg = clamp(math.abs(tonumber(options.yawMaxTiltDeg) or tonumber(yaw.maxTiltDeg) or 8), 0, 12)
  local yawDeadbandDegPerSecond = math.max(
    0,
    tonumber(options.yawDeadbandDegPerSecond) or tonumber(yaw.deadbandDegPerSecond) or 0.5
  )

  if interval <= 0 then
    error("stabilize interval must be greater than zero", 0)
  end

  if options.nixies ~= nil then
    nixiesEnabled = options.nixies == true
  end
  if options.killSwitch ~= nil then
    killSwitchEnabled = options.killSwitch == true
  end
  if options.yaw ~= nil then
    yawEnabled = options.yaw == true
  end

  return {
    forever = options.forever == true,
    seconds = tonumber(options.seconds) or tonumber(defaults.seconds) or 1,
    interval = interval,
    basePower = tonumber(options.basePower) or tonumber(defaults.basePower) or 0,
    maxPower = actuatorSettings.maxPower,
    maxSignal = actuatorSettings.maxSignal or actuatorSettings.maxPower,
    brakeSignal = actuatorSettings.brakeSignal or actuatorSettings.brakeRpm or 0,
    actuator = actuatorSettings,
    axis1Kp = tonumber(options.axis1Kp) or tonumber(options.kp) or tonumber(defaults.axis1Kp) or 4,
    axis2Kp = tonumber(options.axis2Kp) or tonumber(options.kp) or tonumber(defaults.axis2Kp) or 4,
    axis1Kd = tonumber(options.axis1Kd) or tonumber(options.kd) or tonumber(defaults.axis1Kd) or 0.12,
    axis2Kd = tonumber(options.axis2Kd) or tonumber(options.kd) or tonumber(defaults.axis2Kd) or 0.2,
    axis1Trim = tonumber(options.axis1Trim) or tonumber(defaults.axis1Trim) or 0,
    axis2Trim = tonumber(options.axis2Trim) or tonumber(defaults.axis2Trim) or 0,
    maxCorrection = tonumber(options.maxCorrection) or tonumber(defaults.maxCorrection) or 1.5,
    desaturate = defaults.desaturate ~= false,
    desaturateHeadroom = tonumber(defaults.desaturateHeadroom) or 0.75,
    tiltCompensation = defaults.tiltCompensation ~= false,
    tiltCompensationGain = tonumber(defaults.tiltCompensationGain) or 1,
    tiltCompensationMaxPower = tonumber(defaults.tiltCompensationMaxPower) or 2,
    signalDither = defaults.signalDither ~= false,
    maxAttitudeDelta = tonumber(options.maxAttitudeDelta)
        or (tonumber(options.maxAttitudeDeg) and tonumber(options.maxAttitudeDeg) * math.pi / 180)
        or tonumber(defaults.maxAttitudeDelta)
        or tonumber(config.maxAttitudeDelta)
        or 2,
    brakeOnExit = defaults.brakeOnExit ~= false,
    reportFrameLimit = tonumber(options.reportFrameLimit) or tonumber(defaults.reportFrameLimit) or 600,
    yaw = {
      enabled = yawEnabled,
      rateKd = math.max(0, tonumber(options.yawRateKd) or tonumber(yaw.rateKd) or 0.15),
      maxTiltDeg = yawMaxTiltDeg,
      maxTilt = radians(yawMaxTiltDeg),
      deadbandDegPerSecond = yawDeadbandDegPerSecond,
      deadband = radians(yawDeadbandDegPerSecond),
      sign = yawSign(options.yawSign or yaw.sign or 1),
      commandLateral = math.max(0, tonumber(options.yawCommandLateral) or tonumber(yaw.commandLateral) or 0.08),
      clearOnExit = yaw.clearOnExit ~= false,
      writeInterval = math.max(0, tonumber(options.yawWriteInterval) or tonumber(yaw.writeInterval) or 0.1),
      writeDeadband = math.max(0, tonumber(options.yawWriteDeadband) or tonumber(yaw.writeDeadband) or 0.01),
    },
    killSwitch = {
      enabled = killSwitchEnabled,
      source = normalizeKillSwitchSource(killSwitch.source or (killSwitch.binding and "router" or "side")),
      side = tostring(killSwitch.side or "front"),
      activeHigh = killSwitch.activeHigh ~= false,
      keyEnabled = killSwitch.keyEnabled ~= false,
      key = tostring(killSwitch.key or "k"),
      binding = copyPlain(killSwitch.binding),
    },
    nixiesEnabled = nixiesEnabled,
    nixieInterval = tonumber(options.nixieInterval) or tonumber(display.stabilizeInterval) or 1,
  }
end

local function normalizeRouterSide(side)
  local value = string.lower(tostring(side or "up"))
  if value == "top" then
    return "up"
  elseif value == "bottom" then
    return "down"
  end

  return value
end

local function normalizeRouterBinding(binding)
  if type(binding) ~= "table" then
    return nil
  end

  return {
    x = tonumber(binding.x) or 0,
    y = tonumber(binding.y) or 0,
    z = tonumber(binding.z) or 0,
    side = normalizeRouterSide(binding.side),
  }
end

local function redstoneValue(input)
  if input == true then
    return true
  elseif input == false or input == nil then
    return false
  end

  return (tonumber(input) or 0) > 0
end

local function readLocalKillSwitch(killSwitch)
  local side = tostring(killSwitch.side or "front")
  if type(redstone) ~= "table" or type(redstone.getInput) ~= "function" then
    return {
      source = "side",
      side = side,
      ok = false,
      input = nil,
      triggered = true,
      error = "redstone.getInput unavailable",
    }
  end

  local ok, inputOrError = pcall(redstone.getInput, side)
  if not ok then
    return {
      source = "side",
      side = side,
      ok = false,
      input = nil,
      triggered = true,
      error = tostring(inputOrError),
    }
  end

  local input = inputOrError == true
  return {
    source = "side",
    side = side,
    ok = true,
    input = input,
    triggered = input == (killSwitch.activeHigh ~= false),
  }
end

local function readRouterKillSwitch(killSwitch, router, routerName)
  local binding = normalizeRouterBinding(killSwitch.binding)
  if not binding then
    return {
      source = "router",
      ok = false,
      triggered = true,
      error = "missing router kill switch binding",
    }
  end

  if not router then
    return {
      source = "router",
      binding = binding,
      ok = false,
      triggered = true,
      error = "No redstone_router with getRedstone(x, y, z, side) found",
    }
  end

  local ok, inputOrError = pcall(router.getRedstone, binding.x, binding.y, binding.z, binding.side)
  if not ok then
    return {
      source = "router",
      routerName = routerName,
      binding = binding,
      ok = false,
      triggered = true,
      error = tostring(inputOrError),
    }
  end

  local input = redstoneValue(inputOrError)
  return {
    source = "router",
    routerName = routerName,
    binding = binding,
    ok = true,
    input = input,
    rawInput = inputOrError,
    triggered = input == (killSwitch.activeHigh ~= false),
  }
end

local function readKeyKillSwitch(killSwitch, control)
  local key = tostring(killSwitch.key or "k")
  local read = control and control.reads and control.reads[key]
  local pressed = read and read.pressed == true

  return {
    source = "controller_key",
    key = key,
    ok = true,
    pressed = pressed,
    triggered = pressed,
    read = copyPlain(read),
  }
end

local function readKillSwitch(settings, control, router, routerName)
  local killSwitch = settings.killSwitch or {}
  if not killSwitch.enabled then
    return {
      enabled = false,
      triggered = false,
    }
  end

  local source = tostring(killSwitch.source or "side")
  local result = {
    enabled = true,
    source = source,
    side = killSwitch.side,
    binding = copyPlain(killSwitch.binding),
    activeHigh = killSwitch.activeHigh ~= false,
    keyEnabled = killSwitch.keyEnabled ~= false,
    key = killSwitch.key or "k",
    ok = true,
    triggered = false,
    checks = {},
  }

  local function addCheck(check)
    table.insert(result.checks, check)
    if check.ok == false then
      result.ok = false
      result.triggered = true
      result.error = result.error or check.error
      result.triggeredBy = result.triggeredBy or check.source
    elseif check.triggered then
      result.triggered = true
      result.triggeredBy = result.triggeredBy or check.source
    end
  end

  if killSwitch.keyEnabled ~= false then
    addCheck(readKeyKillSwitch(killSwitch, control))
  end

  if source == "router" then
    addCheck(readRouterKillSwitch(killSwitch, router, routerName))
  elseif source == "controller" or source == "keyboard" or source == "key" then
    -- Key-only kill switch. Nothing else to read.
  else
    addCheck(readLocalKillSwitch(killSwitch))
  end

  return result
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
  local throttleMode = tostring(settings.throttleMode or "hold")

  result.rawAxis1Target = tonumber(control.axis1Target) or 0
  result.rawAxis2Target = tonumber(control.axis2Target) or 0
  result.rawThrottlePower = tonumber(control.throttlePower) or 0
  result.rawYaw = tonumber(control.yaw) or 0
  result.yaw = clamp(result.rawYaw, -1, 1)
  result.throttleMode = throttleMode

  if elapsed > 0 and previousControl then
    local targetStep = targetSlew * math.pi / 180 * elapsed
    local throttleStep = throttleSlew * elapsed

    result.axis1Target = slewValue(previousControl.axis1Target, result.rawAxis1Target, targetStep)
    result.axis2Target = slewValue(previousControl.axis2Target, result.rawAxis2Target, targetStep)

    if throttleMode == "hold" then
      local previousHeld = tonumber(previousControl.heldThrottlePower) or tonumber(previousControl.throttlePower) or 0
      local throttleInput = tonumber(control.throttle) or 0
      local maxThrottle = math.abs(tonumber(settings.throttlePower) or math.abs(result.rawThrottlePower) or 0)
      local held = previousHeld + throttleInput * throttleStep

      result.throttlePower = clamp(held, -maxThrottle, maxThrottle)
      result.heldThrottlePower = result.throttlePower
    else
      result.throttlePower = slewValue(previousControl.throttlePower, result.rawThrottlePower, throttleStep)
      result.heldThrottlePower = nil
    end
  elseif throttleMode == "hold" then
    result.throttlePower = tonumber(previousControl and previousControl.heldThrottlePower) or 0
    result.heldThrottlePower = result.throttlePower
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
    yaw = active and (tonumber(test.yaw) or 0) or 0,
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
      throttleMode = "momentary",
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

local function rangeOfPower(power)
  local minValue = nil
  local maxValue = nil

  for _, role in ipairs(ROLE_ORDER) do
    local value = tonumber(power and power[role]) or 0
    minValue = minValue and math.min(minValue, value) or value
    maxValue = maxValue and math.max(maxValue, value) or value
  end

  return minValue or 0, maxValue or 0
end

local function desaturateRange(power, minValue, maxValue, enabled, headroom)
  minValue = tonumber(minValue) or 0
  maxValue = tonumber(maxValue) or minValue
  if minValue > maxValue then
    minValue, maxValue = maxValue, minValue
  end

  local inputMin, inputMax = rangeOfPower(power)
  local rawInputMin = inputMin
  local rawInputMax = inputMax
  local range = math.max(0, maxValue - minValue)
  local margin = clamp(tonumber(headroom) or 0, 0, math.max(0, range / 2 - 0.01))
  local minAllowed = minValue + margin
  local maxAllowed = maxValue - margin
  local available = math.max(0.01, maxAllowed - minAllowed)
  local span = inputMax - inputMin
  local adjusted = {}
  local scaled = false
  local scale = 1

  if enabled ~= false and span > available then
    scaled = true
    scale = available / span
    local center = (inputMin + inputMax) / 2
    for _, role in ipairs(ROLE_ORDER) do
      adjusted[role] = center + ((tonumber(power[role]) or 0) - center) * scale
    end
    inputMin, inputMax = rangeOfPower(adjusted)
  else
    for _, role in ipairs(ROLE_ORDER) do
      adjusted[role] = tonumber(power[role]) or 0
    end
  end

  local shift = 0

  if enabled ~= false then
    if inputMin < minAllowed then
      shift = minAllowed - inputMin
    end

    if inputMax + shift > maxAllowed then
      shift = shift - (inputMax + shift - maxAllowed)
    end
  end

  local result = {}
  local saturated = false

  for _, role in ipairs(ROLE_ORDER) do
    local shifted = (tonumber(adjusted[role]) or 0) + shift
    local clamped = clamp(shifted, minValue, maxValue)
    result[role] = clamped
    if math.abs(clamped - shifted) > 0.000001 then
      saturated = true
    end
  end

  local outputMin, outputMax = rangeOfPower(result)
  return result, {
    enabled = enabled ~= false,
    headroom = margin,
    minAllowed = minAllowed,
    maxAllowed = maxAllowed,
    scaled = scaled,
    scale = scale,
    shift = shift,
    inputMin = rawInputMin,
    inputMax = rawInputMax,
    adjustedMin = inputMin,
    adjustedMax = inputMax,
    outputMin = outputMin,
    outputMax = outputMax,
    saturated = saturated,
    minValue = minValue,
    maxValue = maxValue,
  }
end

local function desaturatePower(power, maxPower, enabled, headroom)
  return desaturateRange(power, 0, maxPower, enabled, headroom)
end

local function rpmDesaturateHeadroom(settings, rpm)
  local configured = tonumber(rpm and rpm.desaturateHeadroomRpm)
  if configured then
    return math.max(0, configured)
  end

  local throttleRpmPerPower = math.abs(tonumber(rpm and rpm.throttleRpmPerPower) or 0)
  return math.max(0, tonumber(settings and settings.desaturateHeadroom) or 0) * throttleRpmPerPower
end

local function tiltCompensationPower(settings, target1, target2, basePower)
  if settings.tiltCompensation == false then
    return 0, {
      enabled = false,
    }
  end

  local base = math.max(0, tonumber(basePower) or 0)
  local tilt = math.sqrt((tonumber(target1) or 0) ^ 2 + (tonumber(target2) or 0) ^ 2)
  local limitedTilt = clamp(tilt, 0, math.pi / 2 - 0.01)
  local cosTilt = math.max(0.1, math.cos(limitedTilt))
  local gain = tonumber(settings.tiltCompensationGain) or 1
  local maxPower = math.max(0, tonumber(settings.tiltCompensationMaxPower) or 0)
  local rawPower = base * ((1 / cosTilt) - 1) * gain
  local power = clamp(rawPower, 0, maxPower)

  return power, {
    enabled = true,
    source = "target",
    tilt = tilt,
    cosTilt = cosTilt,
    gain = gain,
    maxPower = maxPower,
    rawPower = rawPower,
    power = power,
    limited = power ~= rawPower,
  }
end

local function mixerSignals(settings, state, control, signalResiduals)
  control = control or {}

  local currentTilt = attitudeAngles(state.angles)
  local rates = attitudeRates(state.angularRates)
  local rawRate1 = rates.axis1
  local rawRate2 = rates.axis2
  local rawYawRate = rates.yaw
  local rawError1 = currentTilt.axis1
  local rawError2 = currentTilt.axis2
  local measured1 = wrapRadians(rawError1)
  local measured2 = wrapRadians(rawError2)

  local target1 = tonumber(control.axis1Target) or 0
  local target2 = tonumber(control.axis2Target) or 0
  local rawControlPower1 = tonumber(control.axis1Power) or 0
  local rawControlPower2 = tonumber(control.axis2Power) or 0
  local error1 = measured1 - target1
  local error2 = measured2 - target2
  local controlPower1 = targetAssistPower(rawControlPower1, error1, target1)
  local controlPower2 = targetAssistPower(rawControlPower2, error2, target2)
  local rate1 = rawRate1
  local rate2 = rawRate2

  if settings.actuator and settings.actuator.type == "rotation_speed" then
    local rpm = settings.actuator
    local throttleRpm = (tonumber(control.throttlePower) or 0) * (tonumber(rpm.throttleRpmPerPower) or 0)
    local baseRpmBeforeTilt = (tonumber(rpm.baseRpm) or 0) + throttleRpm
    local rawControlRpm1 = rawControlPower1 * (tonumber(rpm.axisPowerRpmPerPower) or tonumber(rpm.throttleRpmPerPower) or 1)
    local rawControlRpm2 = rawControlPower2 * (tonumber(rpm.axisPowerRpmPerPower) or tonumber(rpm.throttleRpmPerPower) or 1)
    local controlRpm1 = targetAssistPower(rawControlRpm1, error1, target1)
    local controlRpm2 = targetAssistPower(rawControlRpm2, error2, target2)
    local rawCorrection1Rpm = -((tonumber(rpm.axis1KpRpm) or 0) * error1 + (tonumber(rpm.axis1KdRpm) or 0) * rate1)
      + (tonumber(rpm.axis1TrimRpm) or 0)
      + controlRpm1
    local rawCorrection2Rpm = -((tonumber(rpm.axis2KpRpm) or 0) * error2 + (tonumber(rpm.axis2KdRpm) or 0) * rate2)
      + (tonumber(rpm.axis2TrimRpm) or 0)
      + controlRpm2
    local maxCorrectionRpm = math.abs(tonumber(rpm.maxCorrectionRpm) or 0)
    local correction1Rpm = maxCorrectionRpm > 0
      and clamp(rawCorrection1Rpm, -maxCorrectionRpm, maxCorrectionRpm)
      or rawCorrection1Rpm
    local correction2Rpm = maxCorrectionRpm > 0
      and clamp(rawCorrection2Rpm, -maxCorrectionRpm, maxCorrectionRpm)
      or rawCorrection2Rpm
    local baseRpm = baseRpmBeforeTilt
    local rawTargetRpm = {
      front_left = baseRpm + correction1Rpm - correction2Rpm,
      front_right = baseRpm - correction1Rpm - correction2Rpm,
      rear_left = baseRpm + correction1Rpm + correction2Rpm,
      rear_right = baseRpm - correction1Rpm + correction2Rpm,
    }
    local minTarget = math.max(0, tonumber(rpm.minTargetRpm) or 0)
    local maxTarget = math.max(minTarget, tonumber(rpm.maxTargetRpm) or 256)
    local targetRpm, desaturation = desaturateRange(
      rawTargetRpm,
      minTarget,
      maxTarget,
      settings.desaturate,
      rpmDesaturateHeadroom(settings, rpm)
    )
    desaturation.unit = "rpm"

    local actuatorFrame = actuators.outputsFromRpm(rpm, targetRpm)

    return {
      angle1 = currentTilt.axis1,
      angle2 = currentTilt.axis2,
      rate1 = rate1,
      rate2 = rate2,
      yawRate = rawYawRate,
      rawRate1 = rawRate1,
      rawRate2 = rawRate2,
      rawYawRate = rawYawRate,
      neutral1 = 0,
      neutral2 = 0,
      currentTilt = currentTilt,
      neutralTilt = {
        axis1 = 0,
        axis2 = 0,
        pitch = 0,
        roll = 0,
      },
      rawError1 = rawError1,
      rawError2 = rawError2,
      measured1 = measured1,
      measured2 = measured2,
      target1 = target1,
      target2 = target2,
      rawControlPower1 = rawControlPower1,
      rawControlPower2 = rawControlPower2,
      rawControlRpm1 = rawControlRpm1,
      rawControlRpm2 = rawControlRpm2,
      controlPower1 = controlRpm1,
      controlPower2 = controlRpm2,
      controlRpm1 = controlRpm1,
      controlRpm2 = controlRpm2,
      error1 = error1,
      error2 = error2,
      rawCorrection1 = rawCorrection1Rpm,
      rawCorrection2 = rawCorrection2Rpm,
      rawCorrection1Rpm = rawCorrection1Rpm,
      rawCorrection2Rpm = rawCorrection2Rpm,
      trim1 = tonumber(rpm.axis1TrimRpm) or 0,
      trim2 = tonumber(rpm.axis2TrimRpm) or 0,
      correction1 = correction1Rpm,
      correction2 = correction2Rpm,
      correction1Rpm = correction1Rpm,
      correction2Rpm = correction2Rpm,
      correctionLimited = correction1Rpm ~= rawCorrection1Rpm
        or correction2Rpm ~= rawCorrection2Rpm,
      basePowerBeforeTilt = baseRpmBeforeTilt,
      baseRpmBeforeTilt = baseRpmBeforeTilt,
      throttleRpm = throttleRpm,
      tiltCompensationPower = 0,
      tiltCompensation = {
        enabled = false,
        source = "rpm_native",
      },
      basePower = baseRpm,
      baseRpm = baseRpm,
      rawPower = rawTargetRpm,
      power = targetRpm,
      rawTargetRpm = rawTargetRpm,
      targetRpm = targetRpm,
      desaturation = desaturation,
      control = copyPlain(control),
      desiredSignals = actuatorFrame.desiredSignals,
      signals = actuatorFrame.signals or actuatorFrame.outputs,
      outputs = actuatorFrame.outputs,
      displayValues = actuatorFrame.displayValues,
      actuator = actuatorFrame,
    }
  end

  local rawCorrection1 = -(settings.axis1Kp * error1 + settings.axis1Kd * rate1) + settings.axis1Trim + controlPower1
  local rawCorrection2 = -(settings.axis2Kp * error2 + settings.axis2Kd * rate2) + settings.axis2Trim + controlPower2
  local correction1 = clamp(rawCorrection1, -settings.maxCorrection, settings.maxCorrection)
  local correction2 = clamp(rawCorrection2, -settings.maxCorrection, settings.maxCorrection)
  local basePowerBeforeTilt = settings.basePower + (tonumber(control.throttlePower) or 0)
  local tiltCompensation, tiltCompensationDetails = tiltCompensationPower(
    settings,
    target1,
    target2,
    basePowerBeforeTilt
  )
  local basePower = basePowerBeforeTilt + tiltCompensation
  local rawPower = {
    front_left = basePower + correction1 - correction2,
    front_right = basePower - correction1 - correction2,
    rear_left = basePower + correction1 + correction2,
    rear_right = basePower - correction1 + correction2,
  }
  local power, desaturation = desaturatePower(
    rawPower,
    settings.maxPower,
    settings.desaturate,
    settings.desaturateHeadroom
  )
  local actuatorFrame = actuators.outputsFromPower(
    settings.actuator,
    power,
    settings.signalDither and signalResiduals or nil
  )

  return {
    angle1 = currentTilt.axis1,
    angle2 = currentTilt.axis2,
    rate1 = rate1,
    rate2 = rate2,
    yawRate = rawYawRate,
    rawRate1 = rawRate1,
    rawRate2 = rawRate2,
    rawYawRate = rawYawRate,
    neutral1 = 0,
    neutral2 = 0,
    currentTilt = currentTilt,
    neutralTilt = {
      axis1 = 0,
      axis2 = 0,
      pitch = 0,
      roll = 0,
    },
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
    correctionLimited = correction1 ~= rawCorrection1
      or correction2 ~= rawCorrection2,
    basePowerBeforeTilt = basePowerBeforeTilt,
    tiltCompensationPower = tiltCompensation,
    tiltCompensation = tiltCompensationDetails,
    basePower = basePower,
    rawPower = rawPower,
    control = copyPlain(control),
    power = power,
    desaturation = desaturation,
    desiredSignals = actuatorFrame.desiredSignals,
    signals = actuatorFrame.signals or actuatorFrame.outputs,
    outputs = actuatorFrame.outputs,
    displayValues = actuatorFrame.displayValues,
    actuator = actuatorFrame,
  }
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
      roleTelemetry.thrustHandedness = readOptionalGetter(rotor.object, "getThrustHandedness")
      roleTelemetry.blockNormal = readOptionalGetter(rotor.object, "getBlockNormal")
      roleTelemetry.thrustVector = readOptionalGetter(rotor.object, "getThrustVector")
      roleTelemetry.tiltAngle = readOptionalGetter(rotor.object, "getTiltAngle")
      roleTelemetry.stabilizationStrength = readOptionalGetter(rotor.object, "getStabilizationStrength")
      roleTelemetry.manualTarget = readOptionalGetter(rotor.object, "getManualTarget")
    end

    result.roles[role] = roleTelemetry
  end

  return result
end

local function readSensorTelemetry(sensors)
  local result = {}

  if sensors and sensors.navigation then
    local navigation = sensors.navigation.object
    result.navigation = {
      coord = copyPlain(sensors.navigation.coord),
      source = sensors.navigation.source,
      orientation = readOptionalGetter(navigation, "getOrientation"),
      heading = readOptionalGetter(navigation, "getHeading"),
      headingRad = readOptionalGetter(navigation, "getHeadingRad"),
      hasTarget = readOptionalGetter(navigation, "hasTarget"),
      targetType = readOptionalGetter(navigation, "getTargetType"),
      bearingRad = readOptionalGetter(navigation, "getBearingRad"),
      distanceToTarget = readOptionalGetter(navigation, "getDistanceToTarget"),
    }
  end

  if sensors and sensors.altitude then
    local altitude = sensors.altitude.object
    result.altitude = {
      coord = copyPlain(sensors.altitude.coord),
      source = sensors.altitude.source,
      height = readOptionalGetter(altitude, "getHeight"),
      verticalSpeed = readOptionalGetter(altitude, "getVerticalSpeed"),
      airPressure = readOptionalGetter(altitude, "getAirPressure"),
    }
  end

  return result
end

local function roleCenter(devices)
  local total = vector(0, 0, 0)
  local count = 0

  for _, role in ipairs(ROLE_ORDER) do
    local device = devices and devices[role]
    if device and device.coord then
      total = coords.add(total, vector(device.coord.x, device.coord.y, device.coord.z))
      count = count + 1
    end
  end

  if count == 0 then
    return nil
  end

  return vectorScale(total, 1 / count)
end

local function orientationUpVector(scan)
  local up = scan
    and scan.orientation
    and scan.orientation.upVector

  if coords.isCardinal(up) then
    return vector(up.x, up.y, up.z)
  end

  return vector(0, 1, 0)
end

local function buildYawFrame(settings, state, scan, sensors, gyroDevices, control)
  local yawSettings = settings.yaw or {}
  local yawRate = numberAt(state and state.angularRates, 2)
  local commandYaw = clamp(tonumber(control and control.yaw) or 0, -1, 1)
  local result = {
    enabled = yawSettings.enabled == true,
    yawRate = yawRate,
    yawRateDegPerSecond = degrees(yawRate),
    commandYaw = commandYaw,
    commands = {},
  }

  if not result.enabled then
    result.skipped = "yaw disabled"
    return result
  end

  if not sensors or not sensors.navigation then
    result.skipped = "navigation table missing"
    return result
  end

  local center = roleCenter(gyroDevices)
  if not center then
    result.skipped = "manual gyro bearings missing"
    return result
  end

  local orientation, orientationError = callGetter(sensors.navigation.object, "getOrientation")
  if orientationError then
    result.skipped = "navigation getOrientation failed"
    result.error = orientationError
    return result
  end
  if type(orientation) ~= "table" then
    result.skipped = "navigation getOrientation returned non-table"
    return result
  end

  local heading = readOptionalGetter(sensors.navigation.object, "getHeadingRad")
  local craftUp = orientationUpVector(scan)
  craftUp = vectorNormalize(craftUp, vector(0, 1, 0))
  local worldUp = vector(0, 1, 0)

  local activeRate = yawRate
  if math.abs(activeRate) < (tonumber(yawSettings.deadband) or 0) then
    activeRate = 0
  end

  local sign = yawSign(yawSettings.sign)
  local maxLateral = math.tan(tonumber(yawSettings.maxTilt) or 0)
  local rateLateral = -sign * (tonumber(yawSettings.rateKd) or 0) * activeRate
  local commandLateral = sign * (tonumber(yawSettings.commandLateral) or 0) * commandYaw
  local rawLateral = rateLateral + commandLateral
  local lateral = clamp(rawLateral, -maxLateral, maxLateral)

  result.headingRad = heading and heading.ok and heading.value or nil
  result.headingRadRead = heading
  result.center = center
  result.up = worldUp
  result.craftUp = craftUp
  result.worldUp = worldUp
  result.targetMode = "manual_local_from_world_target"
  result.yawTangentMode = "world_up_cross_world_radial"
  result.orientation = copyPlain(orientation)
  result.activeYawRate = activeRate
  result.rateLateral = rateLateral
  result.commandLateral = commandLateral
  result.rawLateral = rawLateral
  result.lateral = lateral
  result.maxLateral = maxLateral
  result.tiltDeg = degrees(math.atan(math.abs(lateral)))
  result.sign = sign

  for _, role in ipairs(ROLE_ORDER) do
    local device = gyroDevices and gyroDevices[role]

    if device and device.coord then
      local localBaseTarget = rotateByInverseQuaternion(orientation, worldUp)
      localBaseTarget = vectorNormalize(localBaseTarget, craftUp)
      local relative = coords.sub(vector(device.coord.x, device.coord.y, device.coord.z), center)
      local vertical = vectorScale(craftUp, coords.dot(relative, craftUp))
      local radial = coords.sub(relative, vertical)
      local radialUnit, radius = vectorNormalize(radial)

      if radius > 0.000001 then
        local tangent = coords.cross(craftUp, radialUnit)
        tangent = vectorNormalize(tangent)

        local worldRelative = rotateByQuaternion(orientation, relative)
        local worldVertical = vectorScale(worldUp, coords.dot(worldRelative, worldUp))
        local worldRadial = coords.sub(worldRelative, worldVertical)
        local worldRadialUnit, worldRadius = vectorNormalize(worldRadial)

        if worldRadius <= 0.000001 then
          result.commands[role] = {
            role = role,
            coord = copyPlain(device.coord),
            radius = radius,
            radial = radialUnit,
            skipped = "rotor is on world yaw centerline",
          }
        else
          local worldTangent = coords.cross(worldUp, worldRadialUnit)
          worldTangent = vectorNormalize(worldTangent)

          local worldTarget = coords.add(worldUp, vectorScale(worldTangent, lateral))
          worldTarget = vectorNormalize(worldTarget, worldUp)
          local localTarget = rotateByInverseQuaternion(orientation, worldTarget)
          localTarget = vectorNormalize(localTarget, localBaseTarget)

          result.commands[role] = {
            role = role,
            coord = copyPlain(device.coord),
            radius = radius,
            radial = radialUnit,
            tangent = tangent,
            worldRelative = worldRelative,
            worldRadius = worldRadius,
            worldRadial = worldRadialUnit,
            worldTangent = worldTangent,
            baseTarget = localBaseTarget,
            localTarget = localTarget,
            worldBaseTarget = worldUp,
            worldTarget = worldTarget,
            target = vectorToList(localTarget),
          }
        end
      else
        result.commands[role] = {
          role = role,
          coord = copyPlain(device.coord),
          skipped = "rotor is on yaw centerline",
        }
      end
    else
      result.commands[role] = {
        role = role,
        skipped = "manual gyro bearing missing",
      }
    end
  end

  return result
end

local function applyYawTargets(gyroDevices, yawFrame, active)
  if not yawFrame or not yawFrame.enabled or yawFrame.skipped then
    return {
      applied = false,
      skipped = yawFrame and yawFrame.skipped or "yaw unavailable",
    }
  end

  local results = {}
  local tasks = {}

  for _, role in ipairs(ROLE_ORDER) do
    local command = yawFrame.commands and yawFrame.commands[role]
    local device = gyroDevices and gyroDevices[role]

    if command and command.target and device then
      if active then
        local roleName = role
        local target = command.target
        table.insert(tasks, function()
          results[roleName] = callSetter(device.object, "setManualTarget", target)
        end)
      else
        results[role] = {
          ok = true,
          dryRun = true,
          method = "setManualTarget",
          target = copyPlain(command.target),
        }
      end
    else
      results[role] = {
        ok = false,
        skipped = command and command.skipped or "missing target",
      }
    end
  end

  if active and #tasks > 0 then
    parallel.waitForAll(unpack(tasks))
  end

  return {
    applied = active,
    results = results,
  }
end

local function yawTargetsFromFrame(yawFrame)
  local targets = {}

  for _, role in ipairs(ROLE_ORDER) do
    local command = yawFrame
      and yawFrame.commands
      and yawFrame.commands[role]

    if command and command.target then
      targets[role] = copyPlain(command.target)
    end
  end

  return targets
end

local function yawTargetDelta(previousTargets, yawFrame)
  if not previousTargets then
    return nil
  end

  local maxDelta = 0

  for _, role in ipairs(ROLE_ORDER) do
    local previous = previousTargets[role]
    local command = yawFrame
      and yawFrame.commands
      and yawFrame.commands[role]
    local current = command and command.target

    if not previous or not current then
      return nil
    end

    for index = 1, 3 do
      local before = tonumber(previous[index])
      local after = tonumber(current[index])

      if before == nil or after == nil then
        return nil
      end

      maxDelta = math.max(maxDelta, math.abs(after - before))
    end
  end

  return maxDelta
end

local function shouldWriteYawTargets(yawSettings, yawFrame, previousTargets, elapsed, lastWriteElapsed)
  if not yawFrame or not yawFrame.enabled or yawFrame.skipped then
    return false, {
      write = false,
      reason = yawFrame and yawFrame.skipped or "yaw unavailable",
    }
  end

  local interval = math.max(0, tonumber(yawSettings and yawSettings.writeInterval) or 0.1)
  local deadband = math.max(0, tonumber(yawSettings and yawSettings.writeDeadband) or 0.01)
  local delta = yawTargetDelta(previousTargets, yawFrame)

  if not previousTargets or lastWriteElapsed == nil then
    return true, {
      write = true,
      reason = "first_write",
      delta = delta,
      interval = interval,
      deadband = deadband,
    }
  end

  local elapsedSinceWrite = (tonumber(elapsed) or 0) - (tonumber(lastWriteElapsed) or 0)
  local due = interval <= 0 or elapsedSinceWrite >= interval
  local changed = delta == nil or delta >= deadband

  if due and changed then
    return true, {
      write = true,
      reason = "due_changed",
      delta = delta,
      elapsedSinceWrite = elapsedSinceWrite,
      interval = interval,
      deadband = deadband,
    }
  end

  return false, {
    write = false,
    reason = due and "deadband" or "interval",
    delta = delta,
    elapsedSinceWrite = elapsedSinceWrite,
    interval = interval,
    deadband = deadband,
  }
end

local function skippedYawWriteResult(yawWrite)
  return {
    applied = false,
    skipped = yawWrite and yawWrite.reason or "write skipped",
    write = copyPlain(yawWrite),
  }
end

local function clearGyroTargets(gyroDevices)
  local results = {}
  local tasks = {}

  for _, role in ipairs(ROLE_ORDER) do
    local device = gyroDevices and gyroDevices[role]

    if device then
      local roleName = role
      table.insert(tasks, function()
        results[roleName] = callSetter(device.object, "clearManualTarget")
      end)
    end
  end

  if #tasks > 0 then
    parallel.waitForAll(unpack(tasks))
  end

  return results
end

local function pressedControls(control)
  local pressed = {}

  for _, name in ipairs({ "shift", "space", "w", "a", "s", "d", "q", "e", "k" }) do
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
    type = control.type,
    synthetic = control.synthetic == true,
    pulseActive = control.pulseActive == true,
    pulseSeconds = control.pulseSeconds,
    throttle = control.throttle,
    throttlePower = control.throttlePower,
    axis1 = control.axis1,
    axis2 = control.axis2,
    yaw = control.yaw,
    rawAxis1Target = control.rawAxis1Target,
    rawAxis2Target = control.rawAxis2Target,
    rawThrottlePower = control.rawThrottlePower,
    rawYaw = control.rawYaw,
    throttleMode = control.throttleMode,
    heldThrottlePower = control.heldThrottlePower,
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
    rate1 = mixed.rate1,
    rate2 = mixed.rate2,
    yawRate = mixed.yawRate,
    rawRate1 = mixed.rawRate1,
    rawRate2 = mixed.rawRate2,
    rawYawRate = mixed.rawYawRate,
    rawError1 = mixed.rawError1,
    rawError2 = mixed.rawError2,
    measured1 = mixed.measured1,
    measured2 = mixed.measured2,
    target1 = mixed.target1,
    target2 = mixed.target2,
    rawControlPower1 = mixed.rawControlPower1,
    rawControlPower2 = mixed.rawControlPower2,
    rawControlRpm1 = mixed.rawControlRpm1,
    rawControlRpm2 = mixed.rawControlRpm2,
    controlPower1 = mixed.controlPower1,
    controlPower2 = mixed.controlPower2,
    controlRpm1 = mixed.controlRpm1,
    controlRpm2 = mixed.controlRpm2,
    error1 = mixed.error1,
    error2 = mixed.error2,
    rawCorrection1 = mixed.rawCorrection1,
    rawCorrection2 = mixed.rawCorrection2,
    rawCorrection1Rpm = mixed.rawCorrection1Rpm,
    rawCorrection2Rpm = mixed.rawCorrection2Rpm,
    correction1 = mixed.correction1,
    correction2 = mixed.correction2,
    correction1Rpm = mixed.correction1Rpm,
    correction2Rpm = mixed.correction2Rpm,
    correctionLimited = mixed.correctionLimited == true,
    basePowerBeforeTilt = mixed.basePowerBeforeTilt,
    baseRpmBeforeTilt = mixed.baseRpmBeforeTilt,
    throttleRpm = mixed.throttleRpm,
    tiltCompensationPower = mixed.tiltCompensationPower,
    tiltCompensation = copyPlain(mixed.tiltCompensation),
    basePower = mixed.basePower,
    baseRpm = mixed.baseRpm,
    rawPower = copyPlain(mixed.rawPower),
    power = copyPlain(mixed.power),
    rawTargetRpm = copyPlain(mixed.rawTargetRpm),
    targetRpm = copyPlain(mixed.targetRpm),
    desaturation = copyPlain(mixed.desaturation),
    desiredSignals = copyPlain(mixed.desiredSignals),
    signals = copyPlain(mixed.signals),
    outputs = copyPlain(mixed.outputs),
    displayValues = copyPlain(mixed.displayValues),
    actuator = copyPlain(mixed.actuator),
  }
end

local function hzFromInterval(interval)
  interval = tonumber(interval) or 0
  if interval <= 0 then
    return 0
  end

  return 1 / interval
end

local function emptyTimingHealth(settings)
  return {
    targetHz = hzFromInterval(settings and settings.interval),
    actualHz = 0,
    rollingActualHz = 0,
    framesRun = 0,
    missedFrames = 0,
    deadlineMisses = 0,
    avgFrameSeconds = 0,
    maxFrameSeconds = 0,
    lastFrameSeconds = 0,
    lastMissed = false,
    rollingMissedFrames = 0,
  }
end

local function outputDelta(previous, current)
  local maxDelta = nil

  for _, role in ipairs(ROLE_ORDER) do
    local before = tonumber(previous and previous[role])
    local after = tonumber(current and current[role])

    if before == nil or after == nil then
      return nil
    end

    maxDelta = math.max(maxDelta or 0, math.abs(after - before))
  end

  return maxDelta or 0
end

local function shouldWriteActuators(settings, outputs, previousOutputs, elapsed, lastWriteElapsed)
  if not settings or settings.type ~= "rotation_speed" then
    return true, {
      write = true,
      reason = "every_frame",
    }
  end

  local interval = math.max(0, tonumber(settings.writeInterval) or 0)
  local deadband = math.max(0, tonumber(settings.writeDeadbandRpm) or 0)
  local delta = outputDelta(previousOutputs, outputs)

  if not previousOutputs or lastWriteElapsed == nil then
    return true, {
      write = true,
      reason = "first_write",
      delta = delta,
      interval = interval,
      deadband = deadband,
    }
  end

  local elapsedSinceWrite = (tonumber(elapsed) or 0) - (tonumber(lastWriteElapsed) or 0)
  local due = interval <= 0 or elapsedSinceWrite >= interval
  local changed = delta == nil or delta >= deadband

  if due and changed then
    return true, {
      write = true,
      reason = "due_changed",
      delta = delta,
      elapsedSinceWrite = elapsedSinceWrite,
      interval = interval,
      deadband = deadband,
    }
  end

  return false, {
    write = false,
    reason = due and "deadband" or "interval",
    delta = delta,
    elapsedSinceWrite = elapsedSinceWrite,
    interval = interval,
    deadband = deadband,
  }
end

local function updateTimingSummary(timing, frameTiming, recentFrames)
  local total = tonumber(frameTiming.total) or 0
  local finishedAt = tonumber(frameTiming.finishedAt)
    or tonumber(frameTiming.startedAt)
    or 0
  local missed = frameTiming.missed == true

  timing.framesRun = (tonumber(timing.framesRun) or 0) + 1
  timing.totalFrameSeconds = (tonumber(timing.totalFrameSeconds) or 0) + total
  timing.avgFrameSeconds = timing.totalFrameSeconds / timing.framesRun
  timing.maxFrameSeconds = math.max(tonumber(timing.maxFrameSeconds) or 0, total)

  if missed then
    timing.missedFrames = (tonumber(timing.missedFrames) or 0) + 1
    timing.deadlineMisses = (tonumber(timing.deadlineMisses) or 0) + 1
  else
    timing.missedFrames = tonumber(timing.missedFrames) or 0
    timing.deadlineMisses = tonumber(timing.deadlineMisses) or 0
  end

  if finishedAt > 0 then
    timing.actualHz = timing.framesRun / finishedAt
  else
    timing.actualHz = 0
  end

  table.insert(recentFrames, {
    startedAt = tonumber(frameTiming.startedAt) or finishedAt,
    total = total,
    missed = missed,
  })
  while #recentFrames > TIMING_WINDOW do
    table.remove(recentFrames, 1)
  end

  local rollingActualHz = timing.actualHz
  if #recentFrames >= 2 then
    local span = recentFrames[#recentFrames].startedAt - recentFrames[1].startedAt
    if span > 0 then
      rollingActualHz = (#recentFrames - 1) / span
    end
  end

  local rollingMissedFrames = 0
  for _, item in ipairs(recentFrames) do
    if item.missed then
      rollingMissedFrames = rollingMissedFrames + 1
    end
  end

  timing.targetHz = timing.targetHz or hzFromInterval(timing.interval)
  timing.rollingActualHz = rollingActualHz
  timing.rollingMissedFrames = rollingMissedFrames

  return {
    targetHz = timing.targetHz,
    actualHz = timing.actualHz,
    rollingActualHz = timing.rollingActualHz,
    framesRun = timing.framesRun,
    missedFrames = timing.missedFrames,
    deadlineMisses = timing.deadlineMisses,
    avgFrameSeconds = timing.avgFrameSeconds,
    maxFrameSeconds = timing.maxFrameSeconds,
    lastFrameSeconds = total,
    lastMissed = missed,
    rollingMissedFrames = rollingMissedFrames,
  }
end

local function compactStabilizeFrame(frame)
  return {
    index = frame.index,
    elapsed = frame.elapsed,
    timing = copyPlain(frame.timing),
    dryRun = frame.dryRun == true,
    aborted = frame.aborted == true,
    abortReason = frame.abortReason,
    killSwitch = copyPlain(frame.killSwitch),
    controller = compactControllerFrame(frame.controller),
    mixed = compactMixedFrame(frame.mixed),
    actuatorWrite = copyPlain(frame.actuatorWrite),
    setResults = copyPlain(frame.setResults),
    yaw = copyPlain(frame.yaw),
    yawSetResults = copyPlain(frame.yawSetResults),
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

function flightControl.stabilize(config, options)
  local scan, router, routerName = loadContext(config)
  local gimbal = findGimbal(scan, router)
  local settings = stabilizeConfig(config, options)
  local actuatorContext = actuators.open(scan, router, settings.actuator)
  settings.actuator = actuatorContext.settings
  actuators.assertReady(actuatorContext)
  local rotorDevices, rotorErrors = wrapOptionalRoleDevices(scan, router, "rotorBearing")
  local gyroDevices, gyroErrors = wrapManualGyroDevices(scan, router)
  local sensors, sensorErrors = wrapOptionalSensors(scan, router)
  local killSwitchRouter, killSwitchRouterName = nil, nil
  if settings.killSwitch
      and settings.killSwitch.enabled
      and settings.killSwitch.source == "router" then
    killSwitchRouter, killSwitchRouterName = findRedstoneRouter()
  end
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
    baseRpm = settings.actuator and settings.actuator.baseRpm,
  }
  report.settings = copyPlain(settings)
  report.attitudeTarget = {
    angles = { 0, 0 },
    source = "gimbal_zero",
  }
  report.gimbal = {
    side = gimbal.side,
    source = gimbal.source,
    coord = gimbal.coord,
  }
  report.hud = hud.describe(hudContext)
  report.controller = controller.describe(controllerContext)
  report.recoveryTest = copyPlain(options.recoveryTest)
  report.killSwitch = copyPlain(settings.killSwitch)
  if killSwitchRouterName then
    report.killSwitch.routerName = killSwitchRouterName
  end
  report.nixies = displays.describe(nixieContext)
  report.actuators = actuators.describe(actuatorContext)
  report.rotorTelemetry = {
    errors = copyPlain(rotorErrors),
  }
  report.gyroYaw = {
    enabled = settings.yaw and settings.yaw.enabled == true,
    errors = copyPlain(gyroErrors),
  }
  report.sensors = {
    navigation = sensors.navigation and {
      source = sensors.navigation.source,
      coord = copyPlain(sensors.navigation.coord),
    } or nil,
    altitude = sensors.altitude and {
      source = sensors.altitude.source,
      coord = copyPlain(sensors.altitude.coord),
    } or nil,
    errors = copyPlain(sensorErrors),
  }
  report.frames = {}
  report.timing = {
    requestedSeconds = settings.seconds,
    forever = settings.forever,
    interval = settings.interval,
    targetHz = hzFromInterval(settings.interval),
    actualHz = 0,
    rollingActualHz = 0,
    rollingWindow = TIMING_WINDOW,
    framesRun = 0,
    missedFrames = 0,
    deadlineMisses = 0,
    rollingMissedFrames = 0,
    avgFrameSeconds = 0,
    maxFrameSeconds = 0,
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
      heldThrottlePower = 0,
    }
    local previousActuatorOutputs = nil
    local previousActuatorWriteElapsed = nil
    local previousYawTargets = nil
    local previousYawWriteElapsed = nil
    local recentTimingFrames = {}
    local previousTimingHealth = emptyTimingHealth(settings)

    while true do
      if active and deadline and frameIndex > 1 and os.clock() >= deadline then
        report.timing.stopReason = "duration_clock"
        break
      end

      local frameStartClock = os.clock()
      local timing = {
        scheduledAt = nextFrameTime - startTime,
        startedAt = frameStartClock - startTime,
        lateness = math.max(0, frameStartClock - nextFrameTime),
        targetInterval = settings.interval,
        phases = {},
        health = copyPlain(previousTimingHealth),
      }

      local phaseStart = os.clock()
      local state = readGimbal(gimbal)
      timing.phases.gimbal = os.clock() - phaseStart

      local elapsed = os.clock() - startTime
      local dt = previousMotion and (elapsed - previousMotion.elapsed) or settings.interval
      timing.dt = dt

      phaseStart = os.clock()
      local rawControl = recoveryControl(options.recoveryTest, elapsed) or controller.sample(controllerContext)
      local controlContext = options.recoveryTest and testControlContext or controllerContext
      local control = smoothControl(controlContext, rawControl, previousControl, dt)
      timing.phases.controller = os.clock() - phaseStart

      phaseStart = os.clock()
      local mixed = mixerSignals(settings, state, control, signalResiduals)
      local attitudeExceeded = math.abs(mixed.error1) > settings.maxAttitudeDelta
          or math.abs(mixed.error2) > settings.maxAttitudeDelta
      timing.phases.mix = os.clock() - phaseStart

      phaseStart = os.clock()
      local killSwitch = readKillSwitch(settings, control, killSwitchRouter, killSwitchRouterName)
      timing.phases.killSwitch = os.clock() - phaseStart

      phaseStart = os.clock()
      local yawFrame = buildYawFrame(settings, state, scan, sensors, gyroDevices, control)
      timing.phases.yaw = os.clock() - phaseStart

      local frame = {
        index = frameIndex,
        elapsed = elapsed,
        timing = timing,
        state = state,
        killSwitch = killSwitch,
        controller = control,
        mixed = mixed,
        yaw = yawFrame,
      }

      phaseStart = os.clock()
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
        local writeActuators, actuatorWrite = shouldWriteActuators(
          settings.actuator,
          mixed.outputs,
          previousActuatorOutputs,
          frame.elapsed,
          previousActuatorWriteElapsed
        )
        local writeYawTargets, yawWrite = shouldWriteYawTargets(
          settings.yaw,
          yawFrame,
          previousYawTargets,
          frame.elapsed,
          previousYawWriteElapsed
        )
        frame.actuatorWrite = actuatorWrite
        frame.yaw.write = yawWrite

        if writeActuators and writeYawTargets then
          parallel.waitForAll(
            function()
              frame.setResults = actuators.apply(actuatorContext, mixed.outputs)
            end,
            function()
              frame.yawSetResults = applyYawTargets(gyroDevices, yawFrame, true)
            end
          )
        elseif writeActuators then
          frame.setResults = actuators.apply(actuatorContext, mixed.outputs)
          frame.yawSetResults = skippedYawWriteResult(yawWrite)
        elseif writeYawTargets then
          frame.yawSetResults = applyYawTargets(gyroDevices, yawFrame, true)
        else
          frame.yawSetResults = skippedYawWriteResult(yawWrite)
        end

        if writeActuators then
          previousActuatorOutputs = copyPlain(mixed.outputs)
          previousActuatorWriteElapsed = frame.elapsed
        end

        if writeYawTargets then
          previousYawTargets = yawTargetsFromFrame(yawFrame)
          previousYawWriteElapsed = frame.elapsed
        end
      else
        frame.dryRun = true
        frame.yawSetResults = applyYawTargets(gyroDevices, yawFrame, false)
      end
      timing.phases.applySignals = os.clock() - phaseStart

      local forceDisplay = attitudeExceeded or killSwitch.triggered
      phaseStart = os.clock()
      frame.nixies = updateNixies(frame, forceDisplay)
      timing.phases.nixies = os.clock() - phaseStart

      phaseStart = os.clock()
      if hud.shouldUpdate(hudContext, frame, forceDisplay) then
        frame.telemetry = readRotorTelemetry(rotorDevices)
        frame.telemetry.actuators = actuators.readTelemetry(actuatorContext)
        frame.telemetry.sensors = readSensorTelemetry(sensors)
      end
      timing.phases.telemetry = os.clock() - phaseStart

      phaseStart = os.clock()
      frame.hud = hud.update(hudContext, frame, settings, active, forceDisplay)
      timing.phases.hud = os.clock() - phaseStart

      phaseStart = os.clock()
      local compactFrame = nil
      if settings.reportFrameLimit == 0 then
        report.timing.framesDropped = (report.timing.framesDropped or 0) + 1
      else
        compactFrame = compactStabilizeFrame(frame)
        table.insert(report.frames, compactFrame)
        if #report.frames > settings.reportFrameLimit then
          table.remove(report.frames, 1)
          report.timing.framesDropped = (report.timing.framesDropped or 0) + 1
        end
      end
      timing.phases.reportFrame = os.clock() - phaseStart

      local frameFinishClock = os.clock()
      timing.finishedAt = frameFinishClock - startTime
      timing.total = frameFinishClock - frameStartClock
      timing.missed = timing.total > settings.interval + TIMING_EPSILON
      local timingHealth = updateTimingSummary(report.timing, timing, recentTimingFrames)
      timing.summary = copyPlain(timingHealth)
      previousTimingHealth = timingHealth
      if compactFrame then
        compactFrame.timing = copyPlain(timing)
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
        heldThrottlePower = control.heldThrottlePower,
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

  local function runWithControllerPump()
    if controller.needsPump(controllerContext) then
      parallel.waitForAny(
        function()
          controller.pump(controllerContext)
        end,
        runLoop
      )
    else
      runLoop()
    end
  end

  local ok, result = pcall(runWithControllerPump)
  if active and settings.brakeOnExit then
    report.brakeOnExit = actuators.brake(actuatorContext)
    if settings.nixiesEnabled then
      report.nixieBrakeOnExit = displays.updateSignals(nixieContext, actuators.brakeOutputs(settings.actuator))
    end
  end

  if active and settings.yaw and settings.yaw.enabled and settings.yaw.clearOnExit then
    report.gyroYaw.clearOnExit = clearGyroTargets(gyroDevices)
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

function flightControl.probeKillSwitch(config, options)
  options = options or {}
  local settings = stabilizeConfig(config, options)
  local controllerOptions = copyPlain(options)
  controllerOptions.controller = true
  local controllerOk, controllerContextOrError = pcall(controller.open, config, controllerOptions)
  local controllerContext = controllerOk and controllerContextOrError or {
    enabled = false,
    error = tostring(controllerContextOrError),
  }
  local killSwitchRouter, killSwitchRouterName = nil, nil

  if settings.killSwitch
      and settings.killSwitch.enabled
      and settings.killSwitch.source == "router" then
    killSwitchRouter, killSwitchRouterName = findRedstoneRouter()
  end

  local seconds = tonumber(options.seconds) or 10
  local interval = tonumber(options.interval) or 0.2
  local startTime = os.clock()
  local deadline = startTime + seconds
  local report = {
    kind = "aircraft_killswitch_probe",
    createdAt = now(),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    seconds = seconds,
    interval = interval,
    killSwitch = copyPlain(settings.killSwitch),
    controller = controller.describe(controllerContext),
    frames = {},
  }
  if not controllerOk then
    report.controller.error = tostring(controllerContextOrError)
  end

  if killSwitchRouterName then
    report.killSwitch.routerName = killSwitchRouterName
  end

  print("Aircraft kill switch probe")
  print("source=" .. tostring(settings.killSwitch and settings.killSwitch.source))
  print("key=" .. tostring(settings.killSwitch and settings.killSwitch.key))
  print("Press K or toggle the physical kill switch. Ctrl+T stops.")

  local function runProbeLoop()
    repeat
      local control = controllerOk and controller.sample(controllerContext) or {
        enabled = false,
        error = tostring(controllerContextOrError),
        reads = {},
      }
      local killSwitch = readKillSwitch(settings, control, killSwitchRouter, killSwitchRouterName)
      local frame = {
        elapsed = os.clock() - startTime,
        controller = compactControllerFrame(control),
        killSwitch = copyPlain(killSwitch),
      }

      table.insert(report.frames, frame)
      print(
        string.format("%.1f", frame.elapsed)
          .. " triggered=" .. tostring(killSwitch.triggered)
          .. " by=" .. tostring(killSwitch.triggeredBy or "none")
          .. " ok=" .. tostring(killSwitch.ok)
      )

      sleep(interval)
    until os.clock() >= deadline
  end

  if controllerOk and controller.needsPump(controllerContext) then
    parallel.waitForAny(
      function()
        controller.pump(controllerContext)
      end,
      runProbeLoop
    )
  else
    runProbeLoop()
  end

  local path = "/aircraft_killswitch.txt"
  reporting.save(report, path, config, { localReport = false })
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  print("Aircraft kill switch report: " .. (config.sendWebhook ~= false and "webhook" or "webhook disabled"))
  return report
end

return flightControl
