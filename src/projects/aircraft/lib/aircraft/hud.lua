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

local function compactNumber(value, digits)
  if type(value) ~= "number" then
    return "?"
  end

  local absolute = math.abs(value)
  if absolute >= 100 then
    return fixed(value, 0)
  end

  return fixed(value, digits or 1)
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

local function readValue(read)
  if type(read) == "table" and read.ok and type(read.value) == "number" then
    return read.value
  end

  return nil
end

local function firstNumber(...)
  local values = { ... }

  for _, value in ipairs(values) do
    if type(value) == "number" then
      return value
    end
  end

  return nil
end

local function telemetryValue(roleTelemetry, key)
  return readValue(roleTelemetry and roleTelemetry[key])
end

local function minMax(values)
  local minValue = nil
  local maxValue = nil

  for _, role in ipairs(ROLE_ORDER) do
    local value = values and values[role]
    if type(value) == "number" then
      if not minValue or value < minValue then
        minValue = value
      end
      if not maxValue or value > maxValue then
        maxValue = value
      end
    end
  end

  return minValue, maxValue
end

local function statusText(frame, mixed, settings)
  if mixed.correctionLimited then
    return "correction capped"
  elseif frame.abortReason then
    return frame.abortReason
  end

  return "maxCorr " .. fixed(settings.maxCorrection, 2)
end

local function roleText(role, mixed, telemetry)
  local signal = mixed.signals and mixed.signals[role]
  local power = mixed.power and mixed.power[role]
  local roleTelemetry = telemetry and telemetry.roles and telemetry.roles[role]
  local readSignal = telemetryValue(roleTelemetry, "signal")
  local speed = firstNumber(
    telemetryValue(roleTelemetry, "outputSpeed"),
    telemetryValue(roleTelemetry, "speed")
  )
  local rotorAirflow = telemetryValue(roleTelemetry, "rotorAirflow")
  local rotorThrust = telemetryValue(roleTelemetry, "rotorThrust")
  local rotorAngle = telemetryValue(roleTelemetry, "rotorAngle")
  local rotorSailPower = telemetryValue(roleTelemetry, "rotorSailPower")
  local rotorSpeed = telemetryValue(roleTelemetry, "rotorSpeed")
  local rotorAngularSpeed = telemetryValue(roleTelemetry, "rotorAngularSpeed")
  local rotorActive = roleTelemetry and roleTelemetry.rotorActive
  local powerText = "?"
  local readText = ""
  local speedText = "out?"
  local rotorText = "rotor ?"
  local activeText = ""

  if type(power) == "number" then
    powerText = fixed(power, 1)
  end

  if type(readSignal) == "number" then
    readText = " rd " .. tostring(readSignal)
  end

  if type(speed) == "number" then
    speedText = "out" .. compactNumber(speed, 0)
  end

  if type(rotorSpeed) == "number" and speedText == "out?" then
    speedText = "rot" .. compactNumber(rotorSpeed, 0)
  elseif type(rotorSpeed) == "number" then
    speedText = speedText .. " r" .. compactNumber(rotorSpeed, 0)
  elseif type(rotorAngularSpeed) == "number" then
    speedText = speedText .. " av" .. compactNumber(rotorAngularSpeed, 0)
  end

  if rotorActive and rotorActive.ok and type(rotorActive.value) == "boolean" then
    activeText = rotorActive.value and " on" or " off"
  end

  if type(rotorAirflow) == "number" and type(rotorThrust) == "number" then
    rotorText = "air" .. compactNumber(rotorAirflow, 1) .. " th" .. compactNumber(rotorThrust, 1)
  elseif type(rotorAirflow) == "number" and type(rotorAngle) == "number" then
    rotorText = "air" .. compactNumber(rotorAirflow, 1) .. " a" .. compactNumber(rotorAngle, 0)
  elseif type(rotorAirflow) == "number" then
    rotorText = "air" .. compactNumber(rotorAirflow, 1)
  elseif type(rotorThrust) == "number" then
    rotorText = "th" .. compactNumber(rotorThrust, 1)
  elseif type(rotorAngle) == "number" then
    rotorText = "ang" .. compactNumber(rotorAngle, 0)
  elseif type(rotorSailPower) == "number" then
    rotorText = "sail" .. compactNumber(rotorSailPower, 0)
  elseif type(rotorSpeed) == "number" then
    rotorText = "rot" .. compactNumber(rotorSpeed, 0)
  end

  if type(rotorAngle) == "number" and type(rotorSailPower) == "number" and #rotorText < 14 then
    rotorText = rotorText .. " s" .. compactNumber(rotorSailPower, 0)
  end

  return {
    ROLE_LABELS[role] .. " sig " .. tostring(signal or "?") .. readText,
    "p" .. powerText .. " " .. speedText,
    rotorText .. activeText,
  }
end

local function drawRolePanel(target, role, x, y, width, mixed, telemetry, alignRight)
  local lines = roleText(role, mixed, telemetry)

  writeAt(target, x, y, lines[1], width, alignRight)
  writeAt(target, x, y + 1, lines[2], width, alignRight)
  writeAt(target, x, y + 2, lines[3], width, alignRight)
end

local function timingText(frame)
  if type(frame.dt) ~= "number" or frame.dt <= 0 then
    return "dt ? hz ?"
  end

  return "dt " .. fixed(frame.dt, 2) .. " hz " .. fixed(1 / frame.dt, 1)
end

local function costText(frame)
  local parts = {}

  if frame.telemetry and type(frame.telemetry.elapsed) == "number" then
    table.insert(parts, "tel " .. fixed(frame.telemetry.elapsed * 1000, 0) .. "ms")
  end

  if frame.nixies and frame.nixies.updated and type(frame.nixies.elapsed) == "number" then
    table.insert(parts, "nix " .. fixed(frame.nixies.elapsed * 1000, 0) .. "ms")
  end

  if #parts == 0 then
    return ""
  end

  return table.concat(parts, " ")
end

local function spreadText(mixed)
  local signalMin, signalMax = minMax(mixed.signals)
  local powerMin, powerMax = minMax(mixed.power)
  local parts = {}

  if signalMin and signalMax then
    table.insert(parts, "sig " .. tostring(signalMin) .. "-" .. tostring(signalMax))
  end
  if powerMin and powerMax then
    table.insert(parts, "pwr " .. fixed(powerMin, 1) .. "-" .. fixed(powerMax, 1))
  end

  return table.concat(parts, " ")
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
  writeLine(target, 8, timingText(frame), width)
  if costText(frame) ~= "" then
    writeLine(target, 9, costText(frame), width)
    writeLine(target, 10, statusText(frame, mixed, settings), width)
  else
    writeLine(target, 9, statusText(frame, mixed, settings), width)
  end
end

local function drawCornerLayout(target, frame, settings, status, width, height)
  local mixed = frame.mixed or {}
  local telemetry = frame.telemetry
  local panelWidth = math.max(12, math.min(18, math.floor(width / 2) - 1))
  local rightX = width - panelWidth + 1
  local bottomY = math.max(8, height - 3)
  local centerY = math.max(5, math.floor(height / 2) - 1)

  writeCentered(target, 1, "AIRCRAFT STABILIZE " .. status, width)
  writeCentered(target, 2, "t " .. fixed(frame.elapsed, 1) .. "/" .. fixed(settings.seconds, 1) .. "s  base " .. fixed(settings.basePower, 1), width)

  drawRolePanel(target, "front_left", 1, 3, panelWidth, mixed, telemetry, false)
  drawRolePanel(target, "front_right", rightX, 3, panelWidth, mixed, telemetry, true)
  drawRolePanel(target, "rear_left", 1, bottomY, panelWidth, mixed, telemetry, false)
  drawRolePanel(target, "rear_right", rightX, bottomY, panelWidth, mixed, telemetry, true)

  if centerY + 3 < bottomY then
    writeCentered(target, centerY, "err deg A1=" .. signed(degrees(mixed.error1), 1) .. " A2=" .. signed(degrees(mixed.error2), 1), width)
    writeCentered(target, centerY + 1, "rate A1=" .. signed(mixed.rate1, 2) .. " A2=" .. signed(mixed.rate2, 2), width)
    writeCentered(target, centerY + 2, "corr A1=" .. signed(mixed.correction1, 2) .. " A2=" .. signed(mixed.correction2, 2), width)
    writeCentered(target, centerY + 3, timingText(frame), width)
    if spreadText(mixed) ~= "" and centerY + 4 < bottomY then
      writeCentered(target, centerY + 4, spreadText(mixed), width)
    end
  end

  local footer = statusText(frame, mixed, settings)
  local costs = costText(frame)
  if costs ~= "" then
    footer = footer .. "  " .. costs
  end
  writeCentered(target, height, footer, width)
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

local function updateDue(context, frame, force)
  if not context.enabled or not context.target then
    return false, context.skipped or "hud disabled"
  end

  local elapsed = number(frame.elapsed)
  if not force and context.lastElapsed and elapsed - context.lastElapsed < context.settings.interval then
    return false, "hud interval"
  end

  return true, nil
end

function hud.shouldUpdate(context, frame, force)
  local due = updateDue(context, frame, force)

  return due == true
end

function hud.update(context, frame, settings, active, force)
  local due, skipped = updateDue(context, frame, force)
  if not due then
    return {
      updated = false,
      skipped = skipped,
    }
  end

  context.lastElapsed = number(frame.elapsed)

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
