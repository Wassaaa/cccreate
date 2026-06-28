local coords = require("lib.aircraft.coords")

local displays = {}

local ROLE_ORDER = {
  "front_left",
  "front_right",
  "rear_left",
  "rear_right",
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

local function call(object, method, ...)
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

local function displayConfig(config, options)
  local display = config.display or {}
  local enabled = display.enabled ~= false

  if options.display ~= nil then
    enabled = options.display == true
  end

  return {
    enabled = enabled,
  }
end

local function formatSignal(signal)
  local number = tonumber(signal) or 0

  return tostring(math.floor(number + 0.5))
end

local function writeText(object, text)
  if type(object.setText) == "function" then
    return {
      setText = call(object, "setText", text),
    }
  end

  return {
    ok = false,
    error = "missing setText",
  }
end

local function wrapDisplay(router, mapped)
  local coord = mapped and mapped.coord
  if not coord then
    return nil, "missing coord"
  end

  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok then
    return nil, "wrap error: " .. tostring(objectOrError)
  end

  if not objectOrError then
    return nil, "no peripheral at " .. coords.label(coord)
  end

  return {
    coord = copyPlain(coord),
    object = objectOrError,
  }, nil
end

function displays.collect(config, router, scan, options)
  options = options or {}

  local settings = displayConfig(config, options)
  local context = {
    enabled = settings.enabled,
    settings = settings,
    devices = {},
    errors = {},
  }

  if not context.enabled then
    context.skipped = "display disabled"
    return context
  end

  local roles = scan.orientation
    and scan.orientation.roles
    and scan.orientation.roles.displaySink

  if not roles then
    context.skipped = "no displaySink role map"
    return context
  end

  for _, role in ipairs(ROLE_ORDER) do
    local mapped = roles[role]

    if mapped and mapped.coord then
      local device, errorMessage = wrapDisplay(router, mapped)
      if device then
        device.role = role
        context.devices[role] = device
      else
        context.errors[role] = errorMessage
      end
    end
  end

  return context
end

function displays.describe(context)
  local result = {
    enabled = context.enabled,
    skipped = context.skipped,
    settings = copyPlain(context.settings),
    devices = {},
    errors = copyPlain(context.errors),
  }

  for _, role in ipairs(ROLE_ORDER) do
    local device = context.devices[role]
    if device then
      result.devices[role] = {
        coord = copyPlain(device.coord),
      }
    end
  end

  return result
end

function displays.updateSignals(context, signals)
  local report = {
    enabled = context.enabled,
    updated = false,
    roles = {},
  }

  if not context.enabled then
    report.skipped = context.skipped or "display disabled"
    return report
  end

  local tasks = {}

  for _, role in ipairs(ROLE_ORDER) do
    local device = context.devices[role]
    local signal = signals and signals[role]

    if device and signal ~= nil then
      local roleName = role
      local displayDevice = device
      local displaySignal = signal
      local text = formatSignal(signal)
      local textValue = text

      report.roles[role] = {
        coord = copyPlain(device.coord),
        signal = displaySignal,
        text = text,
      }
      report.updated = true

      table.insert(tasks, function()
        report.roles[roleName].results = writeText(displayDevice.object, textValue)
      end)
    end
  end

  if #tasks > 0 then
    parallel.waitForAll(unpack(tasks))
  end

  return report
end

return displays
