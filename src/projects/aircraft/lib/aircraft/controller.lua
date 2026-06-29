local reporting = require("lib.aircraft.reporting")

local controller = {}

local INPUT_ORDER = {
  "shift",
  "a",
  "s",
  "d",
  "space",
  "w",
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

local function controllerConfig(config)
  return config.controller or {}
end

local function settingsFrom(config, options)
  local cfg = controllerConfig(config)
  local enabled = cfg.enabled == true

  if options.controller ~= nil then
    enabled = options.controller == true
  end

  return {
    enabled = enabled,
    threshold = tonumber(cfg.threshold) or 1,
    throttlePower = tonumber(cfg.throttlePower) or 1,
    axis1TargetDeg = tonumber(cfg.axis1TargetDeg) or 5,
    axis2TargetDeg = tonumber(cfg.axis2TargetDeg) or tonumber(cfg.axis1TargetDeg) or 5,
    axis1Sign = tonumber(cfg.axis1Sign) or 1,
    axis2Sign = tonumber(cfg.axis2Sign) or 1,
    bindings = cfg.bindings or {},
  }
end

function controller.defaultBindings(originX, originY, originZ, side)
  local x = tonumber(originX) or -1
  local y = tonumber(originY) or -1
  local z = tonumber(originZ) or -5
  local face = normalizeSide(side or "up")

  return {
    shift = { x = x, y = y, z = z, side = face },
    a = { x = x + 1, y = y, z = z, side = face },
    s = { x = x + 2, y = y, z = z, side = face },
    d = { x = x + 3, y = y, z = z, side = face },
    space = { x = x + 4, y = y, z = z, side = face },
    w = { x = x + 2, y = y, z = z - 1, side = face },
  }
end

function controller.open(config, options)
  local settings = settingsFrom(config, options or {})
  local context = {
    enabled = settings.enabled,
    settings = settings,
    routerName = nil,
    router = nil,
  }

  if not settings.enabled then
    return context
  end

  local router, routerName = findRedstoneRouter()
  if not router then
    error("No redstone_router with getRedstone(x, y, z, side) found", 0)
  end

  context.router = router
  context.routerName = routerName

  return context
end

local function readBinding(context, binding)
  local normalized = normalizeBinding(binding)
  if not normalized then
    return {
      ok = false,
      signal = 0,
      value = 0,
      pressed = false,
      error = "missing binding",
    }
  end

  local ok, valueOrError = pcall(
    context.router.getRedstone,
    normalized.x,
    normalized.y,
    normalized.z,
    normalized.side
  )

  if not ok then
    return {
      ok = false,
      signal = 0,
      value = 0,
      pressed = false,
      coord = normalized,
      error = tostring(valueOrError),
    }
  end

  local signal = valueOrError
  if signal == true then
    signal = 15
  elseif signal == false or signal == nil then
    signal = 0
  else
    signal = tonumber(signal) or 0
  end

  signal = clamp(signal, 0, 15)

  return {
    ok = true,
    signal = signal,
    value = signal / 15,
    pressed = signal >= context.settings.threshold,
    coord = normalized,
  }
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
      axis1Target = 0,
      axis2Target = 0,
      reads = {},
    }
  end

  local reads = {}
  for _, name in ipairs(INPUT_ORDER) do
    reads[name] = readBinding(context, context.settings.bindings[name])
  end

  local throttle = inputValue(reads.space) - inputValue(reads.shift)
  local axis1 = (inputValue(reads.d) - inputValue(reads.a)) * context.settings.axis1Sign
  local axis2 = (inputValue(reads.w) - inputValue(reads.s)) * context.settings.axis2Sign
  local degToRad = math.pi / 180

  return {
    enabled = true,
    routerName = context.routerName,
    throttle = throttle,
    throttlePower = throttle * context.settings.throttlePower,
    axis1 = axis1,
    axis2 = axis2,
    axis1Target = axis1 * context.settings.axis1TargetDeg * degToRad,
    axis2Target = axis2 * context.settings.axis2TargetDeg * degToRad,
    reads = reads,
  }
end

function controller.describe(context)
  if not context then
    return {
      enabled = false,
    }
  end

  return {
    enabled = context.enabled == true,
    routerName = context.routerName,
    settings = copyPlain(context.settings),
  }
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
    "t " .. string.format("%.1f", frame.elapsed) .. "/" .. tostring(seconds) .. "  router " .. tostring(context.routerName),
    width
  )

  local center = math.max(16, math.floor(width / 2))
  local topY = math.max(4, math.floor(height / 2) - 4)
  drawButton(target, center - 4, topY, "w", reads.w)
  drawButton(target, center - 23, topY + 2, "shift", reads.shift)
  drawButton(target, center - 8, topY + 2, "a", reads.a)
  drawButton(target, center, topY + 2, "s", reads.s)
  drawButton(target, center + 8, topY + 2, "d", reads.d)
  drawButton(target, center + 18, topY + 2, "space", reads.space)

  setColor(target, colors and colors.white)
  writeCentered(
    target,
    topY + 5,
    "thr " .. signed(frame.input.throttle) .. "  axis1 " .. signed(frame.input.axis1) .. "  axis2 " .. signed(frame.input.axis2),
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
  print("router=" .. tostring(context.routerName))
  print("display=" .. tostring(displayName))
  print("Press controller buttons. Ctrl+T stops.")

  repeat
    local frame = {
      elapsed = os.clock() - startTime,
      input = controller.sample(context),
    }
    table.insert(report.frames, frame)

    drawProbeDisplay(display, frame, context, seconds)

    sleep(interval)
  until os.clock() >= deadline

  local path = config.controllerReportPath or "/aircraft_controller.txt"
  reporting.save(report, path)
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  print("Aircraft controller report: " .. path)
  return report
end

return controller
