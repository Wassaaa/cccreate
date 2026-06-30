local coords = require("lib.aircraft.coords")

local displays = {}

local ROLE_ORDER = {
  "front_left",
  "front_right",
  "rear_left",
  "rear_right",
}

-- Create Nixie tubes render two text characters per block.
local STATUS_TEXT_CELL_WIDTH = 2

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
  number = math.abs(number)

  return tostring(math.floor(number + 0.5))
end

local function writeColor(object, color)
  local results = {}

  if color and type(object.setTextColor) == "function" then
    results.setTextColor = call(object, "setTextColor", color)
  elseif color and type(object.setTextColour) == "function" then
    results.setTextColour = call(object, "setTextColour", color)
  else
    results.skipped = "missing setTextColor"
  end

  return results
end

local function writeText(object, text, color)
  local results = {}

  if type(object.setText) == "function" then
    if color then
      results.setTextWithColour = call(object, "setText", text, color)
      if results.setTextWithColour.ok then
        return results
      end
    end

    results.setText = call(object, "setText", text)
    if color then
      results.setTextColour = writeColor(object, color)
    end
    return results
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

local function coordAt(anchor, axis, offset)
  return {
    x = anchor.x + axis.x * offset,
    y = anchor.y + axis.y * offset,
    z = anchor.z + axis.z * offset,
  }
end

local function reserveStatusStripKey(context, coord)
  local key = coord and coords.key(coord.x, coord.y, coord.z)
  if key then
    context.statusStrip.reservedKeys[key] = true
  end
end

local function collectStatusStrip(context, router, scan)
  local strip = scan
    and scan.orientation
    and scan.orientation.reservedDisplays
    and scan.orientation.reservedDisplays.statusStrip

  context.statusStrip = {
    enabled = false,
    status = strip and strip.status,
    coord = strip and copyPlain(strip.coord),
    axis = strip and strip.axis,
    length = strip and strip.length,
    devices = {},
    cellsByOffset = {},
    errors = {},
    reservedKeys = {},
  }

  if not strip or strip.enabled ~= true or not strip.coord then
    return
  end

  context.statusStrip.enabled = true

  local axis = coords.parseAxis(strip.axis)
  local length = tonumber(strip.length)

  if axis and length and length > 0 then
    for offset = 0, length - 1 do
      local coord = coordAt(strip.coord, axis, offset)
      reserveStatusStripKey(context, coord)
      local device, errorMessage = wrapDisplay(router, { coord = coord })
      if device then
        context.statusStrip.cellsByOffset[offset] = device
        if offset == 0 then
          context.statusStrip.devices.text = device
        end
      else
        context.statusStrip.errors["offset" .. tostring(offset)] = errorMessage
      end
    end
  else
    local textDevice, textError = wrapDisplay(router, { coord = strip.coord })
    if textDevice then
      context.statusStrip.devices.text = textDevice
      context.statusStrip.cellsByOffset[0] = textDevice
    else
      context.statusStrip.errors.text = textError
    end

    for key, cell in pairs(strip.cells or {}) do
      if type(cell) == "table" and cell.coord then
        reserveStatusStripKey(context, cell.coord)
        local device, errorMessage = wrapDisplay(router, { coord = cell.coord })
        if device then
          context.statusStrip.devices[key] = device
          if type(cell.offset) == "number" then
            context.statusStrip.cellsByOffset[cell.offset] = device
          end
        else
          context.statusStrip.errors[key] = errorMessage
        end
      end
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

  collectStatusStrip(context, router, scan)

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
      status = context.statusStrip.status,
      coord = copyPlain(context.statusStrip.coord),
      axis = context.statusStrip.axis,
      length = context.statusStrip.length,
      devices = {},
      offsets = {},
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
    for _, key in ipairs({ "text", "hold", "moveTarget" }) do
      local device = context.statusStrip.devices[key]
      if device then
        result.statusStrip.devices[key] = {
          coord = copyPlain(device.coord),
        }
      end
    end

    for offset, device in pairs(context.statusStrip.cellsByOffset or {}) do
      table.insert(result.statusStrip.offsets, {
        offset = offset,
        coord = copyPlain(device.coord),
      })
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

local function modeCell(onText, offText, mode)
  mode = mode or {}

  if mode.enabled == false then
    return {
      text = "-",
      color = "gray",
      colorName = "gray",
      state = "disabled",
    }
  elseif mode.active == true and mode.skipped then
    return {
      text = "!",
      color = "orange",
      colorName = "orange",
      state = "skipped",
      skipped = mode.skipped,
    }
  elseif mode.active == true then
    return {
      text = onText,
      color = "lime",
      colorName = "lime",
      state = "active",
    }
  end

  return {
    text = offText,
    color = "red",
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
      color = "white",
      colorName = "white",
      state = "value",
    },
    hold = modeCell("H", "h", hold),
    moveTarget = modeCell("T", "t", moveTarget),
  }
end

local function statusCellOffset(characterIndex)
  return math.floor((characterIndex - 1) / STATUS_TEXT_CELL_WIDTH)
end

local function statusColorOffsets(cells)
  local throttleLength = string.len(cells.throttle.text or "")

  return {
    throttleStart = 0,
    throttleEnd = statusCellOffset(math.max(1, throttleLength)),
    hold = statusCellOffset(throttleLength + 2),
    moveTarget = statusCellOffset(throttleLength + 3),
  }
end

local function mergedModeColor(hold, moveTarget)
  if (hold and hold.state == "skipped") or (moveTarget and moveTarget.state == "skipped") then
    return "orange"
  elseif (hold and hold.state == "active") or (moveTarget and moveTarget.state == "active") then
    return "lime"
  elseif (hold and hold.state == "disabled") and (moveTarget and moveTarget.state == "disabled") then
    return "gray"
  end

  return "red"
end

local function statusColorsByOffset(cells, offsets)
  local colorsByOffset = {}

  for offset = offsets.throttleStart, offsets.throttleEnd do
    colorsByOffset[offset] = cells.throttle.color
  end

  if offsets.hold == offsets.moveTarget then
    colorsByOffset[offsets.hold] = mergedModeColor(cells.hold, cells.moveTarget)
  else
    colorsByOffset[offsets.hold] = cells.hold.color
    colorsByOffset[offsets.moveTarget] = cells.moveTarget.color
  end

  return colorsByOffset
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
  local textValue = cells.throttle.text .. " " .. cells.hold.text .. cells.moveTarget.text
  local offsets = statusColorOffsets(cells)
  local colorsByOffset = statusColorsByOffset(cells, offsets)
  report.statusStrip.text = textValue
  report.statusStrip.colorOffsets = copyPlain(offsets)

  for _, key in ipairs({ "throttle", "hold", "moveTarget" }) do
    local value = cells[key]
    if value then
      report.statusStrip.cells[key] = {
        text = value.text,
        color = value.colorName,
        state = value.state,
        skipped = value.skipped,
      }
    end
  end

  strip.lastColors = strip.lastColors or {}

  if strip.devices.text then
    local textDevice = strip.devices.text
    report.statusStrip.coord = copyPlain(textDevice.coord)
    local textChanged = strip.lastText ~= textValue
    local colorChanges = {}

    for offset, color in pairs(colorsByOffset) do
      if strip.lastColors[offset] ~= color then
        table.insert(colorChanges, {
          offset = offset,
          color = color,
        })
      end
    end

    report.statusStrip.changed = {
      text = textChanged,
      colorCount = #colorChanges,
    }

    if textChanged or #colorChanges > 0 then
      report.updated = true
      table.insert(tasks, function()
        if textChanged then
          report.statusStrip.results = writeText(textDevice.object, textValue, nil)
          strip.lastText = textValue
        else
          report.statusStrip.results = {
            skipped = "text unchanged",
          }
        end

        report.statusStrip.colorResults = {}

        for _, change in ipairs(colorChanges) do
          local device = strip.cellsByOffset and strip.cellsByOffset[change.offset]
          if device then
            local results = writeColor(device.object, change.color)
            strip.lastColors[change.offset] = change.color
            table.insert(report.statusStrip.colorResults, {
              offset = change.offset,
              color = change.color,
              coord = copyPlain(device.coord),
              results = results,
            })
          else
            table.insert(report.statusStrip.colorResults, {
              offset = change.offset,
              color = change.color,
              skipped = "missing display",
            })
          end
        end

        for _, key in ipairs({ "hold", "moveTarget" }) do
          local offset = offsets[key]
          local device = strip.cellsByOffset and strip.cellsByOffset[offset]
          local value = cells[key]

          if device and value then
            report.statusStrip.cells[key].coord = copyPlain(device.coord)
            report.statusStrip.cells[key].offset = offset
            report.statusStrip.cells[key].color = colorsByOffset[offset] or value.color
          elseif value then
            report.statusStrip.cells[key].offset = offset
            report.statusStrip.cells[key].skipped = "missing display at offset " .. tostring(offset)
          end
        end
      end)
    else
      report.statusStrip.skipped = "unchanged"
    end
  else
    report.statusStrip.skipped = "missing text display"
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
      local text = formatSignal(signal)
      local textValue = text

      report.roles[role] = {
        coord = copyPlain(device.coord),
        signal = displaySignal,
        text = text,
      }
      report.updated = true

      table.insert(tasks, function()
        report.roles[roleName].results = writeText(displayDevice.object, textValue, "white")
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
