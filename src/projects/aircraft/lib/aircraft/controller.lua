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

local function formatPressed(read)
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
    frames = {},
  }

  print("Aircraft controller probe")
  print("router=" .. tostring(context.routerName))
  print("Press controller buttons. Ctrl+T stops.")

  repeat
    local frame = {
      elapsed = os.clock() - startTime,
      input = controller.sample(context),
    }
    table.insert(report.frames, frame)

    local reads = frame.input.reads or {}
    print(
      "shift="
        .. formatPressed(reads.shift)
        .. " a="
        .. formatPressed(reads.a)
        .. " s="
        .. formatPressed(reads.s)
        .. " d="
        .. formatPressed(reads.d)
        .. " space="
        .. formatPressed(reads.space)
        .. " w="
        .. formatPressed(reads.w)
    )

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
