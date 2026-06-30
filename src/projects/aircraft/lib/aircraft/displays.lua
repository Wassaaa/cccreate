local coords = require("lib.aircraft.coords")

local displays = {}

local ROLE_ORDER = {
  "front_left",
  "front_right",
  "rear_left",
  "rear_right",
}

local STATUS_STRIP_ORDER = {
  {
    key = "throttle",
    offset = 0,
  },
  {
    key = "hold",
    offset = 1,
  },
  {
    key = "moveTarget",
    offset = 2,
  },
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

local function ccColor(name)
  local palette = nil
  if type(colors) == "table" then
    palette = colors
  elseif type(colours) == "table" then
    palette = colours
  end

  return palette and palette[name] or nil
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
  local statusStrip = display.statusStrip or {}

  if options.display ~= nil then
    enabled = options.display == true
  end

  return {
    enabled = enabled,
    absoluteRotorValues = display.absoluteRotorValues ~= false,
    statusStrip = {
      enabled = statusStrip.enabled == true,
      x = statusStrip.x,
      y = statusStrip.y,
      z = statusStrip.z,
      axis = statusStrip.axis,
    },
  }
end

local function formatSignal(signal, absolute)
  local number = tonumber(signal) or 0
  if absolute then
    number = math.abs(number)
  end

  return tostring(math.floor(number + 0.5))
end

local function writeText(object, text, color)
  local results = {}

  if color then
    if type(object.setTextColor) == "function" then
      results.setTextColor = call(object, "setTextColor", color)
    elseif type(object.setTextColour) == "function" then
      results.setTextColour = call(object, "setTextColour", color)
    end
  end

  if type(object.setText) == "function" then
    results.setText = call(object, "setText", text)
    return results
  end

  return {
    ok = false,
    error = "missing setText",
  }
end

local function coordAt(anchor, axis, offset)
  return {
    x = anchor.x + axis.x * offset,
    y = anchor.y + axis.y * offset,
    z = anchor.z + axis.z * offset,
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

local function collectStatusStrip(context, router)
  local strip = context.settings.statusStrip or {}
  local anchor = {
    x = tonumber(strip.x),
    y = tonumber(strip.y),
    z = tonumber(strip.z),
  }
  local axis = coords.parseAxis(strip.axis or "+X")

  context.statusStrip = {
    enabled = strip.enabled == true,
    anchor = copyPlain(anchor),
    axis = axis and coords.axisLabel(axis) or strip.axis,
    devices = {},
    errors = {},
    reservedKeys = {},
  }

  if not context.statusStrip.enabled then
    return
  end

  if type(anchor.x) ~= "number" or type(anchor.y) ~= "number" or type(anchor.z) ~= "number" then
    context.statusStrip.errors.config = "missing anchor x/y/z"
    return
  end
  if not axis then
    context.statusStrip.errors.config = "invalid axis " .. tostring(strip.axis)
    return
  end

  for _, cell in ipairs(STATUS_STRIP_ORDER) do
    local coord = coordAt(anchor, axis, cell.offset)
    context.statusStrip.reservedKeys[coords.key(coord.x, coord.y, coord.z)] = true
    local device, errorMessage = wrapDisplay(router, { coord = coord })
    if device then
      device.key = cell.key
      context.statusStrip.devices[cell.key] = device
    else
      context.statusStrip.errors[cell.key] = errorMessage
    end
  end
end

local function isReservedStatusStripCoord(context, coord)
  local key = coord and coords.key(coord.x, coord.y, coord.z)
  return key and context.statusStrip
    and context.statusStrip.reservedKeys
    and context.statusStrip.reservedKeys[key] == true
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

  collectStatusStrip(context, router)

  local roles = scan.orientation
    and scan.orientation.roles
    and scan.orientation.roles.displaySink

  if not roles then
    if not context.statusStrip or not context.statusStrip.enabled then
      context.skipped = "no displaySink role map"
    else
      context.roleSkipped = "no displaySink role map"
    end
    return context
  end

  for _, role in ipairs(ROLE_ORDER) do
    local mapped = roles[role]

    if mapped and mapped.coord then
      if isReservedStatusStripCoord(context, mapped.coord) then
        context.errors[role] = "skipped reserved status strip cell " .. coords.label(mapped.coord)
      elseif options.textOnly and mapped.displayKind and mapped.displayKind ~= "text" then
        context.errors[role] = "skipped non-text displayKind " .. tostring(mapped.displayKind)
      else
        local device, errorMessage = wrapDisplay(router, mapped)
        if device then
          device.role = role
          device.displayKind = mapped.displayKind
          context.devices[role] = device
        else
          context.errors[role] = errorMessage
        end
      end
    end
  end

  return context
end

function displays.describe(context)
  local result = {
    enabled = context.enabled,
    skipped = context.skipped,
    roleSkipped = context.roleSkipped,
    settings = copyPlain(context.settings),
    devices = {},
    errors = copyPlain(context.errors),
    statusStrip = context.statusStrip and {
      enabled = context.statusStrip.enabled,
      anchor = copyPlain(context.statusStrip.anchor),
      axis = context.statusStrip.axis,
      devices = {},
      errors = copyPlain(context.statusStrip.errors),
    } or nil,
  }

  for _, role in ipairs(ROLE_ORDER) do
    local device = context.devices[role]
    if device then
      result.devices[role] = {
        coord = copyPlain(device.coord),
        displayKind = device.displayKind,
      }
    end
  end

  if result.statusStrip then
    for _, cell in ipairs(STATUS_STRIP_ORDER) do
      local device = context.statusStrip.devices[cell.key]
      if device then
        result.statusStrip.devices[cell.key] = {
          coord = copyPlain(device.coord),
        }
      end
    end
  end

  return result
end

local function compactNumber(value)
  local number = tonumber(value)
  if not number then
    return "?"
  end

  return tostring(math.floor(number + (number >= 0 and 0.5 or -0.5)))
end

local function throttleText(frame)
  local mixed = frame and frame.mixed or {}
  local controller = frame and frame.controller or {}

  return compactNumber(
    mixed.baseRpmBeforeTilt
      or mixed.baseRpm
      or mixed.basePowerBeforeTilt
      or mixed.basePower
      or controller.heldThrottlePower
      or controller.throttlePower
      or 0
  )
end

local function modeCell(label, mode)
  mode = mode or {}

  if mode.enabled == false then
    return {
      text = label,
      color = ccColor("gray") or ccColor("lightGray"),
      colorName = "gray",
      state = "disabled",
    }
  elseif mode.active == true and mode.skipped then
    return {
      text = label,
      color = ccColor("orange") or ccColor("yellow"),
      colorName = "orange",
      state = "skipped",
      skipped = mode.skipped,
    }
  elseif mode.active == true then
    return {
      text = label,
      color = ccColor("lime") or ccColor("green"),
      colorName = "lime",
      state = "active",
    }
  end

  return {
    text = label,
    color = ccColor("red"),
    colorName = "red",
    state = "inactive",
  }
end

local function statusStripCells(frame)
  local hold = frame and frame.hold or {}
  local moveTarget = hold.moveTarget or {}

  return {
    throttle = {
      text = throttleText(frame),
      color = ccColor("white"),
      colorName = "white",
      state = "value",
    },
    hold = modeCell("H", hold),
    moveTarget = modeCell("T", moveTarget),
  }
end

local function updateStatusStrip(context, frame, report, tasks)
  local strip = context.statusStrip
  if not strip or not strip.enabled or not frame then
    return
  end

  report.statusStrip = {
    enabled = true,
    cells = {},
  }

  local cells = statusStripCells(frame)
  for _, cell in ipairs(STATUS_STRIP_ORDER) do
    local device = strip.devices[cell.key]
    local value = cells[cell.key]

    if device and value then
      local key = cell.key
      local displayDevice = device
      local textValue = value.text
      local colorValue = value.color

      report.statusStrip.cells[key] = {
        coord = copyPlain(device.coord),
        text = textValue,
        color = value.colorName,
        state = value.state,
        skipped = value.skipped,
      }
      report.updated = true

      table.insert(tasks, function()
        report.statusStrip.cells[key].results = writeText(displayDevice.object, textValue, colorValue)
      end)
    elseif value then
      report.statusStrip.cells[cell.key] = {
        text = value.text,
        color = value.colorName,
        state = value.state,
        skipped = "missing display",
      }
    end
  end
end

function displays.updateSignals(context, signals, frame)
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
      local text = formatSignal(signal, context.settings and context.settings.absoluteRotorValues)
      local textValue = text

      report.roles[role] = {
        coord = copyPlain(device.coord),
        signal = displaySignal,
        text = text,
      }
      report.updated = true

      table.insert(tasks, function()
        report.roles[roleName].results = writeText(displayDevice.object, textValue, ccColor("white"))
      end)
    end
  end

  updateStatusStrip(context, frame, report, tasks)

  if #tasks > 0 then
    parallel.waitForAll(unpack(tasks))
  end

  return report
end

return displays
