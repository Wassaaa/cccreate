local configModel = {}

local ROOT_ORDER = {
  "scan",
  "frontAxis",
  "leftAxis",
  "dryRun",
  "absoluteSignalMax",
  "brakeSignal",
  "maxAttitudeDelta",
  "statusReadLimit",
  "stabilize",
  "controller",
  "display",
  "hud",
  "killSwitch",
  "level",
  "reportPath",
  "statusReportPath",
  "actuatorReportPath",
  "stabilizeReportPath",
  "displayReportPath",
  "controllerReportPath",
  "configReportPath",
  "sendWebhook",
}

local ORDERS = {
  scan = { "xRadius", "yRadius", "zRadius", "sampleLimit", "errorLimit" },
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
    "signalDither",
    "brakeOnExit",
    "reportFrameLimit",
  },
  controller = {
    "enabled",
    "threshold",
    "throttlePower",
    "axis1TargetDeg",
    "axis2TargetDeg",
    "axis1Power",
    "axis2Power",
    "targetSlewDegPerSecond",
    "throttleSlewPowerPerSecond",
    "bindings",
  },
  bindings = { "space", "d", "s", "a", "shift", "w" },
  binding = { "x", "y", "z", "side" },
  display = { "enabled", "stabilizeEnabled", "stabilizeInterval" },
  hud = { "enabled", "interval", "monitorScale", "monitorName" },
  killSwitch = { "enabled", "side", "activeHigh" },
  level = { "mode", "createdAt", "angles", "attitude" },
  attitude = { "axis1", "axis2", "pitch", "roll" },
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

local function normalizeLevel(level)
  if type(level) ~= "table" then
    return nil
  end

  local result = {}
  set(result, "mode", level.mode)
  set(result, "createdAt", level.createdAt)
  set(result, "angles", level.angles)

  local attitude = pick(level.attitude, ORDERS.attitude)
  if hasAny(attitude) then
    result.attitude = attitude
  end

  if hasAny(result) then
    return result
  end

  return nil
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
  set(result, "maxAttitudeDelta", config.maxAttitudeDelta)
  set(result, "statusReadLimit", config.statusReadLimit)
  result.stabilize = pick(config.stabilize, ORDERS.stabilize)
  result.controller = pick(config.controller, ORDERS.controller)
  result.controller.bindings = normalizeBindings(config.controller and config.controller.bindings)
  result.display = pick(config.display, ORDERS.display)
  result.hud = pick(config.hud, ORDERS.hud)
  result.killSwitch = pick(config.killSwitch, ORDERS.killSwitch)
  set(result, "level", normalizeLevel(config.level))
  set(result, "reportPath", config.reportPath)
  set(result, "statusReportPath", config.statusReportPath)
  set(result, "actuatorReportPath", config.actuatorReportPath)
  set(result, "stabilizeReportPath", config.stabilizeReportPath)
  set(result, "displayReportPath", config.displayReportPath)
  set(result, "controllerReportPath", config.controllerReportPath)
  set(result, "configReportPath", config.configReportPath)
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
  end

  return ORDERS[path]
end

local function childPath(path, key)
  if path == "controller" and key == "bindings" then
    return "bindings"
  elseif path == "bindings" then
    return "binding"
  elseif path == "level" and key == "attitude" then
    return "attitude"
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
