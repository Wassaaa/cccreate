local controlInput = require("lib.control_input")
local reporting = require("lib.aircraft.reporting")

local controller = {}

local INPUT_ORDER = {
  "shift",
  "a",
  "s",
  "d",
  "space",
  "w",
  "q",
  "e",
  "k",
  "hold",
  "moveTarget",
}

local SIDE_ALIASES = {
  top = "up",
  bottom = "down",
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

local function safePeripheralTypes(name)
  local values = { pcall(peripheral.getType, name) }
  local ok = table.remove(values, 1)

  if not ok then
    return {}
  end

  return values
end

local function isRedstoneRouterType(types)
  for _, typeName in ipairs(types or {}) do
    if string.find(string.lower(tostring(typeName)), "redstone_router", 1, true) then
      return true
    end
  end

  return false
end

local function isPeripheralRouterType(types)
  for _, typeName in ipairs(types or {}) do
    if string.find(string.lower(tostring(typeName)), "peripheral_router", 1, true) then
      return true
    end
  end

  return false
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

local function findPeripheralRouter()
  for _, peripheralName in ipairs(peripheral.getNames()) do
    local types = safePeripheralTypes(peripheralName)

    if isPeripheralRouterType(types) then
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

local function normalizeSide(side)
  local value = string.lower(tostring(side or "up"))
  return SIDE_ALIASES[value] or value
end

local function normalizeBinding(binding)
  if type(binding) ~= "table" then
    return nil
  end

  return {
    x = tonumber(binding.x) or 0,
    y = tonumber(binding.y) or 0,
    z = tonumber(binding.z) or 0,
    side = normalizeSide(binding.side),
  }
end

local function axisVector(value, fallback)
  if type(value) == "table" then
    local x = tonumber(value.x) or 0
    local y = tonumber(value.y) or 0
    local z = tonumber(value.z) or 0

    if math.abs(x) + math.abs(y) + math.abs(z) == 1 then
      return { x = x, y = y, z = z }
    end
  elseif type(value) == "string" then
    local text = string.upper(string.gsub(value, "%s+", ""))
    local sign = 1

    if string.sub(text, 1, 1) == "-" then
      sign = -1
      text = string.sub(text, 2)
    elseif string.sub(text, 1, 1) == "+" then
      text = string.sub(text, 2)
    end

    if text == "X" then
      return { x = sign, y = 0, z = 0 }
    elseif text == "Y" then
      return { x = 0, y = sign, z = 0 }
    elseif text == "Z" then
      return { x = 0, y = 0, z = sign }
    end
  end

  return fallback
end

local function stepFrom(binding, vector, amount)
  amount = tonumber(amount) or 1

  return {
    x = binding.x + vector.x * amount,
    y = binding.y + vector.y * amount,
    z = binding.z + vector.z * amount,
    side = binding.side,
  }
end

local function controllerConfig(config)
  return config.controller or {}
end

controller.normalizeType = controlInput.normalizeType

local function numberOr(value, fallback)
  local number = tonumber(value)
  if number ~= nil then
    return number
  end

  return fallback
end

local function normalizeThrottleMode(value)
  local text = string.lower(tostring(value or "hold"))
  text = string.gsub(text, "%s+", "_")
  text = string.gsub(text, "-", "_")

  if text == "momentary" then
    return "momentary"
  end

  return "hold"
end

local function settingsFrom(config, options)
  local cfg = controllerConfig(config)
  local enabled = cfg.enabled == true
  local bindings = copyPlain(cfg.bindings or {})
  local typeName = cfg.type or cfg.backend or "redstone_router"

  if options.controller ~= nil then
    enabled = options.controller == true
  end
  if options.controllerType then
    typeName = options.controllerType
  end

  return {
    enabled = enabled,
    type = controlInput.normalizeType(typeName),
    inputs = INPUT_ORDER,
    optionalInputs = {
      hold = true,
      moveTarget = true,
    },
    threshold = numberOr(cfg.threshold, 1),
    throttleMode = normalizeThrottleMode(cfg.throttleMode),
    throttlePower = numberOr(cfg.throttlePower, 1),
    axis1TargetDeg = numberOr(cfg.axis1TargetDeg, 5),
    axis2TargetDeg = numberOr(cfg.axis2TargetDeg, numberOr(cfg.axis1TargetDeg, 5)),
    axis1Power = numberOr(cfg.axis1Power, 0),
    axis2Power = numberOr(cfg.axis2Power, numberOr(cfg.axis1Power, 0)),
    targetSlewDegPerSecond = numberOr(cfg.targetSlewDegPerSecond, 8),
    throttleSlewPowerPerSecond = numberOr(cfg.throttleSlewPowerPerSecond, 4),
    keyMap = copyPlain(cfg.keyMap),
    pulseInputs = {
      k = true,
      hold = true,
      moveTarget = true,
    },
    bindings = bindings,
  }
end

function controller.defaultBindings(originX, originY, originZ, side, frontAxis, leftAxis)
  local x = tonumber(originX) or 3
  local y = tonumber(originY) or -1
  local z = tonumber(originZ) or -5
  local face = normalizeSide(side or "up")
  local front = axisVector(frontAxis, { x = 0, y = 0, z = 1 })
  local left = axisVector(leftAxis, { x = 1, y = 0, z = 0 })
  local right = { x = -left.x, y = -left.y, z = -left.z }
  local shift = { x = x, y = y, z = z, side = face }
  local a = stepFrom(shift, right, 1)
  local s = stepFrom(shift, right, 2)
  local d = stepFrom(shift, right, 3)

  return {
    shift = shift,
    a = a,
    s = s,
    d = d,
    space = stepFrom(shift, right, 4),
    q = stepFrom(a, front, 1),
    w = stepFrom(s, front, 1),
    e = stepFrom(d, front, 1),
  }
end

function controller.open(config, options)
  local settings = settingsFrom(config, options or {})
  return controlInput.open(settings)
end

local function inputValue(read)
  if read and read.pressed then
    return read.value or 1
  end

  return 0
end

function controller.sample(context)
  if not context or not context.enabled then
    return {
      enabled = false,
      throttle = 0,
      axis1 = 0,
      axis2 = 0,
      yaw = 0,
      axis1Target = 0,
      axis2Target = 0,
      axis1Power = 0,
      axis2Power = 0,
      reads = {},
    }
  end

  local raw = controlInput.sample(context)
  local reads = raw.reads or {}

  local throttle = inputValue(reads.space) - inputValue(reads.shift)
  local axis1 = inputValue(reads.d) - inputValue(reads.a)
  local axis2 = inputValue(reads.w) - inputValue(reads.s)
  local yaw = inputValue(reads.q) - inputValue(reads.e)
  local holdToggle = inputValue(reads.hold)
  local moveTargetToggle = inputValue(reads.moveTarget)
  local degToRad = math.pi / 180

  return {
    enabled = true,
    type = raw.type or context.type,
    routerName = raw.routerName,
    eventCount = raw.eventCount,
    throttle = throttle,
    throttlePower = throttle * context.settings.throttlePower,
    axis1 = axis1,
    axis2 = axis2,
    yaw = yaw,
    axis1Target = axis1 * context.settings.axis1TargetDeg * degToRad,
    axis2Target = axis2 * context.settings.axis2TargetDeg * degToRad,
    axis1Power = axis1 * context.settings.axis1Power,
    axis2Power = axis2 * context.settings.axis2Power,
    holdToggle = holdToggle,
    moveTargetToggle = moveTargetToggle,
    reads = reads,
  }
end

function controller.describe(context)
  return controlInput.describe(context)
end

function controller.needsPump(context)
  return controlInput.needsPump(context)
end

function controller.pump(context)
  return controlInput.pump(context)
end

local formatPressed

local function call(target, method, ...)
  if not target or type(target[method]) ~= "function" then
    return false
  end

  local ok = pcall(target[method], ...)
  return ok
end

local function wrapMonitor(name)
  if not name then
    return nil, nil
  end

  local ok, object = pcall(peripheral.wrap, name)
  if ok and object and type(object.getSize) == "function" and type(object.write) == "function" then
    return object, name
  end

  return nil, nil
end

local function hasMethod(entry, method)
  for _, name in ipairs(entry.methods or {}) do
    if name == method then
      return true
    end
  end

  return false
end

local function isTerminalLike(entry)
  return hasMethod(entry, "getSize")
    and hasMethod(entry, "setCursorPos")
    and hasMethod(entry, "clear")
    and hasMethod(entry, "write")
end

local function loadScan(path)
  if not path or not fs.exists(path) then
    return nil
  end

  local handle = fs.open(path, "r")
  if not handle then
    return nil
  end

  local contents = handle.readAll()
  handle.close()

  local ok, scan = pcall(textutils.unserialize, contents)
  if ok and type(scan) == "table" then
    return scan
  end

  return nil
end

local function findScanMonitor(config)
  local scan = loadScan(config.reportPath or "/aircraft_scan.txt")
  if not scan then
    return nil, nil
  end

  local router = findPeripheralRouter()
  if not router then
    return nil, nil
  end

  for _, entry in ipairs(scan.peripherals or {}) do
    local coord = entry.coord

    if coord and isTerminalLike(entry) then
      local ok, object = pcall(router.wrap, coord.x, coord.y, coord.z)
      if ok and object and type(object.getSize) == "function" and type(object.write) == "function" then
        return object, "scan:" .. tostring(coord.x) .. "," .. tostring(coord.y) .. "," .. tostring(coord.z)
      end
    end
  end

  return nil, nil
end

local function findDisplay(config)
  local hudConfig = config.hud or {}

  if hudConfig.monitorName then
    local monitor, name = wrapMonitor(hudConfig.monitorName)
    if monitor then
      return monitor, name
    end
  end

  local monitor = peripheral.find("monitor")
  if monitor then
    return monitor, "monitor"
  end

  local scanned, scannedName = findScanMonitor(config)
  if scanned then
    return scanned, scannedName
  end

  return term.current(), "terminal"
end

local function size(target)
  local ok, width, height = pcall(target.getSize)
  if ok and type(width) == "number" and type(height) == "number" then
    return width, height
  end

  return 51, 19
end

local function writeAt(target, x, y, text)
  call(target, "setCursorPos", x, y)
  call(target, "write", tostring(text or ""))
end

local function writeCentered(target, y, text, width)
  local value = tostring(text or "")
  local x = math.max(1, math.floor((width - #value) / 2) + 1)
  writeAt(target, x, y, value)
end

local function setColor(target, color)
  if colors and color then
    call(target, "setTextColor", color)
  end
end

local function readLabel(name, read)
  local value = formatPressed(read)
  if read and read.pressed then
    return "[" .. string.upper(name) .. " " .. value .. "]"
  end

  return " " .. string.upper(name) .. " " .. value .. " "
end

local function drawButton(target, x, y, name, read)
  if read and read.pressed then
    setColor(target, colors and colors.lime)
  elseif read and not read.ok then
    setColor(target, colors and colors.red)
  else
    setColor(target, colors and colors.white)
  end

  writeAt(target, x, y, readLabel(name, read))
  setColor(target, colors and colors.white)
end

local function signed(value)
  local number = tonumber(value) or 0
  if number >= 0 then
    return "+" .. string.format("%.2f", number)
  end

  return string.format("%.2f", number)
end

local function drawProbeDisplay(target, frame, context, seconds)
  local width, height = size(target)
  local reads = frame.input.reads or {}

  call(target, "clear")
  setColor(target, colors and colors.white)
  writeCentered(target, 1, "AIRCRAFT CONTROLLER PROBE", width)
  writeCentered(
    target,
    2,
    "t " .. string.format("%.1f", frame.elapsed) .. "/" .. tostring(seconds) .. "  input " .. tostring(context.type),
    width
  )

  local center = math.max(16, math.floor(width / 2))
  local topY = math.max(4, math.floor(height / 2) - 4)
  drawButton(target, center - 12, topY, "q", reads.q)
  drawButton(target, center - 4, topY, "w", reads.w)
  drawButton(target, center + 4, topY, "e", reads.e)
  drawButton(target, center - 23, topY + 2, "shift", reads.shift)
  drawButton(target, center - 8, topY + 2, "a", reads.a)
  drawButton(target, center, topY + 2, "s", reads.s)
  drawButton(target, center + 8, topY + 2, "d", reads.d)
  drawButton(target, center + 18, topY + 2, "space", reads.space)
  drawButton(target, center - 8, topY + 4, "h", reads.hold)
  drawButton(target, center, topY + 4, "t", reads.moveTarget)
  drawButton(target, center + 18, topY + 4, "k", reads.k)

  setColor(target, colors and colors.white)
  writeCentered(
    target,
    topY + 5,
    "thr " .. signed(frame.input.throttle)
      .. "  axis1 " .. signed(frame.input.axis1)
      .. "  axis2 " .. signed(frame.input.axis2)
      .. "  yaw " .. signed(frame.input.yaw),
    width
  )
  writeCentered(target, topY + 7, ". off   number pressed   err bad coord/API", width)
end

function formatPressed(read)
  if not read or not read.ok then
    return "err"
  end

  if read.pressed then
    return tostring(read.signal)
  end

  return "."
end

function controller.probe(config, options)
  options = options or {}
  local probeOptions = copyPlain(options or {})
  probeOptions.controller = true

  local context = controller.open(config, probeOptions)
  local seconds = tonumber(options.seconds) or 10
  local interval = tonumber(options.interval) or 0.2
  local display, displayName = findDisplay(config)
  local displayScale = tonumber(config.hud and config.hud.monitorScale) or 0.5

  if displayName ~= "terminal" then
    call(display, "setTextScale", displayScale)
  end

  local startTime = os.clock()
  local deadline = startTime + seconds
  local report = {
    kind = "aircraft_controller_probe",
    createdAt = now(),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    seconds = seconds,
    interval = interval,
    controller = controller.describe(context),
    display = {
      targetName = displayName,
    },
    frames = {},
  }

  print("Aircraft controller probe")
  print("input=" .. tostring(context.type))
  if context.routerName then
    print("router=" .. tostring(context.routerName))
  end
  print("display=" .. tostring(displayName))
  print("Press controller buttons. Ctrl+T stops.")

  local function runProbeLoop()
    repeat
      local frame = {
        elapsed = os.clock() - startTime,
        input = controller.sample(context),
      }
      table.insert(report.frames, frame)

      drawProbeDisplay(display, frame, context, seconds)

      sleep(interval)
    until os.clock() >= deadline
  end

  if controller.needsPump(context) then
    parallel.waitForAny(
      function()
        controller.pump(context)
      end,
      runProbeLoop
    )
  else
    runProbeLoop()
  end

  local path = "/aircraft_controller.txt"
  reporting.save(report, path, config, { localReport = false })
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  print("Aircraft controller report: " .. (config.sendWebhook ~= false and "webhook" or "webhook disabled"))
  return report
end

return controller
