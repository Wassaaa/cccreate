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
  "q",
  "w",
  "e",
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

local function toneRow(key, value, explanation, tone)
  local result = row(key, value, explanation)
  result.tone = tone
  return result
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

  local actuator = {}
  add(actuator, config, "actuator.type", "Output backend used by stabilize: redstone_signal keeps the existing analog path; rotation_speed writes target RPM.", "aircraft config actuator-type rotation_speed")
  add(actuator, config, "actuator.redstoneSignal.roleFamily", "Scan role family used by the redstone backend.")
  add(actuator, config, "actuator.rotationSpeed.roleFamily", "Scan role family used by rotation-speed controllers.", nil)
  add(actuator, config, "actuator.rotationSpeed.setter", "Setter used for speed actuators. Create Rotation Speed Controllers expose setTargetSpeed.")
  add(actuator, config, "actuator.rotationSpeed.getter", "Getter used for speed actuator status. Create Rotation Speed Controllers expose getTargetSpeed.")
  add(actuator, config, "actuator.rotationSpeed.idleRpm", "Target RPM at zero PD power demand.")
  add(actuator, config, "actuator.rotationSpeed.powerRpm", "RPM added at full PD power demand before sign and clamping.", "aircraft config rotation-speed 256 0 1 0 -256 256")
  add(actuator, config, "actuator.rotationSpeed.brakeRpm", "Target RPM written by brake-on-exit for the rotation_speed backend.")
  add(actuator, config, "actuator.rotationSpeed.minRpm", "Minimum target RPM allowed by the rotation_speed backend.")
  add(actuator, config, "actuator.rotationSpeed.maxRpm", "Maximum target RPM allowed by the rotation_speed backend.")
  add(actuator, config, "actuator.rotationSpeed.sign", "Set to -1 if positive PD power needs negative RPM on this drivetrain.")
  add(actuator, config, "actuator.rotationSpeed.autoRoleSigns", "When true, infer per-role RPM polarity from speed-controller to rotor-bearing geometry in the scan.", "aircraft config rotation-speed-signs auto")
  add(actuator, config, "actuator.rotationSpeed.roleSigns", "Manual per-role polarity override. Values multiply actuator.rotationSpeed.sign.", "aircraft config rotation-speed-signs 1 1 -1 -1")

  local orientation = {}
  add(orientation, config, "frontAxis", "Manual aircraft-front axis. nil lets scan infer it from side peripherals near the computer.", "aircraft config axes +Z +X")
  add(orientation, config, "leftAxis", "Manual aircraft-left axis. This combines with frontAxis to map front_left/front_right/rear_left/rear_right.")

  local scan = {}
  add(scan, config, "scan.xRadius", "Horizontal scan radius to aircraft left/right.", "aircraft scan --x-radius 8")
  add(scan, config, "scan.yRadius", "Vertical scan radius above/below the router.")
  add(scan, config, "scan.zRadius", "Horizontal scan radius to aircraft front/back.")
  add(scan, config, "scan.sampleLimit", "Maximum number of safe getter samples captured per found peripheral.")
  add(scan, config, "scan.errorLimit", "Maximum stored scan errors per error list.")
  add(scan, config, "scan.parallelism", "Worker count for routed scan calls. 1 is sequential; larger values increase concurrent router calls.", "aircraft config scan-parallelism 32")

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

  local yaw = {}
  add(yaw, config, "yaw.enabled", "When true, stabilize damps yaw rate by tilting gyroscopic propeller bearings with setManualTarget.", "aircraft config yaw true 0.15 8 1 0.08")
  add(yaw, config, "yaw.rateKd", "Yaw-rate damping gain. Higher values command more tilt for the same spin rate.")
  add(yaw, config, "yaw.maxTiltDeg", "Maximum manual yaw tilt in degrees. Gyroscopic propeller bearings hard-clamp at 12 degrees.")
  add(yaw, config, "yaw.deadbandDegPerSecond", "Yaw rates below this are ignored to avoid twitching around zero.")
  add(yaw, config, "yaw.sign", "Use -1 if the first small applied yaw run increases spin instead of damping it.")
  add(yaw, config, "yaw.commandLateral", "How hard a held Q/E controller yaw command pushes before maxTiltDeg clamps the gyro target.", "aircraft stabilize --controller --yaw-command 0.08")
  add(yaw, config, "yaw.clearOnExit", "When true, stabilize clears manual gyro bearing targets on exit.")

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
  add(kill, config, "killSwitch.source", "key is keyboard-only; side/router add a physical redstone check.", "aircraft config killswitch-source key")
  add(kill, config, "killSwitch.side", "Computer side read for source=side.")
  add(kill, config, "killSwitch.activeHigh", "If true, signal on means stop. If false, signal off means stop.")
  add(kill, config, "killSwitch.keyEnabled", "Whether controller key input can trip the kill switch.", "aircraft config killswitch-key true k")
  add(kill, config, "killSwitch.key", "Controller key name used for the kill switch.")
  add(kill, config, "killSwitch.binding", "Redstone-router coordinate and side for source=router.")

  local reports = {}
  add(reports, config, "reportPath", "Local scan cache path used by later aircraft commands.")

  return {
    section("Safety and Output", safety),
    section("Actuator Backend", actuator),
    section("Scan", scan),
    section("Orientation and Level", orientation),
    section("Stabilizer", stabilize, "axis1 is roll/A-D/left-right. axis2 is pitch/W-S/front-back."),
    section("Yaw Gyros", yaw),
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
    or math.abs(tonumber(control.yaw) or 0) > 0.0001
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
    yawActiveFrames = 0,
    yawSkippedFrames = 0,
    controllerActiveFrames = 0,
    pressed = {},
    signalRanges = {},
    outputRanges = {},
    powerRanges = {},
  }

  for _, frame in ipairs(report.frames or {}) do
    stats.frames = stats.frames + 1
    local mixed = frame.mixed or {}
    local yaw = frame.yaw or mixed.yaw or {}
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
    if yaw.enabled and not yaw.skipped then
      stats.yawActiveFrames = stats.yawActiveFrames + 1
    elseif yaw.enabled and yaw.skipped then
      stats.yawSkippedFrames = stats.yawSkippedFrames + 1
    end
    if type(yaw.yawRate) == "number" then
      stats.peakYawRate = math.max(stats.peakYawRate or 0, math.abs(yaw.yawRate))
    end
    if controlsActive(control) then
      stats.controllerActiveFrames = stats.controllerActiveFrames + 1
    end

    for _, key in ipairs(control.pressed or {}) do
      stats.pressed[key] = true
    end

    for _, role in ipairs(ROLE_ORDER) do
      updateRange(stats.signalRanges, role, mixed.signals and mixed.signals[role])
      updateRange(stats.outputRanges, role, mixed.outputs and mixed.outputs[role])
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
  local finalYaw = stats.final and (stats.final.yaw or (stats.final.mixed and stats.final.mixed.yaw)) or {}
  local actuatorSettings = report.actuators and report.actuators.settings or settings.actuator or {}
  local outputLabel = actuatorSettings.outputLabel or "output"
  local recovery = report.recoverySummary or {}
  local recoveryTest = report.recoveryTest or {}

  local runRows = {}
  addTextRow(runRows, "kind", report.kind, "Report kind.")
  addTextRow(runRows, "applied", report.applied, "true means outputs were actually written. false means dry-run or blocked.")
  addTextRow(runRows, "basePower", request.basePower or settings.basePower, "Power before stabilizer correction and controller throttle.")
  addTextRow(runRows, "elapsed", timing.elapsed, "Measured run time in seconds.")
  addTextRow(runRows, "targetHz", timing.targetHz, "Requested loop rate from stabilize.interval.")
  addTextRow(runRows, "actualHz", timing.actualHz, "Cumulative measured loop rate.")
  addTextRow(runRows, "rollingActualHz", timing.rollingActualHz, "Measured loop rate over the most recent timing window.")
  addTextRow(runRows, "missedFrames", timing.missedFrames or timing.deadlineMisses or 0, "Frames whose measured work exceeded the requested interval.")
  addTextRow(runRows, "avgFrameSeconds", timing.avgFrameSeconds or 0, "Average measured frame work time.")
  addTextRow(runRows, "maxFrameSeconds", timing.maxFrameSeconds or 0, "Largest measured frame work time.")
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
  addTextRow(stabilizerRows, "actuator.type", actuatorSettings.type, "Actuator backend that received the mixed outputs.")
  addTextRow(stabilizerRows, "actuator.roleFamily", actuatorSettings.roleFamily, "Scan role family used for actuator writes.")
  addTextRow(stabilizerRows, "actuator.method", finalMixed.actuator and finalMixed.actuator.method or actuatorSettings.setter, "Setter selected for actuator writes.")
  addTextRow(stabilizerRows, "outputRanges", rangeText(stats.outputRanges), "Applied " .. tostring(outputLabel) .. " ranges sent to the four actuator roles.")
  addTextRow(stabilizerRows, "signalRanges", rangeText(stats.signalRanges), "Compatibility field: redstone signals, or backend outputs when not using redstone.")
  addTextRow(stabilizerRows, "powerRanges", rangeText(stats.powerRanges), "Mixed power demand ranges before backend conversion.")

  local yawRows = {}
  addTextRow(yawRows, "yaw.enabled", settings.yaw and settings.yaw.enabled, "Whether yaw gyro damping was enabled for this run.")
  addTextRow(yawRows, "yawActiveFrames", stats.yawActiveFrames, "Frames where yaw targets were computed from nav orientation and gyro bearing roles.")
  addTextRow(yawRows, "yawSkippedFrames", stats.yawSkippedFrames, "Frames where yaw was enabled but skipped because a dependency was missing or errored.")
  addTextRow(yawRows, "finalYawRate", degPerSecondText(finalYaw.yawRate), "Last yaw angular rate from gimbal getAngularRatesRad()[2].")
  addTextRow(yawRows, "peakYawRate", degPerSecondText(stats.peakYawRate), "Largest absolute yaw rate kept in the report.")
  addTextRow(yawRows, "finalYawTilt", finalYaw.tiltDeg and (valueText(finalYaw.tiltDeg) .. " deg") or "n/a", "Last manual gyro tilt requested for yaw damping.")
  addTextRow(yawRows, "finalYawLateral", finalYaw.lateral, "Last sideways thrust ratio before converting to manual targets.")
  addTextRow(yawRows, "finalYawCommand", finalYaw.commandYaw, "Last controller yaw request. Q and E are opposite signs before yaw.sign is applied.")
  addTextRow(yawRows, "finalYawCommandLateral", finalYaw.commandLateral, "Last lateral contribution from Q/E before clamping.")
  addTextRow(yawRows, "yawSkipped", finalYaw.skipped or "none", "Why the last yaw frame skipped, if it did.")
  addTextRow(yawRows, "yawSign", settings.yaw and settings.yaw.sign, "Invert this if a small applied run increases spin.")

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
      section("Yaw Gyros", yawRows),
      section("Controller and Recovery", controllerRows),
    },
  }, stats
end

local function sortedKeys(map)
  local keys = {}

  for key, _ in pairs(map or {}) do
    table.insert(keys, key)
  end

  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)

  return keys
end

local function listText(values, limit)
  local parts = {}
  limit = limit or 5

  for index, value in ipairs(values or {}) do
    if index > limit then
      table.insert(parts, "+" .. tostring(#values - limit))
      break
    end

    table.insert(parts, tostring(value))
  end

  if #parts == 0 then
    return "none"
  end

  return table.concat(parts, ", ")
end

local function coordText(coord)
  if type(coord) ~= "table" then
    return "?"
  end

  return "("
    .. tostring(coord.x)
    .. ","
    .. tostring(coord.y)
    .. ","
    .. tostring(coord.z)
    .. ")"
end

local function speedText(group)
  if type(group) ~= "table" then
    return "n/a"
  end

  if group.speedMin == nil and group.speedMax == nil then
    return "n/a"
  end

  if group.speedMin == group.speedMax then
    return valueText(group.speedMin)
  end

  return valueText(group.speedMin) .. ".." .. valueText(group.speedMax)
end

local function stressText(group)
  if type(group) ~= "table" then
    return "n/a"
  end

  return "impact "
    .. valueText(group.stressImpact or 0)
    .. " / contribution "
    .. valueText(group.stressContribution or 0)
end

local function kindCountsText(kindCounts)
  local parts = {}

  for _, key in ipairs(sortedKeys(kindCounts)) do
    table.insert(parts, tostring(key) .. "=" .. tostring(kindCounts[key]))
  end

  if #parts == 0 then
    return "none"
  end

  return table.concat(parts, ", ")
end

local function groupTone(group)
  if type(group) ~= "table" then
    return "warn"
  end

  if group.overstressed then
    return "bad"
  end

  if #(group.consumers or {}) > 0 and #(group.drivers or {}) == 0 then
    return "warn"
  end

  return "ok"
end

local function groupRows(groups, ids, limit)
  local rows = {}
  limit = limit or 24

  for index, id in ipairs(ids or {}) do
    if index > limit then
      table.insert(rows, toneRow("more", tostring(#ids - limit), "Additional groups omitted from this compact tab. Use Raw JSON for the full graph.", "info"))
      break
    end

    local group = groups and groups[id] or {}
    local value = "nodes="
      .. tostring(#(group.nodeIds or {}))
      .. " roots="
      .. tostring(#(group.roots or {}))
      .. " leaves="
      .. tostring(#(group.leaves or {}))
      .. " drivers="
      .. tostring(#(group.drivers or {}))
      .. " consumers="
      .. tostring(#(group.consumers or {}))
      .. " speed="
      .. speedText(group)

    local explanation = stressText(group)
      .. "; kinds "
      .. kindCountsText(group.kindCounts)
      .. "; subnetworks "
      .. listText(group.subnetworks, 4)

    table.insert(rows, toneRow(id, value, explanation, groupTone(group)))
  end

  return rows
end

local function nodeLabel(node)
  if type(node) ~= "table" then
    return "missing"
  end

  local parts = {
    tostring(node.kind or "?"),
    coordText(node.coord),
  }

  if node.speed ~= nil then
    table.insert(parts, "speed=" .. valueText(node.speed))
  end

  return table.concat(parts, " ")
end

local function leafRows(scada, limit)
  local rows = {}
  limit = limit or 32

  for index, leafId in ipairs(scada.leafIds or {}) do
    if index > limit then
      table.insert(rows, toneRow("more", tostring(#scada.leafIds - limit), "Additional leaves omitted from this compact tab. Use Raw JSON for the full graph.", "info"))
      break
    end

    local node = scada.nodes and scada.nodes[leafId]
    local control = scada.leafControls and scada.leafControls[leafId] or {}
    local path = control.sourcePath and control.sourcePath.ids or {}
    local driver = control.upstreamDriverId
    local value = nodeLabel(node) .. " driver=" .. tostring(driver or "nil")
    local explanation = "source path " .. listText(path, 8)
    local tone = driver and "ok" or "warn"

    if control.sourcePath and control.sourcePath.stoppedBy == "cycle" then
      tone = "bad"
      explanation = explanation .. "; cycle detected"
    elseif control.sourcePath and control.sourcePath.stoppedBy == "missing_source" then
      explanation = explanation .. "; source id not in scan"
    end

    table.insert(rows, toneRow(leafId, value, explanation, tone))
  end

  return rows
end

local function missingRows(title, missing)
  local rows = {}

  for _, id in ipairs(sortedKeys(missing)) do
    local entry = missing[id] or {}
    table.insert(rows, toneRow(id, "referenced by " .. listText(entry.referencedBy, 8), title, "warn"))
  end

  return rows
end

local function warningRows(scada)
  local rows = {}

  for index, warning in ipairs(scada.warnings or {}) do
    table.insert(rows, toneRow(
      tostring(index) .. ":" .. tostring(warning.kind or "warning"),
      valueText(warning.details),
      "Generated while building the kinetic SCADA graph.",
      warning.kind == "source_cycle" and "bad" or "warn"
    ))
  end

  return rows
end

function reportTabs.kineticScadaTab(report)
  local scada = report.kineticScada
    or (report.summary and report.summary.kineticScada and { summary = report.summary.kineticScada })
    or {}
  local summary = scada.summary or {}

  local summaryRows = {
    toneRow("nodes", summary.nodes or 0, "Kinetic peripherals with a SCADA self id.", (summary.nodes or 0) > 0 and "ok" or "info"),
    toneRow("networks", summary.networks or 0, "Unique kinetic network ids.", (summary.networks or 0) > 0 and "ok" or "info"),
    toneRow("subnetworks", summary.subnetworks or 0, "Speed zones keyed by subnetwork anchor id.", (summary.subnetworks or 0) > 0 and "ok" or "info"),
    toneRow("edges", tostring(summary.resolvedEdges or 0) .. "/" .. tostring(summary.edges or 0), "Resolved immediate source links over total source references.", summary.edges == summary.resolvedEdges and "ok" or "warn"),
    toneRow("drivers", summary.drivers or 0, "Nodes with recognized control methods such as setSignal or setTargetSpeed.", (summary.drivers or 0) > 0 and "ok" or "warn"),
    toneRow("consumers", summary.consumers or 0, "Nodes that consume stress or report kind=consumer.", "info"),
    toneRow("generators", summary.generators or 0, "Nodes that contribute stress capacity or report kind=generator.", "info"),
    toneRow("leaves", summary.leaves or 0, "Nodes with no scanned children.", "info"),
    toneRow("unnetworked", summary.unnetworked or 0, "SCADA nodes that reported nil network id. This can be normal for disconnected parts.", (summary.unnetworked or 0) > 0 and "warn" or "ok"),
    toneRow("overstressed", summary.overstressedNodes or 0, "Nodes reporting an overstressed network.", (summary.overstressedNodes or 0) > 0 and "bad" or "ok"),
    toneRow("warnings", summary.warnings or 0, "Graph builder warnings such as missing references or duplicate ids.", (summary.warnings or 0) > 0 and "warn" or "ok"),
  }

  local sections = {
    section("SCADA Summary", summaryRows, "Green rows are ready, yellow rows need interpretation, red rows are active problems."),
  }

  local networkRows = groupRows(scada.networks, scada.networkIds, 18)
  if #networkRows > 0 then
    table.insert(sections, section("Networks", networkRows, "One row per kinetic network id. Drivers are controllable nodes discovered inside that network."))
  end

  local subnetworkRows = groupRows(scada.subnetworks, scada.subnetworkIds, 18)
  if #subnetworkRows > 0 then
    table.insert(sections, section("Subnetworks", subnetworkRows, "Speed zones grouped by subnetwork anchor id."))
  end

  local leaves = leafRows(scada, 32)
  if #leaves > 0 then
    table.insert(sections, section("Leaves And Upstream Drivers", leaves, "Generic leaf nodes and their nearest upstream controllable node, if one was scanned."))
  end

  local missingSources = missingRows("Source id was referenced but the source block was not in this scan.", scada.missingSourceIds)
  if #missingSources > 0 then
    table.insert(sections, section("Missing Source IDs", missingSources))
  end

  local missingAnchors = missingRows("Subnetwork anchor id was referenced but the anchor block was not in this scan.", scada.missingAnchorIds)
  if #missingAnchors > 0 then
    table.insert(sections, section("Missing Anchor IDs", missingAnchors))
  end

  local warnings = warningRows(scada)
  if #warnings > 0 then
    table.insert(sections, section("Warnings", warnings))
  end

  return {
    id = "aircraft-kinetic-scada",
    label = "Kinetic SCADA",
    title = "Kinetic SCADA Topology",
    note = "Derived from Create: Avionics self/source/network/subnetwork ids captured during scan. Raw JSON contains the full graph.",
    sections = sections,
  }
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
      { label = "Hz", value = timing.rollingActualHz or timing.actualHz or "n/a" },
      { label = "Misses", value = timing.missedFrames or timing.deadlineMisses or 0 },
      { label = "Peak Tilt", value = stats and (degText(math.max(stats.peakAxis1 or 0, stats.peakAxis2 or 0))) or "n/a" },
      { label = "Stop", value = timing.stopReason or report.abortReason or settings.mode or "n/a" },
    }
    return
  end

  if report.kind == "aircraft_scan" or report.kind == "aircraft_status" then
    local scada = report.kineticScada or {}
    local scanSummary = report.summary or {}
    local summary = scada.summary or (report.summary and report.summary.kineticScada) or {}
    human.metrics = {
      { label = "Kind", value = report.kind },
      { label = "Scanned", value = scanSummary.scanned or "n/a" },
      { label = "Found", value = scanSummary.found or "n/a" },
      { label = "Scan Workers", value = scanSummary.parallelism or "n/a" },
      { label = "SCADA Nodes", value = summary.nodes or 0 },
      { label = "Networks", value = summary.networks or 0 },
      { label = "Drivers", value = summary.drivers or 0 },
      { label = "Warnings", value = summary.warnings or 0 },
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

  if report.kind == "aircraft_scan" or report.kind == "aircraft_status" then
    insertFirstTab(human, reportTabs.kineticScadaTab(report))
  end

  if config then
    replaceTab(human, reportTabs.configTab(config, options.configSource))
  end

  setMetrics(report, stats)

  return report
end

reportTabs.copyPlain = copyPlain

return reportTabs
