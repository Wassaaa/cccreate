local configModel = {}

local ROOT_ORDER = {
  "scan",
  "frontAxis",
  "leftAxis",
  "dryRun",
  "absoluteSignalMax",
  "brakeSignal",
  "actuator",
  "maxAttitudeDelta",
  "statusReadLimit",
  "stabilize",
  "yaw",
  "hold",
  "moveTarget",
  "controller",
  "display",
  "hud",
  "killSwitch",
  "reportPath",
  "sendWebhook",
}

local ORDERS = {
  scan = { "xRadius", "yRadius", "zRadius", "sampleLimit", "errorLimit", "parallelism" },
  actuator = { "type", "roleFamily", "maxPower", "redstoneSignal", "rotationSpeed" },
  actuatorRedstoneSignal = { "roleFamily", "setter", "getter" },
  actuatorRotationSpeed = {
    "roleFamily",
    "setter",
    "getter",
    "idleRpm",
    "powerRpm",
    "brakeRpm",
    "minRpm",
    "maxRpm",
    "sign",
    "autoRoleSigns",
    "roleSigns",
    "round",
    "baseRpm",
    "throttleRpmPerPower",
    "axisPowerRpmPerPower",
    "axis1KpRpm",
    "axis1KdRpm",
    "axis2KpRpm",
    "axis2KdRpm",
    "axis1TrimRpm",
    "axis2TrimRpm",
    "maxCorrectionRpm",
    "minTargetRpm",
    "maxTargetRpm",
    "desaturateHeadroomRpm",
    "writeInterval",
    "writeDeadbandRpm",
    "maxPower",
  },
  roleSigns = { "front_left", "front_right", "rear_left", "rear_right" },
  stabilize = {
    "interval",
    "seconds",
    "basePower",
    "axis1Kp",
    "axis1Kd",
    "axis2Kp",
    "axis2Kd",
    "axis1Trim",
    "axis2Trim",
    "maxCorrection",
    "desaturate",
    "desaturateHeadroom",
    "tiltCompensation",
    "tiltCompensationGain",
    "tiltCompensationMaxPower",
    "signalDither",
    "brakeOnExit",
    "reportFrameLimit",
  },
  yaw = {
    "enabled",
    "rateKd",
    "maxTiltDeg",
    "deadbandDegPerSecond",
    "sign",
    "commandLateral",
    "clearOnExit",
    "writeInterval",
    "writeDeadband",
  },
  hold = {
    "enabled",
    "defaultActive",
    "maxTiltDeg",
    "velocityKp",
    "velocityDeadband",
    "axis1Sign",
    "axis2Sign",
  },
  moveTarget = {
    "enabled",
    "defaultActive",
    "maxVelocity",
    "targetKp",
    "deadband",
    "captureRadius",
    "velocitySlew",
  },
  controller = {
    "enabled",
    "type",
    "threshold",
    "throttleMode",
    "throttlePower",
    "axis1TargetDeg",
    "axis2TargetDeg",
    "axis1Power",
    "axis2Power",
    "targetSlewDegPerSecond",
    "throttleSlewPowerPerSecond",
    "keyMap",
    "bindings",
  },
  bindings = { "shift", "a", "s", "d", "space", "q", "w", "e", "k", "hold", "moveTarget" },
  binding = { "x", "y", "z", "side" },
  display = { "enabled", "stabilizeEnabled", "stabilizeInterval", "absoluteRotorValues", "statusStrip" },
  statusStrip = { "enabled", "x", "y", "z", "axis" },
  hud = { "enabled", "interval", "monitorScale", "monitorName" },
  killSwitch = { "enabled", "source", "side", "activeHigh", "keyEnabled", "key", "binding" },
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

local function set(target, key, value)
  if value ~= nil then
    target[key] = copyPlain(value)
  end
end

local function hasAny(value)
  return type(value) == "table" and next(value) ~= nil
end

local function pick(source, keys)
  local result = {}

  if type(source) ~= "table" then
    return result
  end

  for _, key in ipairs(keys) do
    set(result, key, source[key])
  end

  return result
end

local function normalizeBindings(bindings)
  local result = {}

  if type(bindings) ~= "table" then
    return result
  end

  for _, key in ipairs(ORDERS.bindings) do
    local binding = pick(bindings[key], ORDERS.binding)
    if hasAny(binding) then
      result[key] = binding
    end
  end

  return result
end

function configModel.normalize(config)
  config = config or {}

  local result = {}
  result.scan = pick(config.scan, ORDERS.scan)
  set(result, "frontAxis", config.frontAxis)
  set(result, "leftAxis", config.leftAxis)
  set(result, "dryRun", config.dryRun)
  set(result, "absoluteSignalMax", config.absoluteSignalMax)
  set(result, "brakeSignal", config.brakeSignal)
  result.actuator = pick(config.actuator, ORDERS.actuator)
  result.actuator.redstoneSignal = pick(config.actuator and config.actuator.redstoneSignal, ORDERS.actuatorRedstoneSignal)
  result.actuator.rotationSpeed = pick(config.actuator and config.actuator.rotationSpeed, ORDERS.actuatorRotationSpeed)
  set(result, "maxAttitudeDelta", config.maxAttitudeDelta)
  set(result, "statusReadLimit", config.statusReadLimit)
  result.stabilize = pick(config.stabilize, ORDERS.stabilize)
  result.yaw = pick(config.yaw, ORDERS.yaw)
  result.hold = pick(config.hold, ORDERS.hold)
  result.moveTarget = pick(config.moveTarget, ORDERS.moveTarget)
  result.controller = pick(config.controller, ORDERS.controller)
  result.controller.bindings = normalizeBindings(config.controller and config.controller.bindings)
  result.display = pick(config.display, ORDERS.display)
  result.display.statusStrip = pick(config.display and config.display.statusStrip, ORDERS.statusStrip)
  result.hud = pick(config.hud, ORDERS.hud)
  result.killSwitch = pick(config.killSwitch, ORDERS.killSwitch)
  set(result, "reportPath", config.reportPath)
  set(result, "sendWebhook", config.sendWebhook)

  return result
end

local function isArray(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  for key, _ in pairs(value) do
    if type(key) ~= "number" or key < 1 or key ~= math.floor(key) then
      return false
    end
    count = count + 1
  end

  return count == #value
end

local function quote(value)
  return string.format("%q", tostring(value))
end

local function keyText(key)
  if type(key) == "string" and string.match(key, "^[A-Za-z_][A-Za-z0-9_]*$") then
    return key
  end

  return "[" .. quote(key) .. "]"
end

local function orderFor(path)
  if path == "" then
    return ROOT_ORDER
  elseif path == "actuator.redstoneSignal" then
    return ORDERS.actuatorRedstoneSignal
  elseif path == "actuator.rotationSpeed" then
    return ORDERS.actuatorRotationSpeed
  end

  return ORDERS[path]
end

local function childPath(path, key)
  if path == "controller" and key == "bindings" then
    return "bindings"
  elseif path == "bindings" then
    return "binding"
  elseif path == "actuator" and key == "redstoneSignal" then
    return "actuator.redstoneSignal"
  elseif path == "actuator" and key == "rotationSpeed" then
    return "actuator.rotationSpeed"
  elseif path == "actuator.rotationSpeed" and key == "roleSigns" then
    return "roleSigns"
  elseif path == "" then
    return key
  end

  return path .. "." .. tostring(key)
end

local function writeValue(lines, value, indent, path)
  local valueType = type(value)

  if valueType == "string" then
    table.insert(lines, quote(value))
  elseif valueType == "number" or valueType == "boolean" then
    table.insert(lines, tostring(value))
  elseif valueType ~= "table" then
    table.insert(lines, "nil")
  elseif isArray(value) then
    table.insert(lines, "{ ")
    for index, child in ipairs(value) do
      if index > 1 then
        table.insert(lines, ", ")
      end
      writeValue(lines, child, indent, path)
    end
    table.insert(lines, " }")
  else
    local pad = string.rep(" ", indent)
    local childPad = string.rep(" ", indent + 2)
    local wrote = {}

    table.insert(lines, "{\n")

    local ordered = orderFor(path)
    for _, key in ipairs(ordered or {}) do
      if value[key] ~= nil then
        table.insert(lines, childPad .. keyText(key) .. " = ")
        writeValue(lines, value[key], indent + 2, childPath(path, key))
        table.insert(lines, ",\n")
        wrote[key] = true
      end
    end

    local extra = {}
    for key, _ in pairs(value) do
      if not wrote[key] then
        table.insert(extra, key)
      end
    end
    table.sort(extra, function(left, right)
      return tostring(left) < tostring(right)
    end)

    for _, key in ipairs(extra) do
      table.insert(lines, childPad .. keyText(key) .. " = ")
      writeValue(lines, value[key], indent + 2, childPath(path, key))
      table.insert(lines, ",\n")
    end

    table.insert(lines, pad .. "}")
  end
end

function configModel.serialize(config)
  local lines = { "return " }
  writeValue(lines, configModel.normalize(config), 0, "")
  table.insert(lines, "\n")
  return table.concat(lines)
end

configModel.copy = copyPlain
configModel.ROOT_ORDER = ROOT_ORDER
configModel.ORDERS = ORDERS

return configModel
