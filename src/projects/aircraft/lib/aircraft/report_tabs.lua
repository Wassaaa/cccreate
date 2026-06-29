local reportTabs = {}

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

local BINDING_ORDER = {
  "w",
  "shift",
  "a",
  "s",
  "d",
  "space",
  "k",
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

local function round(value, places)
  if type(value) ~= "number" then
    return value
  end

  local factor = 10 ^ (places or 2)
  if value >= 0 then
    return math.floor(value * factor + 0.5) / factor
  end

  return math.ceil(value * factor - 0.5) / factor
end

local function degrees(radians)
  if type(radians) ~= "number" then
    return nil
  end

  return radians * 180 / math.pi
end

local function valueText(value)
  if value == nil then
    return "nil"
  end

  if type(value) == "number" then
    return tostring(round(value, 3))
  end

  if type(value) == "string" or type(value) == "boolean" then
    return tostring(value)
  end

  if textutils and textutils.serialize then
    local ok, serialized = pcall(textutils.serialize, value)
    if ok then
      serialized = string.gsub(serialized, "\n", " ")
      if #serialized > 96 then
        return string.sub(serialized, 1, 93) .. "..."
      end

      return serialized
    end
  end

  return tostring(value)
end

local function at(root, path)
  local current = root
  for part in string.gmatch(path, "[^.]+") do
    if type(current) ~= "table" then
      return nil
    end
    current = current[part]
  end

  return current
end

local function row(key, value, explanation, command, label)
  return {
    key = key,
    label = label or key,
    value = copyPlain(value),
    displayValue = valueText(value),
    explanation = explanation,
    command = command,
  }
end

local function add(rows, config, key, explanation, command, label)
  table.insert(rows, row(key, at(config, key), explanation, command, label))
end

local function section(title, rows, note)
  return {
    title = title,
    note = note,
    rows = rows,
  }
end

local function bindingText(binding)
  if type(binding) ~= "table" then
    return "nil"
  end

  return tostring(binding.x)
    .. ","
    .. tostring(binding.y)
    .. ","
    .. tostring(binding.z)
    .. " "
    .. tostring(binding.side)
end

local function configSections(config)
  config = config or {}

  local safety = {}
  add(safety, config, "dryRun", "Master safety. When true, --apply reports what it would do but does not write actuator outputs.", "aircraft config dry-run false")
  add(safety, config, "absoluteSignalMax", "Highest redstone signal the aircraft code may send to scalar actuators.", "aircraft config max-signal 15")
  add(safety, config, "brakeSignal", "Signal written by brake and on stabilize exit. On this inverted transmission setup, higher signal means lower rotor power.", nil)
  add(safety, config, "maxAttitudeDelta", "Abort limit in radians unless a run overrides it with --max-attitude-deg. 0.785 rad is about 45 degrees.", "aircraft config stabilize-limits <maxCorrection> <maxAttitudeDelta>")
  add(safety, config, "sendWebhook", "When true, aircraft commands send their report to the configured webhook after saving locally.")

  local orientation = {}
  add(orientation, config, "frontAxis", "Manual aircraft-front axis. nil lets scan infer it from side peripherals near the computer.", "aircraft config axes +Z +X")
  add(orientation, config, "leftAxis", "Manual aircraft-left axis. This combines with frontAxis to map front_left/front_right/rear_left/rear_right.")

  local stabilize = {}
  add(stabilize, config, "stabilize.interval", "Requested control-loop interval in seconds. Lower is faster but costs more peripheral work.")
  add(stabilize, config, "stabilize.seconds", "Default stabilize duration when --seconds is not provided.")
  add(stabilize, config, "stabilize.basePower", "Default power demand before stabilization and controller additions. With inverted redstone, higher power becomes lower signal.")
  add(stabilize, config, "stabilize.axis1Kp", "Roll proportional gain. Higher reacts harder to roll angle error.", "aircraft config stabilize-gains <axis1Kp> <axis1Kd> <axis2Kp> <axis2Kd>")
  add(stabilize, config, "stabilize.axis1Kd", "Roll damping gain. Uses gimbal angular rate to resist roll rotation.")
  add(stabilize, config, "stabilize.axis2Kp", "Pitch proportional gain. Higher reacts harder to pitch angle error.")
  add(stabilize, config, "stabilize.axis2Kd", "Pitch damping gain. Uses gimbal angular rate to resist pitch rotation.")
  add(stabilize, config, "stabilize.axis1Trim", "Constant roll correction bias added every frame. Usually keep near 0 and fix balance physically when possible.", "aircraft config stabilize-trim 0 0")
  add(stabilize, config, "stabilize.axis2Trim", "Constant pitch correction bias added every frame. Usually keep near 0 and fix balance physically when possible.")
  add(stabilize, config, "stabilize.maxCorrection", "Maximum stabilizer correction power per axis before mixing into the four rotors.", "aircraft config stabilize-limits 1.5 0.785")
  add(stabilize, config, "stabilize.desaturate", "When true, shifts/scales rotor powers before clipping so pitch/roll correction survives low or high collective.", "aircraft config stabilize-desaturate true 0.75")
  add(stabilize, config, "stabilize.desaturateHeadroom", "Power margin kept away from 0 and max while desaturating, so redstone rounding does not turn a rotor fully off or full on.")
  add(stabilize, config, "stabilize.tiltCompensation", "When true, adds bounded collective power for requested pitch/roll target to offset vertical lift lost to steering.", "aircraft config stabilize-tilt-comp true 1 2")
  add(stabilize, config, "stabilize.tiltCompensationGain", "Multiplier for tilt-compensating collective power.")
  add(stabilize, config, "stabilize.tiltCompensationMaxPower", "Maximum extra power tilt compensation may add.")
  add(stabilize, config, "stabilize.signalDither", "Spreads fractional desired signals over time so redstone integer outputs average closer to the float target.", "aircraft config stabilize-dither true")
  add(stabilize, config, "stabilize.brakeOnExit", "Writes brakeSignal when stabilize exits, errors, or aborts.")
  add(stabilize, config, "stabilize.reportFrameLimit", "Maximum recent control frames kept in the saved report. Lower saves space; higher gives more history.", nil)

  local controller = {}
  add(controller, config, "controller.enabled", "Default controller enable flag. A run can still use --controller or --no-controller.", "aircraft config controller true")
  add(controller, config, "controller.type", "Controller input backend: redstone_router or keyboard.", "aircraft config controller-type keyboard")
  add(controller, config, "controller.threshold", "Minimum redstone value counted as a pressed controller input.", "aircraft config controller-threshold 1")
  add(controller, config, "controller.throttleMode", "hold keeps a retained throttle offset; momentary only adds throttle while space/shift is held.", "aircraft config controller-throttle hold <maxPower> <slewPowerPerSecond>")
  add(controller, config, "controller.throttlePower", "Maximum held throttle offset in hold mode, or momentary extra power while holding space/shift.", "aircraft config controller-tuning <throttlePower> <axis1TargetDeg> <axis2TargetDeg> <axis1Power> <axis2Power>")
  add(controller, config, "controller.axis1TargetDeg", "Requested roll target in degrees while holding A/D.")
  add(controller, config, "controller.axis2TargetDeg", "Requested pitch target in degrees while holding W/S.")
  add(controller, config, "controller.axis1Power", "Optional direct roll power mixed in while steering. 0 means steering only changes the attitude target.")
  add(controller, config, "controller.axis2Power", "Optional direct pitch power mixed in while steering. 0 means steering only changes the attitude target.")
  add(controller, config, "controller.targetSlewDegPerSecond", "How quickly requested pitch/roll targets move toward held controller inputs.", "aircraft config controller-response <targetSlewDegPerSecond> <throttleSlewPowerPerSecond>")
  add(controller, config, "controller.throttleSlewPowerPerSecond", "How quickly space/shift throttle power ramps up or returns to base.")
  local bindings = {}
  for _, key in ipairs(BINDING_ORDER) do
    local value = bindingText(config.controller and config.controller.bindings and config.controller.bindings[key])
    table.insert(bindings, row(
      "controller.bindings." .. key,
      value,
      "Redstone-router coordinate and side read for the " .. key .. " controller input. Used only when controller.type is redstone_router.",
      "aircraft config controller-bind " .. key .. " <x> <y> <z> [side]"
    ))
  end

  local display = {}
  add(display, config, "display.enabled", "Master Nixie/display collection flag for display-related commands.")
  add(display, config, "display.stabilizeEnabled", "Whether stabilize updates mapped Nixie tubes during flight.", "aircraft config stabilize-nixies true 1")
  add(display, config, "display.stabilizeInterval", "Minimum seconds between stabilize Nixie updates.")
  add(display, config, "hud.enabled", "Whether stabilize draws the monitor HUD when a monitor is available.", "aircraft config hud true")
  add(display, config, "hud.interval", "Minimum seconds between monitor HUD updates.")
  add(display, config, "hud.monitorScale", "Text scale used on the monitor HUD.")
  add(display, config, "hud.monitorName", "Optional fixed monitor peripheral name. nil means auto-detect.")

  local kill = {}
  add(kill, config, "killSwitch.enabled", "Whether stabilize checks configured kill-switch sources.", "aircraft config killswitch true front true")
  add(kill, config, "killSwitch.source", "Physical kill-switch source: side, router, or controller for key-only.", "aircraft config killswitch-router <x> <y> <z> up true")
  add(kill, config, "killSwitch.side", "Computer side read for source=side.")
  add(kill, config, "killSwitch.activeHigh", "If true, signal on means stop. If false, signal off means stop.")
  add(kill, config, "killSwitch.keyEnabled", "Whether controller key input can trip the kill switch.", "aircraft config killswitch-key true k")
  add(kill, config, "killSwitch.key", "Controller key name used for the kill switch.")
  add(kill, config, "killSwitch.binding", "Redstone-router coordinate and side for source=router.")

  local reports = {}
  add(reports, config, "reportPath", "Local scan cache path used by later aircraft commands.")

  return {
    section("Safety and Output", safety),
    section("Orientation and Level", orientation),
    section("Stabilizer", stabilize, "axis1 is roll/A-D/left-right. axis2 is pitch/W-S/front-back."),
    section("Controller", controller),
    section("Controller Bindings", bindings),
    section("Displays and HUD", display),
    section("Kill Switch", kill),
    section("Report Paths", reports),
  }
end

local function setHuman(report, title)
  report.human = report.human or {}
  report.human.title = report.human.title or title
  report.human.tabs = report.human.tabs or {}
  return report.human
end

local function replaceTab(human, tab)
  for index, existing in ipairs(human.tabs) do
    if existing.id == tab.id then
      human.tabs[index] = tab
      return
    end
  end

  table.insert(human.tabs, tab)
end

local function insertFirstTab(human, tab)
  for index, existing in ipairs(human.tabs) do
    if existing.id == tab.id then
      table.remove(human.tabs, index)
      break
    end
  end

  table.insert(human.tabs, 1, tab)
end

function reportTabs.configTab(config, source)
  return {
    id = "aircraft-config",
    label = "Config Guide",
    title = "Aircraft Config",
    note = source and ("Loaded from " .. tostring(source)) or nil,
    sections = configSections(config),
  }
end

local function updateRange(ranges, role, value)
  value = tonumber(value)
  if not value then
    return
  end

  local range = ranges[role]
  if not range then
    range = {
      min = value,
      max = value,
    }
    ranges[role] = range
    return
  end

  range.min = math.min(range.min, value)
  range.max = math.max(range.max, value)
end

local function controlsActive(control)
  if type(control) ~= "table" then
    return false
  end

  if #(control.pressed or {}) > 0 then
    return true
  end

  return math.abs(tonumber(control.axis1Target) or 0) > 0.0001
    or math.abs(tonumber(control.axis2Target) or 0) > 0.0001
    or math.abs(tonumber(control.throttlePower) or 0) > 0.0001
    or math.abs(tonumber(control.axis1Power) or 0) > 0.0001
    or math.abs(tonumber(control.axis2Power) or 0) > 0.0001
end

local function frameStats(report)
  local stats = {
    frames = 0,
    correctionLimited = 0,
    desaturatedFrames = 0,
    tiltedCompensatedFrames = 0,
    controllerActiveFrames = 0,
    pressed = {},
    signalRanges = {},
    powerRanges = {},
  }

  for _, frame in ipairs(report.frames or {}) do
    stats.frames = stats.frames + 1
    local mixed = frame.mixed or {}
    local control = frame.controller or {}

    if type(mixed.measured1) == "number" then
      stats.peakAxis1 = math.max(stats.peakAxis1 or 0, math.abs(mixed.measured1))
    end
    if type(mixed.measured2) == "number" then
      stats.peakAxis2 = math.max(stats.peakAxis2 or 0, math.abs(mixed.measured2))
    end
    if type(mixed.error1) == "number" then
      stats.peakError1 = math.max(stats.peakError1 or 0, math.abs(mixed.error1))
    end
    if type(mixed.error2) == "number" then
      stats.peakError2 = math.max(stats.peakError2 or 0, math.abs(mixed.error2))
    end
    if mixed.correctionLimited then
      stats.correctionLimited = stats.correctionLimited + 1
    end
    if mixed.desaturation
        and (math.abs(tonumber(mixed.desaturation.shift) or 0) > 0.0001
          or mixed.desaturation.scaled == true) then
      stats.desaturatedFrames = stats.desaturatedFrames + 1
    end
    if math.abs(tonumber(mixed.tiltCompensationPower) or 0) > 0.0001 then
      stats.tiltedCompensatedFrames = stats.tiltedCompensatedFrames + 1
    end
    if controlsActive(control) then
      stats.controllerActiveFrames = stats.controllerActiveFrames + 1
    end

    for _, key in ipairs(control.pressed or {}) do
      stats.pressed[key] = true
    end

    for _, role in ipairs(ROLE_ORDER) do
      updateRange(stats.signalRanges, role, mixed.signals and mixed.signals[role])
      updateRange(stats.powerRanges, role, mixed.power and mixed.power[role])
    end

    stats.final = frame
  end

  return stats
end

local function degText(value)
  local converted = degrees(value)
  if converted == nil then
    return "n/a"
  end

  return tostring(round(converted, 2)) .. " deg"
end

local function degPerSecondText(value)
  local converted = degrees(value)
  if converted == nil then
    return "n/a"
  end

  return tostring(round(converted, 2)) .. " deg/s"
end

local function rangeText(ranges)
  local parts = {}

  for _, role in ipairs(ROLE_ORDER) do
    local range = ranges and ranges[role]
    if range then
      table.insert(parts, ROLE_LABELS[role] .. " " .. valueText(range.min) .. ".." .. valueText(range.max))
    end
  end

  if #parts == 0 then
    return "n/a"
  end

  return table.concat(parts, " | ")
end

local function pressedText(pressed)
  local parts = {}

  for _, key in ipairs(BINDING_ORDER) do
    if pressed[key] then
      table.insert(parts, key)
    end
  end

  if #parts == 0 then
    return "none"
  end

  return table.concat(parts, ", ")
end

local function addTextRow(rows, key, value, explanation)
  table.insert(rows, row(key, value, explanation))
end

function reportTabs.flightOverviewTab(report)
  local stats = frameStats(report)
  local settings = report.settings or {}
  local timing = report.timing or {}
  local request = report.request or {}
  local finalMixed = stats.final and stats.final.mixed or {}
  local recovery = report.recoverySummary or {}
  local recoveryTest = report.recoveryTest or {}

  local runRows = {}
  addTextRow(runRows, "kind", report.kind, "Report kind.")
  addTextRow(runRows, "applied", report.applied, "true means outputs were actually written. false means dry-run or blocked.")
  addTextRow(runRows, "basePower", request.basePower or settings.basePower, "Power before stabilizer correction and controller throttle.")
  addTextRow(runRows, "elapsed", timing.elapsed, "Measured run time in seconds.")
  addTextRow(runRows, "stopReason", timing.stopReason, "Why the loop stopped.")
  addTextRow(runRows, "abortReason", report.abortReason or "none", "Abort reason, if the run tripped the kill switch, angle limit, or an error.")
  addTextRow(runRows, "framesKept", stats.frames, "Number of compact frames kept in this report.")
  addTextRow(runRows, "framesDropped", timing.framesDropped or 0, "Old frames dropped because of reportFrameLimit.")

  local stabilizerRows = {}
  addTextRow(stabilizerRows, "peakAxis1", degText(stats.peakAxis1), "Largest absolute roll measurement kept in the report.")
  addTextRow(stabilizerRows, "peakAxis2", degText(stats.peakAxis2), "Largest absolute pitch measurement kept in the report.")
  addTextRow(stabilizerRows, "finalAxis1", degText(finalMixed.measured1), "Last roll measurement in the report.")
  addTextRow(stabilizerRows, "finalAxis2", degText(finalMixed.measured2), "Last pitch measurement in the report.")
  addTextRow(stabilizerRows, "finalRate1", degPerSecondText(finalMixed.rate1), "Last roll angular rate.")
  addTextRow(stabilizerRows, "finalRate2", degPerSecondText(finalMixed.rate2), "Last pitch angular rate.")
  addTextRow(stabilizerRows, "maxCorrection", settings.maxCorrection, "Per-axis correction cap used by the stabilizer.")
  addTextRow(stabilizerRows, "correctionLimitedFrames", stats.correctionLimited, "How often the stabilizer hit maxCorrection.")
  addTextRow(stabilizerRows, "desaturate", settings.desaturate, "Whether the mixer shifts all rotor powers before clipping.")
  addTextRow(stabilizerRows, "desaturateHeadroom", settings.desaturateHeadroom, "Power margin reserved before redstone rounding.")
  addTextRow(stabilizerRows, "desaturatedFrames", stats.desaturatedFrames, "Frames where the mixer shifted or scaled powers to preserve pitch/roll correction.")
  addTextRow(stabilizerRows, "tiltCompensation", settings.tiltCompensation, "Whether tilt-based collective compensation was enabled.")
  addTextRow(stabilizerRows, "tiltCompensatedFrames", stats.tiltedCompensatedFrames, "Frames where tilt compensation added collective power.")
  addTextRow(stabilizerRows, "finalTiltCompPower", finalMixed.tiltCompensationPower, "Last extra power added by tilt compensation.")
  addTextRow(stabilizerRows, "maxAttitudeDelta", degText(settings.maxAttitudeDelta), "Angle error abort threshold for this run.")
  addTextRow(stabilizerRows, "angleGetter", "getAnglesRad", "Gimbal getter used for pitch/roll attitude.")
  addTextRow(stabilizerRows, "rateGetter", "getAngularRatesRad", "Gimbal getter used for damping.")
  addTextRow(stabilizerRows, "signalRanges", rangeText(stats.signalRanges), "Integer redstone signal ranges sent to the four transmissions.")
  addTextRow(stabilizerRows, "powerRanges", rangeText(stats.powerRanges), "Mixed power demand ranges before inverted signal conversion.")

  local controllerRows = {}
  addTextRow(controllerRows, "controller.enabled", report.controller and report.controller.enabled, "Whether controller input was open for this run.")
  addTextRow(controllerRows, "controller.type", report.controller and report.controller.type, "Input backend used by this run.")
  addTextRow(controllerRows, "controllerActiveFrames", stats.controllerActiveFrames, "Frames where controller or recovery input requested a target/throttle/power.")
  addTextRow(controllerRows, "pressedKeys", pressedText(stats.pressed), "Controller keys seen in kept frames.")
  addTextRow(controllerRows, "killSwitchTriggeredBy", report.abortReason == "kill switch active" and (stats.final and stats.final.killSwitch and stats.final.killSwitch.triggeredBy) or "n/a", "Kill-switch source that stopped the run, if any.")
  addTextRow(controllerRows, "recoveryPulseSeconds", recoveryTest.pulseSeconds, "Recovery-test pulse duration, if this was aircraft recover.")
  addTextRow(controllerRows, "recoveryAxis1Target", degText(recoveryTest.axis1Target), "Synthetic roll target used during the recovery pulse.")
  addTextRow(controllerRows, "recoveryAxis2Target", degText(recoveryTest.axis2Target), "Synthetic pitch target used during the recovery pulse.")
  addTextRow(controllerRows, "recoveryPeakAfterPulseAxis1", degText(recovery.peakAfterPulseAxis1), "Largest roll after the recovery pulse ended.")
  addTextRow(controllerRows, "recoveryPeakAfterPulseAxis2", degText(recovery.peakAfterPulseAxis2), "Largest pitch after the recovery pulse ended.")

  return {
    id = "aircraft-flight",
    label = "Flight Overview",
    title = "Aircraft Flight Overview",
    sections = {
      section("Run", runRows),
      section("Stabilizer", stabilizerRows),
      section("Controller and Recovery", controllerRows),
    },
  }, stats
end

local function setMetrics(report, stats)
  local human = report.human
  if not human then
    return
  end

  if report.kind == "aircraft_config" then
    human.metrics = {
      { label = "Kind", value = report.kind },
      { label = "Source", value = report.configSource or "n/a" },
      { label = "Dry Run", value = at(report.configSnapshot or {}, "dryRun") },
      { label = "Base Power", value = at(report.configSnapshot or {}, "stabilize.basePower") },
      { label = "Controller", value = at(report.configSnapshot or {}, "controller.enabled") },
    }
    return
  end

  if report.kind == "aircraft_stabilize" or report.kind == "aircraft_level_set" or report.kind == "aircraft_level_zero" then
    local timing = report.timing or {}
    local settings = report.settings or {}
    human.metrics = {
      { label = "Kind", value = report.kind },
      { label = "Applied", value = report.applied },
      { label = "Frames", value = stats and stats.frames or 0 },
      { label = "Peak Tilt", value = stats and (degText(math.max(stats.peakAxis1 or 0, stats.peakAxis2 or 0))) or "n/a" },
      { label = "Stop", value = timing.stopReason or report.abortReason or settings.mode or "n/a" },
    }
  end
end

function reportTabs.attach(report, config, options)
  if type(report) ~= "table" then
    return report
  end

  options = options or {}
  local human = setHuman(report, report.kind or "Aircraft Report")
  local stats = nil

  if report.kind == "aircraft_stabilize" then
    local flightTab
    flightTab, stats = reportTabs.flightOverviewTab(report)
    insertFirstTab(human, flightTab)
  end

  if config then
    replaceTab(human, reportTabs.configTab(config, options.configSource))
  end

  setMetrics(report, stats)

  return report
end

reportTabs.copyPlain = copyPlain

return reportTabs
