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

local function findMonitor(config)
  local hudConfig = config.hud or {}

  if hudConfig.monitorName then
    return wrapMonitor(hudConfig.monitorName)
  end

  local monitor = peripheral.find("monitor")
  if monitor then
    return monitor, "monitor"
  end

  return nil, nil
end

local function call(target, method, ...)
  if type(target[method]) ~= "function" then
    return false
  end

  local ok = pcall(target[method], ...)
  return ok
end

local function line(target, row, text)
  call(target, "setCursorPos", 1, row)
  call(target, "clearLine")
  call(target, "write", text)
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

function hud.open(config, options)
  local settings = settingsFrom(config, options or {})
  local context = {
    enabled = settings.enabled,
    settings = settings,
  }

  if not context.enabled then
    context.skipped = "hud disabled"
    return context
  end

  local monitor, monitorName = findMonitor(config)
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

  call(context.target, "clear")
  line(context.target, 1, "AIRCRAFT STABILIZE " .. status)
  line(context.target, 2, "t " .. fixed(elapsed, 1) .. "/" .. fixed(settings.seconds, 1) .. "s base " .. fixed(settings.basePower, 1))
  line(context.target, 3, "err deg A1=" .. signed(degrees(mixed.error1), 1) .. " A2=" .. signed(degrees(mixed.error2), 1))
  line(context.target, 4, "rate A1=" .. signed(mixed.rate1, 2) .. " A2=" .. signed(mixed.rate2, 2))
  line(context.target, 5, "corr A1=" .. signed(mixed.correction1, 2) .. " A2=" .. signed(mixed.correction2, 2))
  line(context.target, 6, "signal " .. roleValues(mixed.signals))
  line(context.target, 7, "power  " .. roleValues(mixed.power, 1))
  if mixed.correctionLimited then
    line(context.target, 8, "correction capped")
  elseif frame.abortReason then
    line(context.target, 8, frame.abortReason)
  else
    line(context.target, 8, "maxCorr " .. fixed(settings.maxCorrection, 2))
  end

  return {
    updated = true,
    kind = context.kind,
    targetName = context.targetName,
  }
end

return hud
