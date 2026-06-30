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

local function ccColor(name)
  local palette = nil
  if type(colors) == "table" then
    palette = colors
  elseif type(colours) == "table" then
    palette = colours
  end

  return palette and palette[name] or nil
end

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

local function setStyle(target, foreground, background)
  if foreground then
    call(target, "setTextColor", foreground)
    call(target, "setTextColour", foreground)
  end
  if background then
    call(target, "setBackgroundColor", background)
    call(target, "setBackgroundColour", background)
  end
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

local function compactNumber(value)
  if type(value) ~= "number" then
    return "?"
  end

  local absolute = math.abs(value)
  if absolute >= 100 then
    return fixed(value, 0)
  end

  return fixed(value, 1)
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

local function clearRow(target, row, width, background)
  if width <= 0 then
    return
  end

  setStyle(target, nil, background or ccColor("black"))
  call(target, "setCursorPos", 1, math.max(1, row))
  call(target, "write", string.rep(" ", width))
end

local function writeAt(target, x, y, text, width, alignRight, foreground, background)
  width = width or #tostring(text or "")
  text = trim(text, width)

  if alignRight then
    x = x + width - #text
  end

  setStyle(target, foreground or ccColor("white"), background)
  call(target, "setCursorPos", math.max(1, x), math.max(1, y))
  call(target, "write", text)
end

local function writeLine(target, row, text, width, foreground, background, alignRight)
  clearRow(target, row, width, background)
  writeAt(target, 1, row, text, width, alignRight, foreground, background)
end

local function writeCentered(target, row, text, width, foreground, background)
  text = trim(text, width)
  clearRow(target, row, width, background)
  writeAt(target, math.floor((width - #text) / 2) + 1, row, text, #text, false, foreground, background)
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

local function isRotationSpeed(settings, mixed)
  return (settings and settings.actuator and settings.actuator.type == "rotation_speed")
    or (mixed and mixed.actuator and mixed.actuator.type == "rotation_speed")
end

local function baseText(settings, mixed)
  if isRotationSpeed(settings, mixed) then
    return "baseR " .. fixed((mixed and mixed.baseRpm) or (settings and settings.actuator and settings.actuator.baseRpm), 1)
  end

  return "base " .. fixed(settings and settings.basePower, 1)
end

local function correctionText(settings, mixed)
  if isRotationSpeed(settings, mixed) then
    return "corr rpm A1=" .. signed(mixed and mixed.correction1Rpm, 2)
      .. " A2=" .. signed(mixed and mixed.correction2Rpm, 2)
  end

  return "corr A1=" .. signed(mixed and mixed.correction1, 2)
    .. " A2=" .. signed(mixed and mixed.correction2, 2)
end

local function statusText(frame, mixed, settings)
  if frame.abortReason then
    return frame.abortReason
  elseif mixed.correctionLimited then
    return "correction capped"
  elseif isRotationSpeed(settings, mixed) then
    return "maxCorrR " .. fixed(settings and settings.actuator and settings.actuator.maxCorrectionRpm, 1)
  end

  return "maxCorr " .. fixed(settings.maxCorrection, 2)
end

local function timeText(frame, settings)
  if settings.forever then
    return "t " .. fixed(frame.elapsed, 1) .. "s"
  end

  return "t " .. fixed(frame.elapsed, 1) .. "/" .. fixed(settings.seconds, 1) .. "s"
end

local function timingHealth(frame)
  local timing = frame and frame.timing or {}
  return timing.summary or timing.health or timing
end

local function hzTarget(settings, health)
  local target = health and tonumber(health.targetHz)
  if target then
    return target
  end

  local interval = settings and tonumber(settings.interval) or 0
  if interval > 0 then
    return 1 / interval
  end

  return 0
end

local function timingText(frame, settings)
  local health = timingHealth(frame)
  local hz = tonumber(health.rollingActualHz) or tonumber(health.actualHz) or 0
  local target = hzTarget(settings, health)
  local targetDigits = 1
  if target >= 10 then
    targetDigits = 0
  end

  return "hz " .. fixed(hz, 1)
    .. "/" .. fixed(target, targetDigits)
    .. " miss " .. tostring(math.floor(number(health.missedFrames) + 0.5))
end

local function statusBackground(status, frame)
  if frame and frame.aborted then
    return ccColor("red")
  elseif status == "APPLY" then
    return ccColor("green")
  elseif status == "DRY" then
    return ccColor("orange") or ccColor("yellow")
  end

  return ccColor("gray")
end

local function modeSegment(label, enabled, active, skipped)
  if not enabled then
    return label .. " DIS", ccColor("gray")
  elseif active and skipped then
    return label .. " SKIP", ccColor("orange") or ccColor("yellow")
  elseif active then
    return label .. " ON", ccColor("lime") or ccColor("green")
  end

  return label .. " OFF", ccColor("lightGray") or ccColor("gray")
end

local function visibleSkip(reason)
  if reason == "hold inactive" then
    return nil
  end

  return reason
end

local function modeText(frame)
  local hold = frame and frame.hold or {}
  local target = hold.moveTarget or {}
  local holdText = modeSegment("H HOLD", hold.enabled == true, hold.active == true, hold.skipped)
  local targetText = modeSegment("T TARGET", target.enabled == true, target.active == true, target.skipped)
  local reason = visibleSkip(hold.skipped) or visibleSkip(target.skipped)

  if reason then
    return holdText .. "  " .. targetText .. "  " .. tostring(reason)
  end

  return holdText .. "  " .. targetText
end

local function modeColor(frame)
  local hold = frame and frame.hold or {}
  local target = hold.moveTarget or {}
  if visibleSkip(hold.skipped) or visibleSkip(target.skipped) then
    return ccColor("orange") or ccColor("yellow")
  elseif hold.active or target.active then
    return ccColor("lime") or ccColor("green")
  end

  return ccColor("lightGray") or ccColor("white")
end

local function velocityHoldText(frame)
  local hold = frame and frame.hold
  if not hold then
    return "hold no frame data"
  elseif hold.skipped and not hold.measuredVelocity then
    local reason = visibleSkip(hold.skipped)
    if reason then
      return "hold " .. tostring(reason)
    end

    return "hold OFF  press H for velocity hold"
  end

  local measured = hold.measuredVelocity or {}
  local desired = hold.desiredVelocity or {}
  return "vel F " .. signed(measured.front, 2)
    .. " L " .. signed(measured.left, 2)
    .. "  want F " .. signed(desired.front, 2)
    .. " L " .. signed(desired.left, 2)
end

local function holdTargetText(frame)
  local hold = frame and frame.hold or {}
  local target = hold.moveTarget or {}
  local text = nil

  if hold.active ~= true then
    text = "hold target idle"
  else
    text = "hold tgt A1 " .. signed(degrees(hold.axis1Target), 1)
      .. " A2 " .. signed(degrees(hold.axis2Target), 1)
  end

  if target.active and target.horizontalDistance then
    text = text
      .. "  nav "
      .. fixed(target.horizontalDistance, 1)
      .. "m"
  elseif target.skipped then
    text = text .. "  target " .. tostring(target.skipped)
  end

  return text
end

local function telemetryValue(telemetry, role, key)
  local read = telemetry
    and telemetry.roles
    and telemetry.roles[role]
    and telemetry.roles[role][key]

  if type(read) == "table" and read.ok then
    return read.value
  end

  return nil
end

local function telemetryNumber(telemetry, role, key)
  local value = telemetryValue(telemetry, role, key)
  if type(value) == "number" then
    return value
  end

  return nil
end

local function roleText(role, mixed, telemetry)
  local actuator = mixed.actuator or {}
  local outputLabel = actuator.outputLabel or "signal"
  local output = mixed.outputs and mixed.outputs[role] or mixed.signals and mixed.signals[role]
  local power = mixed.power and mixed.power[role]
  local powerLabel = isRotationSpeed(nil, mixed) and "rpm" or "pwr"
  local rotorThrust = telemetryNumber(telemetry, role, "rotorThrust")
  local handedness = telemetryValue(telemetry, role, "thrustHandedness")
  local powerText = "?"
  local thrustText = ""
  local handText = ""

  if type(power) == "number" then
    powerText = fixed(power, 1)
  end

  if type(rotorThrust) == "number" then
    thrustText = " th " .. compactNumber(rotorThrust)
  end
  if type(handedness) == "string" then
    handText = " " .. string.sub(handedness, 1, 1) .. "h"
  end

  return {
    ROLE_LABELS[role] .. " " .. tostring(outputLabel) .. " " .. tostring(output or "?"),
    powerLabel .. " " .. powerText .. thrustText .. handText,
  }
end

local function drawRolePanel(target, role, x, y, width, mixed, telemetry, alignRight)
  local lines = roleText(role, mixed, telemetry)

  writeAt(target, x, y, lines[1], width, alignRight, ccColor("cyan"))
  writeAt(target, x, y + 1, lines[2], width, alignRight, ccColor("lightGray") or ccColor("white"))
end

local function drawCompact(target, frame, settings, active, status, width, height)
  local mixed = frame.mixed or {}
  local outputLabel = mixed.actuator and mixed.actuator.outputLabel or "signal"
  local function line(row, text, foreground, background)
    if not height or row <= height then
      writeLine(target, row, text, width, foreground, background)
    end
  end

  line(1, " AIRCRAFT STABILIZE " .. status, ccColor("white"), statusBackground(status, frame))
  line(2, modeText(frame), modeColor(frame))
  line(3, timeText(frame, settings) .. " " .. baseText(settings, mixed), ccColor("white"))
  line(4, "err A1=" .. signed(degrees(mixed.error1), 1) .. " A2=" .. signed(degrees(mixed.error2), 1) .. " deg", ccColor("cyan"))
  line(5, velocityHoldText(frame), ccColor("lightGray") or ccColor("white"))
  line(6, correctionText(settings, mixed), ccColor("white"))
  line(7, tostring(outputLabel) .. " " .. roleValues(mixed.outputs or mixed.signals), ccColor("white"))
  if isRotationSpeed(settings, mixed) then
    line(8, "local  " .. roleValues(mixed.targetRpm or mixed.power, 1), ccColor("lightGray") or ccColor("white"))
  else
    line(8, "power  " .. roleValues(mixed.power, 1), ccColor("lightGray") or ccColor("white"))
  end
  if height and height >= 10 then
    line(9, holdTargetText(frame), ccColor("lightGray") or ccColor("white"))
    line(10, timingText(frame, settings) .. "  " .. statusText(frame, mixed, settings), ccColor("white"))
  elseif height and height >= 9 then
    line(9, timingText(frame, settings) .. "  " .. statusText(frame, mixed, settings), ccColor("white"))
  end
end

local function drawCornerLayout(target, frame, settings, status, width, height)
  local mixed = frame.mixed or {}
  local telemetry = frame.telemetry
  local panelWidth = math.max(12, math.min(18, math.floor(width / 2) - 1))
  local rightX = width - panelWidth + 1
  local bottomY = math.max(8, height - 2)
  local centerY = math.max(7, math.floor(height / 2) - 1)
  local centerLines = {
    "err deg A1=" .. signed(degrees(mixed.error1), 1) .. " A2=" .. signed(degrees(mixed.error2), 1),
    "rate A1=" .. signed(mixed.rate1, 2) .. " A2=" .. signed(mixed.rate2, 2),
    correctionText(settings, mixed),
    velocityHoldText(frame),
    holdTargetText(frame),
    timingText(frame, settings),
  }

  writeLine(target, 1, " AIRCRAFT STABILIZE " .. status, width, ccColor("white"), statusBackground(status, frame))
  writeLine(target, 2, " " .. modeText(frame), width, modeColor(frame), ccColor("black"))
  writeCentered(target, 3, timeText(frame, settings) .. "  " .. baseText(settings, mixed), width, ccColor("white"))

  drawRolePanel(target, "front_left", 1, 4, panelWidth, mixed, telemetry, false)
  drawRolePanel(target, "front_right", rightX, 4, panelWidth, mixed, telemetry, true)
  drawRolePanel(target, "rear_left", 1, bottomY, panelWidth, mixed, telemetry, false)
  drawRolePanel(target, "rear_right", rightX, bottomY, panelWidth, mixed, telemetry, true)

  for index, text in ipairs(centerLines) do
    local row = centerY + index - 1
    if row < bottomY then
      writeCentered(target, row, text, width, index == 1 and ccColor("cyan") or ccColor("white"))
    end
  end

  writeLine(target, height, " " .. statusText(frame, mixed, settings), width, ccColor("white"), ccColor("gray"))
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

  setStyle(context.target, ccColor("white"), ccColor("black"))
  call(context.target, "clear")
  if width >= 40 and height >= 12 then
    drawCornerLayout(context.target, frame, settings, status, width, height)
  else
    drawCompact(context.target, frame, settings, active, status, width, height)
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
