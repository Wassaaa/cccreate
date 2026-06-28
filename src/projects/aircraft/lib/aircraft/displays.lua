local coords = require("lib.aircraft.coords")

local displays = {}

local ROLE_ORDER = {
  "front_left",
  "front_right",
  "rear_left",
  "rear_right",
}

local ROLE_LABELS = {
  front_left = "FL",
  front_right = "FR",
  rear_left = "RL",
  rear_right = "RR",
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
    includeRole = display.includeRole == true,
    decimals = tonumber(display.decimals) or 1,
    updateEveryFrames = math.max(1, tonumber(display.updateEveryFrames) or 1),
    textColor = display.textColor,
  }
end

local function formatSignal(signal, decimals)
  local number = tonumber(signal) or 0
  decimals = tonumber(decimals) or 1

  if decimals <= 0 then
    return tostring(math.floor(number + 0.5))
  end

  local multiplier = 10 ^ decimals
  local rounded = math.floor(number * multiplier + 0.5) / multiplier
  local format = "%." .. tostring(decimals) .. "f"

  return string.format(format, rounded)
end

local function signalText(role, signal, settings)
  local text = formatSignal(signal, settings.decimals)

  if settings.includeRole then
    return (ROLE_LABELS[role] or role) .. " " .. text
  end

  return text
end

local function setTextColor(object, color)
  if color == nil then
    return nil
  end

  if type(object.setTextColor) == "function" then
    return call(object, "setTextColor", color)
  elseif type(object.setTextColour) == "function" then
    return call(object, "setTextColour", color)
  end

  return {
    ok = false,
    error = "missing text color method",
  }
end

local function writeNixieLike(object, text, signal, settings)
  local results = {}

  local colorResult = setTextColor(object, settings.textColor)
  if colorResult then
    results.setTextColor = colorResult
  end

  if type(object.setText) == "function" then
    results.setText = call(object, "setText", text)
    return results
  end

  return nil
end

local function writeTerminalLike(object, text)
  if type(object.write) ~= "function" then
    return nil
  end

  local results = {}

  if type(object.clear) == "function" then
    results.clear = call(object, "clear")
  end

  if type(object.setCursorPos) == "function" then
    results.setCursorPos = call(object, "setCursorPos", 1, 1)
  end

  results.write = call(object, "write", text)

  if type(object.update) == "function" then
    results.update = call(object, "update")
  end

  return results
end

local function writeSignalFallback(object, signal)
  if type(object.setSignal) ~= "function" then
    return nil
  end

  return {
    setSignal = call(object, "setSignal", math.max(0, math.min(15, math.floor((tonumber(signal) or 0) + 0.5)))),
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

function displays.updateSignals(context, signals, frameIndex, force)
  local report = {
    enabled = context.enabled,
    updated = false,
    roles = {},
  }

  if not context.enabled then
    report.skipped = context.skipped or "display disabled"
    return report
  end

  if not force and frameIndex and ((frameIndex - 1) % context.settings.updateEveryFrames ~= 0) then
    report.skipped = "updateEveryFrames"
    return report
  end

  for _, role in ipairs(ROLE_ORDER) do
    local device = context.devices[role]
    local signal = signals and signals[role]

    if device and signal ~= nil then
      local text = signalText(role, signal, context.settings)
      local writeResults = writeNixieLike(device.object, text, signal, context.settings)
        or writeTerminalLike(device.object, text)
        or writeSignalFallback(device.object, signal)

      report.roles[role] = {
        coord = copyPlain(device.coord),
        signal = signal,
        text = text,
        results = writeResults or {
          ok = false,
          error = "no supported display write method",
        },
      }
      report.updated = true
    end
  end

  return report
end

return displays
