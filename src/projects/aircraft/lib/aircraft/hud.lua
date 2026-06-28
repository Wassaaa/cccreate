local hud = {}

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

local function wrapMonitor(name)
  if not name then
    return nil, nil
  end

  local ok, object = pcall(peripheral.wrap, name)
  if ok and object then
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

local function wrapScanMonitor(router, entry)
  local coord = entry and entry.coord

  if not router or not coord then
    return nil, nil
  end

  local ok, object = pcall(router.wrap, coord.x, coord.y, coord.z)
  if ok and object and type(object.getSize) == "function" and type(object.write) == "function" then
    return object, "scan:" .. tostring(coord.x) .. "," .. tostring(coord.y) .. "," .. tostring(coord.z)
  end

  return nil, nil
end

local function findScanMonitor(router, scan)
  for _, entry in ipairs(scan and scan.peripherals or {}) do
    if isTerminalLike(entry) then
      local monitor, name = wrapScanMonitor(router, entry)

      if monitor then
        return monitor, name
      end
    end
  end

  return nil, nil
end

local function findMonitor(config, router, scan)
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

  return findScanMonitor(router, scan)
end

local function call(target, method, ...)
  if type(target[method]) ~= "function" then
    return false
  end

  local ok = pcall(target[method], ...)
  return ok
end

local function number(value, fallback)
  if type(value) == "number" then
    return value
  end

  return fallback or 0
end

local function degrees(radians)
  return number(radians) * 180 / math.pi
end

local function fixed(value, digits)
  return string.format("%." .. tostring(digits or 1) .. "f", number(value))
end

local function signed(value, digits)
  return string.format("%+." .. tostring(digits or 1) .. "f", number(value))
end

local function getSize(target)
  if type(target.getSize) ~= "function" then
    return 51, 19
  end

  local ok, width, height = pcall(target.getSize)
  if ok and type(width) == "number" and type(height) == "number" then
    return width, height
  end

  return 51, 19
end

local function trim(text, width)
  text = tostring(text or "")

  if width <= 0 then
    return ""
  elseif #text <= width then
    return text
  end

  return string.sub(text, 1, width)
end

local function writeAt(target, x, y, text, width, alignRight)
  width = width or #tostring(text or "")
  text = trim(text, width)

  if alignRight then
    x = x + width - #text
  end

  call(target, "setCursorPos", math.max(1, x), math.max(1, y))
  call(target, "write", text)
end

local function writeLine(target, row, text, width)
  call(target, "setCursorPos", 1, row)
  call(target, "clearLine")
  writeAt(target, 1, row, text, width)
end

local function writeCentered(target, row, text, width)
  text = trim(text, width)
  writeAt(target, math.floor((width - #text) / 2) + 1, row, text, #text)
end

local function roleValues(values, digits)
  local parts = {}

  for _, role in ipairs(ROLE_ORDER) do
    local value = values and values[role]
    if type(value) == "number" and digits then
      value = fixed(value, digits)
    elseif value == nil then
      value = "?"
    end

    table.insert(parts, ROLE_LABELS[role] .. "=" .. tostring(value))
  end

  return table.concat(parts, " ")
end

local function statusText(frame, mixed, settings)
  if mixed.correctionLimited then
    return "correction capped"
  elseif frame.abortReason then
    return frame.abortReason
  end

  return "maxCorr " .. fixed(settings.maxCorrection, 2)
end

local function roleText(role, mixed)
  local signal = mixed.signals and mixed.signals[role]
  local power = mixed.power and mixed.power[role]
  local powerText = "?"

  if type(power) == "number" then
    powerText = fixed(power, 1)
  end

  return {
    ROLE_LABELS[role] .. " sig " .. tostring(signal or "?"),
    "pwr " .. powerText,
  }
end

local function drawRolePanel(target, role, x, y, width, mixed, alignRight)
  local lines = roleText(role, mixed)

  writeAt(target, x, y, lines[1], width, alignRight)
  writeAt(target, x, y + 1, lines[2], width, alignRight)
end

local function drawCompact(target, frame, settings, active, status, width)
  local mixed = frame.mixed or {}

  writeLine(target, 1, "AIRCRAFT STABILIZE " .. status, width)
  writeLine(target, 2, "t " .. fixed(frame.elapsed, 1) .. "/" .. fixed(settings.seconds, 1) .. "s base " .. fixed(settings.basePower, 1), width)
  writeLine(target, 3, "err A1=" .. signed(degrees(mixed.error1), 1) .. " A2=" .. signed(degrees(mixed.error2), 1) .. " deg", width)
  writeLine(target, 4, "rate A1=" .. signed(mixed.rate1, 2) .. " A2=" .. signed(mixed.rate2, 2), width)
  writeLine(target, 5, "corr A1=" .. signed(mixed.correction1, 2) .. " A2=" .. signed(mixed.correction2, 2), width)
  writeLine(target, 6, "signal " .. roleValues(mixed.signals), width)
  writeLine(target, 7, "power  " .. roleValues(mixed.power, 1), width)
  writeLine(target, 8, statusText(frame, mixed, settings), width)
end

local function drawCornerLayout(target, frame, settings, status, width, height)
  local mixed = frame.mixed or {}
  local panelWidth = math.max(12, math.min(18, math.floor(width / 2) - 1))
  local rightX = width - panelWidth + 1
  local bottomY = math.max(8, height - 2)
  local centerY = math.max(5, math.floor(height / 2) - 1)

  writeCentered(target, 1, "AIRCRAFT STABILIZE " .. status, width)
  writeCentered(target, 2, "t " .. fixed(frame.elapsed, 1) .. "/" .. fixed(settings.seconds, 1) .. "s  base " .. fixed(settings.basePower, 1), width)

  drawRolePanel(target, "front_left", 1, 3, panelWidth, mixed, false)
  drawRolePanel(target, "front_right", rightX, 3, panelWidth, mixed, true)
  drawRolePanel(target, "rear_left", 1, bottomY, panelWidth, mixed, false)
  drawRolePanel(target, "rear_right", rightX, bottomY, panelWidth, mixed, true)

  if centerY + 3 < bottomY then
    writeCentered(target, centerY, "err deg A1=" .. signed(degrees(mixed.error1), 1) .. " A2=" .. signed(degrees(mixed.error2), 1), width)
    writeCentered(target, centerY + 1, "rate A1=" .. signed(mixed.rate1, 2) .. " A2=" .. signed(mixed.rate2, 2), width)
    writeCentered(target, centerY + 2, "corr A1=" .. signed(mixed.correction1, 2) .. " A2=" .. signed(mixed.correction2, 2), width)
  end

  writeCentered(target, height, statusText(frame, mixed, settings), width)
end

local function settingsFrom(config, options)
  local hudConfig = config.hud or {}
  local enabled = hudConfig.enabled ~= false

  if options.hud ~= nil then
    enabled = options.hud == true
  end

  return {
    enabled = enabled,
    interval = tonumber(options.hudInterval) or tonumber(hudConfig.interval) or 0.5,
    monitorScale = tonumber(hudConfig.monitorScale) or 0.5,
  }
end

function hud.open(config, options, router, scan)
  local settings = settingsFrom(config, options or {})
  local context = {
    enabled = settings.enabled,
    settings = settings,
  }

  if not context.enabled then
    context.skipped = "hud disabled"
    return context
  end

  local monitor, monitorName = findMonitor(config, router, scan)
  if monitor then
    context.target = monitor
    context.targetName = monitorName
    context.kind = "monitor"
    call(monitor, "setTextScale", settings.monitorScale)
  else
    context.target = term
    context.targetName = "terminal"
    context.kind = "terminal"
  end

  call(context.target, "clear")
  call(context.target, "setCursorPos", 1, 1)

  return context
end

function hud.describe(context)
  return {
    enabled = context.enabled,
    skipped = context.skipped,
    kind = context.kind,
    targetName = context.targetName,
    settings = context.settings,
  }
end

function hud.update(context, frame, settings, active, force)
  if not context.enabled or not context.target then
    return {
      updated = false,
      skipped = context.skipped or "hud disabled",
    }
  end

  local elapsed = number(frame.elapsed)
  if not force and context.lastElapsed and elapsed - context.lastElapsed < context.settings.interval then
    return {
      updated = false,
      skipped = "hud interval",
    }
  end

  context.lastElapsed = elapsed

  local mixed = frame.mixed or {}
  local status = active and "APPLY" or "DRY"
  if frame.aborted then
    status = "ABORT"
  end

  local width, height = getSize(context.target)

  call(context.target, "clear")
  if width >= 40 and height >= 12 then
    drawCornerLayout(context.target, frame, settings, status, width, height)
  else
    drawCompact(context.target, frame, settings, active, status, width)
  end

  return {
    updated = true,
    kind = context.kind,
    targetName = context.targetName,
    width = width,
    height = height,
  }
end

return hud
