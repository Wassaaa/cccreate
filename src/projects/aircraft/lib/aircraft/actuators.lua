local coords = require("lib.aircraft.coords")

local actuators = {}

local ROLE_ORDER = {
  "front_left",
  "front_right",
  "rear_left",
  "rear_right",
}

actuators.ROLE_ORDER = ROLE_ORDER

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
  value = tonumber(value) or 0

  if value < minValue then
    return minValue
  elseif value > maxValue then
    return maxValue
  end

  return value
end

local function round(value)
  value = tonumber(value) or 0

  if value >= 0 then
    return math.floor(value + 0.5)
  end

  return math.ceil(value - 0.5)
end

local function quantize(value, maxValue, residuals, key)
  local clamped = clamp(value, 0, maxValue)
  local adjusted = clamped

  if residuals and key then
    adjusted = adjusted + (tonumber(residuals[key]) or 0)
  end

  local output = clamp(round(adjusted), 0, maxValue)

  if residuals and key then
    residuals[key] = adjusted - output
  end

  return output
end

local function normalizeName(value)
  local text = string.lower(tostring(value or ""))
  text = string.gsub(text, "%s+", "_")
  text = string.gsub(text, "-", "_")
  return text
end

function actuators.normalizeType(value)
  local text = normalizeName(value)

  if text == "" or text == "redstone" or text == "signal" or text == "redstone_signal" then
    return "redstone_signal"
  elseif text == "speed"
      or text == "rotation_speed"
      or text == "target_speed"
      or text == "rotational_speed"
      or text == "rotation_speed_controller"
      or text == "rsc" then
    return "rotation_speed"
  end

  error("actuator type must be redstone_signal or rotation_speed", 0)
end

local function signValue(value)
  local number = tonumber(value)
  if number and number < 0 then
    return -1
  end

  return 1
end

local function roleSignsFromConfig(value)
  if type(value) ~= "table" then
    return nil
  end

  local result = {}
  local any = false
  for _, role in ipairs(ROLE_ORDER) do
    if value[role] ~= nil then
      result[role] = signValue(value[role])
      any = true
    end
  end

  return any and result or nil
end

local function dot(left, right)
  return (tonumber(left and left.x) or 0) * (tonumber(right and right.x) or 0)
    + (tonumber(left and left.y) or 0) * (tonumber(right and right.y) or 0)
    + (tonumber(left and left.z) or 0) * (tonumber(right and right.z) or 0)
end

local function coordDelta(toCoord, fromCoord)
  if type(toCoord) ~= "table" or type(fromCoord) ~= "table" then
    return nil
  end

  return {
    x = (tonumber(toCoord.x) or 0) - (tonumber(fromCoord.x) or 0),
    y = (tonumber(toCoord.y) or 0) - (tonumber(fromCoord.y) or 0),
    z = (tonumber(toCoord.z) or 0) - (tonumber(fromCoord.z) or 0),
  }
end

local function inferRotationSpeedRoleSigns(scan, roleFamily)
  local orientation = scan and scan.orientation
  local roles = orientation and orientation.roles
  local speedRoles = roles and roles[roleFamily or "speedActuator"]
  local rotorRoles = roles and roles.rotorBearing
  local front = orientation and orientation.frontVector
  local left = orientation and orientation.leftVector
  local signs = {}
  local sources = {}
  local any = false

  if not speedRoles or not rotorRoles or not front or not left then
    return nil, nil
  end

  for _, role in ipairs(ROLE_ORDER) do
    local speedCoord = speedRoles[role] and speedRoles[role].coord
    local rotorCoord = rotorRoles[role] and rotorRoles[role].coord
    local delta = coordDelta(rotorCoord, speedCoord)

    if delta then
      local frontOffset = dot(delta, front)
      local leftOffset = dot(delta, left)
      local sign = nil
      local source = nil

      if math.abs(frontOffset) >= math.abs(leftOffset) and math.abs(frontOffset) > 0 then
        sign = frontOffset < 0 and -1 or 1
        source = "rotor_offset_front"
      elseif math.abs(leftOffset) > 0 then
        sign = leftOffset < 0 and -1 or 1
        source = "rotor_offset_left"
      end

      if sign then
        signs[role] = sign
        sources[role] = {
          source = source,
          sign = sign,
          delta = delta,
          frontOffset = frontOffset,
          leftOffset = leftOffset,
        }
        any = true
      end
    end
  end

  return any and signs or nil, any and sources or nil
end

function actuators.settings(config, options)
  config = config or {}
  options = options or {}

  local actuatorConfig = config.actuator or {}
  local typeName = actuators.normalizeType(options.actuatorType or actuatorConfig.type or "redstone_signal")
  local maxSignal = tonumber(config.absoluteSignalMax) or 15
  if maxSignal <= 0 then
    maxSignal = 15
  end

  if typeName == "rotation_speed" then
    local speedConfig = actuatorConfig.rotationSpeed or actuatorConfig.speed or {}
    local maxPower = tonumber(speedConfig.maxPower) or tonumber(actuatorConfig.maxPower) or maxSignal
    if maxPower <= 0 then
      maxPower = maxSignal
    end
    if maxPower <= 0 then
      maxPower = 15
    end

    local idleRpm = tonumber(speedConfig.idleRpm) or 0
    local powerRpm = math.abs(tonumber(speedConfig.powerRpm) or 256)
    local baseRpm = tonumber(options.baseRpm)
      or tonumber(speedConfig.baseRpm)
      or (powerRpm * ((tonumber(config.stabilize and config.stabilize.basePower) or 0) / maxPower))
    local maxTargetRpm = math.abs(tonumber(speedConfig.maxTargetRpm)
      or math.max(math.abs(tonumber(speedConfig.minRpm) or -256), math.abs(tonumber(speedConfig.maxRpm) or 256)))

    return {
      type = "rotation_speed",
      roleFamily = tostring(speedConfig.roleFamily or actuatorConfig.roleFamily or "speedActuator"),
      maxPower = maxPower,
      outputLabel = "rpm",
      outputKind = "targetSpeed",
      setter = tostring(speedConfig.setter or speedConfig.method or "setTargetSpeed"),
      getter = tostring(speedConfig.getter or speedConfig.readMethod or "getTargetSpeed"),
      fallbackSetters = { "setTargetSpeed", "setGeneratedSpeed", "setSpeed" },
      fallbackGetters = { "getTargetSpeed", "getGeneratedSpeed", "getOutputSpeed", "getSpeed" },
      idleRpm = idleRpm,
      powerRpm = powerRpm,
      brakeRpm = tonumber(speedConfig.brakeRpm) or idleRpm,
      minRpm = tonumber(speedConfig.minRpm) or -256,
      maxRpm = tonumber(speedConfig.maxRpm) or 256,
      sign = signValue(speedConfig.sign),
      autoRoleSigns = speedConfig.autoRoleSigns ~= false,
      roleSigns = roleSignsFromConfig(speedConfig.roleSigns),
      round = speedConfig.round == true,
      controlMode = "rpm_native",
      baseRpm = baseRpm,
      throttleRpmPerPower = tonumber(options.throttleRpmPerPower)
        or tonumber(speedConfig.throttleRpmPerPower)
        or (powerRpm / maxPower),
      axisPowerRpmPerPower = tonumber(options.axisPowerRpmPerPower)
        or tonumber(speedConfig.axisPowerRpmPerPower),
      axis1KpRpm = tonumber(options.axis1KpRpm)
        or tonumber(options.kpRpm)
        or tonumber(speedConfig.axis1KpRpm)
        or tonumber(speedConfig.axis1Kp)
        or 0,
      axis1KdRpm = tonumber(options.axis1KdRpm)
        or tonumber(options.kdRpm)
        or tonumber(speedConfig.axis1KdRpm)
        or tonumber(speedConfig.axis1Kd)
        or 0,
      axis2KpRpm = tonumber(options.axis2KpRpm)
        or tonumber(options.kpRpm)
        or tonumber(speedConfig.axis2KpRpm)
        or tonumber(speedConfig.axis2Kp)
        or 0,
      axis2KdRpm = tonumber(options.axis2KdRpm)
        or tonumber(options.kdRpm)
        or tonumber(speedConfig.axis2KdRpm)
        or tonumber(speedConfig.axis2Kd)
        or 0,
      axis1TrimRpm = tonumber(options.axis1TrimRpm) or tonumber(speedConfig.axis1TrimRpm) or 0,
      axis2TrimRpm = tonumber(options.axis2TrimRpm) or tonumber(speedConfig.axis2TrimRpm) or 0,
      maxCorrectionRpm = math.abs(tonumber(options.maxCorrectionRpm) or tonumber(speedConfig.maxCorrectionRpm) or 0),
      minTargetRpm = math.max(0, tonumber(options.minTargetRpm) or tonumber(speedConfig.minTargetRpm) or 0),
      maxTargetRpm = math.abs(tonumber(options.maxTargetRpm) or maxTargetRpm),
      desaturateHeadroomRpm = tonumber(speedConfig.desaturateHeadroomRpm),
      writeInterval = math.max(0, tonumber(options.writeInterval) or tonumber(speedConfig.writeInterval) or 0.1),
      writeDeadbandRpm = math.max(0, tonumber(options.writeDeadbandRpm) or tonumber(speedConfig.writeDeadbandRpm) or 0.5),
    }
  end

  local redstoneConfig = actuatorConfig.redstoneSignal or actuatorConfig.redstone or {}
  local brakeSignal = tonumber(config.brakeSignal) or maxSignal

  return {
    type = "redstone_signal",
    roleFamily = tostring(redstoneConfig.roleFamily or actuatorConfig.roleFamily or "scalarActuator"),
    maxPower = maxSignal,
    maxSignal = maxSignal,
    brakeSignal = clamp(brakeSignal, 0, maxSignal),
    outputLabel = "signal",
    outputKind = "redstoneSignal",
    setter = tostring(redstoneConfig.setter or redstoneConfig.method or "setSignal"),
    getter = tostring(redstoneConfig.getter or redstoneConfig.readMethod or "getSignal"),
    fallbackSetters = { "setSignal" },
    fallbackGetters = { "getSignal", "getOutputSpeed", "getSpeed" },
  }
end

local function containsMethod(object, method)
  return method and type(object and object[method]) == "function"
end

local function resolveMethod(object, preferred, fallbacks)
  if containsMethod(object, preferred) then
    return preferred
  end

  for _, method in ipairs(fallbacks or {}) do
    if containsMethod(object, method) then
      return method
    end
  end

  return nil
end

local function wrapMapped(router, mapped, label)
  local coord = mapped and mapped.coord
  if not coord then
    return nil, "missing " .. tostring(label) .. " coord"
  end

  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok then
    return nil, "wrap error at " .. coords.label(coord) .. ": " .. tostring(objectOrError)
  end

  if not objectOrError then
    return nil, "missing at " .. coords.label(coord)
  end

  return {
    coord = copyPlain(coord),
    object = objectOrError,
  }, nil
end

function actuators.open(scan, router, settings)
  settings = settings or actuators.settings({})
  local effectiveSettings = copyPlain(settings)

  if effectiveSettings.type == "rotation_speed"
      and effectiveSettings.autoRoleSigns ~= false
      and not effectiveSettings.roleSigns then
    local inferred, sources = inferRotationSpeedRoleSigns(scan, effectiveSettings.roleFamily)
    effectiveSettings.roleSigns = inferred
    effectiveSettings.roleSignSources = sources
  end

  local context = {
    settings = effectiveSettings,
    devices = {},
    errors = {},
  }
  local roles = scan
    and scan.orientation
    and scan.orientation.roles
    and scan.orientation.roles[effectiveSettings.roleFamily]

  if not roles then
    context.skipped = "no " .. tostring(effectiveSettings.roleFamily) .. " role map"
    return context
  end

  for _, role in ipairs(ROLE_ORDER) do
    local mapped = roles[role]
    local device, errorMessage = wrapMapped(router, mapped, role)

    if device then
      local setter = resolveMethod(device.object, effectiveSettings.setter, effectiveSettings.fallbackSetters)
      if not setter then
        context.errors[role] = "missing supported setter for " .. tostring(effectiveSettings.type)
      else
        device.role = role
        device.setter = setter
        device.getter = resolveMethod(device.object, effectiveSettings.getter, effectiveSettings.fallbackGetters)
        context.devices[role] = device
      end
    else
      context.errors[role] = errorMessage
    end
  end

  return context
end

function actuators.assertReady(context)
  if context.skipped then
    error("No actuator role map for " .. tostring(context.settings and context.settings.roleFamily) .. ": " .. tostring(context.skipped), 0)
  end

  for _, role in ipairs(ROLE_ORDER) do
    if not context.devices[role] then
      error("Missing actuator role " .. role .. ": " .. tostring(context.errors and context.errors[role] or "not mapped"), 0)
    end
  end
end

local function speedForPower(settings, power, role)
  local fraction = clamp(power, 0, settings.maxPower) / settings.maxPower
  local roleSign = settings.roleSigns and settings.roleSigns[role] or 1
  local speed = (tonumber(settings.idleRpm) or 0)
    + (tonumber(settings.sign) or 1) * roleSign * (tonumber(settings.powerRpm) or 0) * fraction
  speed = clamp(speed, tonumber(settings.minRpm) or -256, tonumber(settings.maxRpm) or 256)

  if settings.round ~= false then
    speed = round(speed)
  end

  return speed
end

function actuators.outputsFromPower(settings, powerByRole, residuals)
  local frame = {
    type = settings.type,
    roleFamily = settings.roleFamily,
    outputLabel = settings.outputLabel,
    outputKind = settings.outputKind,
    method = settings.setter,
    outputs = {},
    displayValues = {},
  }

  if settings.type == "rotation_speed" then
    frame.targetSpeeds = frame.outputs
    frame.desiredTargetSpeeds = {}
    frame.roleSigns = copyPlain(settings.roleSigns)
    frame.roleSignSources = copyPlain(settings.roleSignSources)

    for _, role in ipairs(ROLE_ORDER) do
      local power = tonumber(powerByRole and powerByRole[role]) or 0
      local target = speedForPower(settings, power, role)
      frame.outputs[role] = target
      frame.displayValues[role] = target
      frame.desiredTargetSpeeds[role] = target
    end

    return frame
  end

  frame.signals = frame.outputs
  frame.desiredSignals = {}

  for _, role in ipairs(ROLE_ORDER) do
    local power = tonumber(powerByRole and powerByRole[role]) or 0
    local desired = clamp((tonumber(settings.brakeSignal) or 0) - power, 0, settings.maxSignal)
    local signal = quantize(desired, settings.maxSignal, residuals, role)

    frame.desiredSignals[role] = desired
    frame.outputs[role] = signal
    frame.displayValues[role] = signal
  end

  return frame
end

local function signedSpeed(settings, localRpm, role)
  local roleSign = settings.roleSigns and settings.roleSigns[role] or 1
  local speed = (tonumber(settings.sign) or 1) * roleSign * (tonumber(localRpm) or 0)
  speed = clamp(speed, tonumber(settings.minRpm) or -256, tonumber(settings.maxRpm) or 256)

  if settings.round == true then
    speed = round(speed)
  end

  return speed
end

function actuators.outputsFromRpm(settings, rpmByRole)
  local frame = {
    type = settings.type,
    roleFamily = settings.roleFamily,
    outputLabel = settings.outputLabel,
    outputKind = settings.outputKind,
    method = settings.setter,
    outputs = {},
    displayValues = {},
    targetSpeeds = {},
    desiredTargetSpeeds = {},
    localTargetRpm = {},
    roleSigns = copyPlain(settings.roleSigns),
    roleSignSources = copyPlain(settings.roleSignSources),
    controlMode = "rpm_native",
  }

  local minTarget = math.max(0, tonumber(settings.minTargetRpm) or 0)
  local maxTarget = math.max(minTarget, tonumber(settings.maxTargetRpm) or 256)

  for _, role in ipairs(ROLE_ORDER) do
    local localTarget = clamp(tonumber(rpmByRole and rpmByRole[role]) or 0, minTarget, maxTarget)
    local target = signedSpeed(settings, localTarget, role)

    frame.localTargetRpm[role] = localTarget
    frame.outputs[role] = target
    frame.targetSpeeds[role] = target
    frame.desiredTargetSpeeds[role] = target
    frame.displayValues[role] = target
  end

  return frame
end

function actuators.brakeOutputs(settings, roles)
  local outputs = {}
  local selected = roles or ROLE_ORDER
  local value = settings.type == "rotation_speed"
    and clamp(settings.brakeRpm, settings.minRpm, settings.maxRpm)
    or clamp(settings.brakeSignal, 0, settings.maxSignal)

  if settings.type == "rotation_speed" and settings.round ~= false then
    value = round(value)
  end

  for _, role in ipairs(selected) do
    outputs[role] = value
  end

  return outputs
end

local function callSetter(device, value)
  if not containsMethod(device.object, device.setter) then
    return {
      ok = false,
      error = "missing " .. tostring(device.setter),
    }
  end

  local values = { pcall(device.object[device.setter], value) }
  local ok = table.remove(values, 1)

  if not ok then
    return {
      ok = false,
      method = device.setter,
      value = value,
      error = tostring(values[1]),
    }
  end

  return {
    ok = true,
    method = device.setter,
    value = value,
    returns = copyPlain(values),
  }
end

function actuators.apply(context, outputs)
  local results = {}
  local tasks = {}

  for _, role in ipairs(ROLE_ORDER) do
    local device = context.devices[role]
    local value = outputs and outputs[role]

    if device and value ~= nil then
      local roleName = role
      local deviceRef = device
      local outputValue = value
      table.insert(tasks, function()
        results[roleName] = callSetter(deviceRef, outputValue)
      end)
    elseif value ~= nil then
      results[role] = {
        ok = false,
        error = context.errors and context.errors[role] or "missing actuator",
      }
    end
  end

  if #tasks > 0 then
    parallel.waitForAll(unpack(tasks))
  end

  return results
end

function actuators.brake(context, roles)
  return actuators.apply(context, actuators.brakeOutputs(context.settings, roles))
end

local function readGetter(object, method)
  if type(object[method]) ~= "function" then
    return nil
  end

  local values = { pcall(object[method]) }
  local ok = table.remove(values, 1)

  if not ok then
    return {
      ok = false,
      method = method,
      error = tostring(values[1]),
    }
  end

  if #values == 1 then
    return {
      ok = true,
      method = method,
      value = copyPlain(values[1]),
    }
  end

  return {
    ok = true,
    method = method,
    value = copyPlain(values),
  }
end

function actuators.readDevice(device)
  local result = {
    role = device.role,
    coord = copyPlain(device.coord),
    setter = device.setter,
    getter = device.getter,
  }

  if device.getter then
    result.output = readGetter(device.object, device.getter)
  end

  result.targetSpeed = readGetter(device.object, "getTargetSpeed")
  result.speed = readGetter(device.object, "getSpeed")
  result.outputSpeed = readGetter(device.object, "getOutputSpeed")
  result.signal = readGetter(device.object, "getSignal")
  result.shiftLevel = readGetter(device.object, "getShiftLevel")

  return result
end

function actuators.readTelemetry(context)
  local result = {
    type = context.settings and context.settings.type,
    outputLabel = context.settings and context.settings.outputLabel,
    roles = {},
  }

  for _, role in ipairs(ROLE_ORDER) do
    local device = context.devices[role]
    if device then
      result.roles[role] = actuators.readDevice(device)
    elseif context.errors and context.errors[role] then
      result.roles[role] = {
        ok = false,
        error = context.errors[role],
      }
    end
  end

  return result
end

function actuators.readOutputs(context)
  local outputs = {}
  local reads = {}

  for _, role in ipairs(ROLE_ORDER) do
    local device = context.devices[role]

    if device then
      local read = nil
      if device.getter then
        read = readGetter(device.object, device.getter)
      end

      reads[role] = {
        coord = copyPlain(device.coord),
        method = device.getter,
        output = read,
      }

      if type(read) == "table" and read.ok and type(read.value) == "number" then
        outputs[role] = read.value
      end
    elseif context.errors and context.errors[role] then
      reads[role] = {
        ok = false,
        error = context.errors[role],
      }
    end
  end

  return outputs, reads
end

function actuators.describe(context)
  local result = {
    settings = copyPlain(context.settings),
    skipped = context.skipped,
    devices = {},
    errors = copyPlain(context.errors),
  }

  for _, role in ipairs(ROLE_ORDER) do
    local device = context.devices[role]
    if device then
      result.devices[role] = {
        coord = copyPlain(device.coord),
        setter = device.setter,
        getter = device.getter,
      }
    end
  end

  return result
end

return actuators
