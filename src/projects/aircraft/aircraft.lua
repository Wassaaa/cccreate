local coords = require("lib.aircraft.coords")
local actuatorTest = require("lib.aircraft.actuator_test")
local controller = require("lib.aircraft.controller")
local configModel = require("lib.aircraft.config_model")
local displayLoop = require("lib.aircraft.display_loop")
local flightControl = require("lib.aircraft.flight_control")
local scanner = require("lib.aircraft.scanner")
local reporting = require("lib.aircraft.reporting")
local status = require("lib.aircraft.status")

local args = { ... }
local command = args[1] or "help"
local CONFIG_PATH = "/config/aircraft.lua"

local DEFAULT_CONFIG = {
  scan = {
    xRadius = 8,
    yRadius = 2,
    zRadius = 8,
    sampleLimit = 12,
    errorLimit = 12,
  },
  frontAxis = nil,
  leftAxis = nil,
  dryRun = true,
  absoluteSignalMax = 15,
  brakeSignal = 15,
  maxAttitudeDelta = 2,
  statusReadLimit = 8,
  reportPath = "/aircraft_scan.txt",
  stabilize = {
    interval = 0.1,
    seconds = 1,
    basePower = 0,
    axis1Kp = 4,
    axis2Kp = 4,
    axis1Kd = 0.12,
    axis2Kd = 0.2,
    axis1Trim = 0,
    axis2Trim = 0,
    yawKd = 0.2,
    yawTrim = 0,
    yawSign = 1,
    maxCorrection = 1.5,
    maxYawCorrection = 1.5,
    signalDither = true,
    brakeOnExit = true,
    reportFrameLimit = 600,
  },
  rotors = {
    applyHandednessOnStabilize = true,
    handedness = {},
  },
  display = {
    enabled = true,
    stabilizeEnabled = true,
    stabilizeInterval = 1,
  },
  hud = {
    enabled = true,
    interval = 0.5,
    monitorScale = 0.5,
    monitorName = nil,
  },
  killSwitch = {
    enabled = false,
    side = "front",
    activeHigh = true,
  },
  controller = {
    enabled = false,
    threshold = 1,
    throttlePower = 1,
    axis1TargetDeg = 5,
    axis2TargetDeg = 5,
    axis1Power = 0,
    axis2Power = 0,
    yawPower = 1,
    targetSlewDegPerSecond = 8,
    throttleSlewPowerPerSecond = 4,
    bindings = controller.defaultBindings(-1, -1, -5, "up"),
  },
  sendWebhook = true,
}

local function usage()
  print("aircraft scan [options]")
  print("aircraft status")
  print("aircraft config show")
  print("aircraft config axes <frontAxis> <leftAxis>")
  print("aircraft config dry-run <true|false>")
  print("aircraft config max-signal <0-15>")
  print("aircraft config stabilize-gains <axis1Kp> <axis1Kd> [axis2Kp] [axis2Kd]")
  print("aircraft config stabilize-trim <axis1Power> <axis2Power>")
  print("aircraft config stabilize-yaw <yawKd> [maxYawCorrection] [yawTrim] [yawSign]")
  print("aircraft config rotor-handedness <role> <right_handed|left_handed>")
  print("aircraft config stabilize-limits <maxCorrection> <maxAttitudeDelta>")
  print("aircraft config stabilize-dither <true|false>")
  print("aircraft config display <true|false>")
  print("aircraft config stabilize-nixies <true|false> [interval]")
  print("aircraft config hud <true|false>")
  print("aircraft config killswitch <true|false> [front|back|left|right|top|bottom] [activeHigh true|false]")
  print("aircraft config controller <true|false>")
  print("aircraft config controller-layout <x> <y> <z> [side]")
  print("aircraft config controller-bind <key> <x> <y> <z> [side]")
  print("aircraft config controller-tuning <throttlePower> <axis1TargetDeg> [axis2TargetDeg] [axis1Power] [axis2Power]")
  print("aircraft config controller-yaw <yawPower>")
  print("aircraft config controller-response <targetSlewDegPerSecond> [throttleSlewPowerPerSecond]")
  print("aircraft config controller-threshold <0-15>")
  print("aircraft brake [role|all] [--apply]")
  print("aircraft rotor-handedness [role|all|baseline|configured|diagonal] [right_handed|left_handed|toggle] [--apply]")
  print("aircraft controller [--seconds n] [--interval n]")
  print("aircraft displays [--seconds n] [--interval n]")
  print("aircraft stabilize [--apply] [--seconds n|--forever] [--base-power n] [--kp n] [--kd n] [--axis1-trim n] [--axis2-trim n] [--controller] [--no-hud] [--nixies] [--killswitch|--no-killswitch]")
  print("aircraft recover [--apply] [--seconds n] [--base-power n] [--axis1-target-deg n] [--axis2-target-deg n] [--axis1-power n] [--axis2-power n] [--pulse-seconds n]")
  print("aircraft signal <role|all> <0-15> [--apply] [--seconds n] [--after-signal n]")
  print("aircraft help")
  print("")
  print("Options:")
  print("  --radius <n>       set x/z radius")
  print("  --x-radius <n>     set x scan radius")
  print("  --y-radius <n>     set y scan radius")
  print("  --z-radius <n>     set z scan radius")
  print("  --sample-limit <n> max getter samples per peripheral")
  print("  --out <path>       default /aircraft_scan.txt")
  print("  --no-webhook       skip webhook output")
  print("  --hud-interval <n> stabilize HUD refresh seconds")
  print("  --nixie-interval <n> stabilize Nixie refresh seconds")
  print("  --report-frames <n> max stabilize frames kept in report")
  print("  --max-attitude-deg <n> abort when tilt error exceeds degrees")
  print("  --yaw-kd <n>       one-run yaw damping gain")
  print("  --max-yaw-correction <n> one-run yaw correction cap")
  print("")
  print("signal/brake are dry-run unless --apply is used and config dryRun=false.")
end

local function copyTable(value)
  if type(value) ~= "table" then
    return value
  end

  local result = {}
  for key, child in pairs(value) do
    result[key] = copyTable(child)
  end
  return result
end

local function mergeInto(target, source)
  if type(source) ~= "table" then
    return target
  end

  for key, value in pairs(source) do
    if type(value) == "table" and type(target[key]) == "table" then
      mergeInto(target[key], value)
    else
      target[key] = copyTable(value)
    end
  end

  return target
end

local function loadConfig()
  local config = copyTable(DEFAULT_CONFIG)

  if fs.exists(CONFIG_PATH) then
    local chunk, loadError = loadfile(CONFIG_PATH)
    if not chunk then
      error("Failed to load " .. CONFIG_PATH .. ": " .. tostring(loadError), 0)
    end

    local ok, fileConfig = pcall(chunk)
    if not ok then
      error("Failed to run " .. CONFIG_PATH .. ": " .. tostring(fileConfig), 0)
    end

    if type(fileConfig) ~= "table" then
      error(CONFIG_PATH .. " must return a table", 0)
    end

    local missingControllerBindings
    if type(fileConfig.controller) == "table" and type(fileConfig.controller.bindings) == "table" then
      missingControllerBindings = {
        q = fileConfig.controller.bindings.q == nil,
        e = fileConfig.controller.bindings.e == nil,
      }
    end

    mergeInto(config, fileConfig)
    if missingControllerBindings then
      config.controller = config.controller or {}
      config.controller.bindings = controller.completeKeyboardBindings(
        config.controller.bindings or {},
        missingControllerBindings
      )
    end

    return configModel.normalize(config), CONFIG_PATH
  end

  return configModel.normalize(config), "built-in defaults"
end

local function saveConfig(config)
  local directory = fs.getDir(CONFIG_PATH)
  if directory ~= "" and not fs.exists(directory) then
    fs.makeDir(directory)
  end

  local handle = fs.open(CONFIG_PATH, "w")
  if not handle then
    error("Could not write " .. CONFIG_PATH, 0)
  end

  handle.write(configModel.serialize(config))
  handle.close()
end

local function parseInteger(value, label)
  local number = tonumber(value)
  if not number or number ~= math.floor(number) then
    error(label .. " must be an integer", 0)
  end

  return number
end

local function parseNonNegativeInteger(value, label)
  local number = parseInteger(value, label)

  if number < 0 then
    error(label .. " must be zero or greater", 0)
  end

  return number
end

local function parseNumber(value, label)
  local number = tonumber(value)
  if not number then
    error(label .. " must be a number", 0)
  end

  return number
end

local function parseOptions(config)
  local i = 2

  while i <= #args do
    local arg = args[i]

    if arg == "--radius" then
      local radius = parseNonNegativeInteger(args[i + 1], "--radius")
      config.scan.xRadius = radius
      config.scan.zRadius = radius
      i = i + 2
    elseif arg == "--x-radius" then
      config.scan.xRadius = parseNonNegativeInteger(args[i + 1], "--x-radius")
      i = i + 2
    elseif arg == "--y-radius" then
      config.scan.yRadius = parseNonNegativeInteger(args[i + 1], "--y-radius")
      i = i + 2
    elseif arg == "--z-radius" then
      config.scan.zRadius = parseNonNegativeInteger(args[i + 1], "--z-radius")
      i = i + 2
    elseif arg == "--sample-limit" then
      config.scan.sampleLimit = parseNonNegativeInteger(args[i + 1], "--sample-limit")
      i = i + 2
    elseif arg == "--out" then
      config.reportPath = args[i + 1]
      if not config.reportPath then
        error("--out needs a path", 0)
      end
      i = i + 2
    elseif arg == "--no-webhook" then
      config.sendWebhook = false
      i = i + 1
    else
      error("Unknown aircraft option: " .. tostring(arg), 0)
    end
  end
end

local function printSummary(report, path)
  print("Aircraft scan complete")
  if report.error then
    print("Scan error: " .. tostring(report.error))
  end
  print("Router: " .. tostring(report.router and report.router.name))
  print("Router presence method: " .. tostring(report.router and report.router.presenceMethod))
  print("Bounds: " .. coords.boundsLabel(report.scanBounds))
  print("Scanned positions: " .. tostring(report.summary.scanned or 0))
  print("Presence checks: " .. tostring(report.summary.presenceChecks or 0))
  print("Presence misses: " .. tostring(report.summary.presenceMisses or 0))
  print("Presence errors: " .. tostring(report.summary.presenceErrors or 0))
  print("Wrap attempts: " .. tostring(report.summary.wrapAttempts or 0))
  print("Wrap errors: " .. tostring(report.summary.wrapErrors or report.summary.errors or 0))
  print("Found peripherals: " .. tostring(report.summary.found))
  print("Candidates:")

  for _, category in ipairs(reporting.CATEGORY_ORDER) do
    print("  " .. category .. ": " .. tostring(report.summary.categories[category] or 0))
  end

  if #report.peripherals > 0 then
    print("Candidate coordinates:")

    for _, entry in ipairs(report.peripherals) do
      print(
        "  "
          .. coords.label(entry.coord)
          .. " "
          .. table.concat(entry.categories, ",")
          .. " methods="
          .. tostring(entry.methodCount)
      )
    end
  end

  if report.orientation then
    print("Orientation:")
    print("  computerCoord=" .. coords.label(report.orientation.computerCoord))

    if report.orientation.computerCoordError then
      print("  origin note=" .. tostring(report.orientation.computerCoordError))
    end

    print("  front=" .. coords.axisLabel(report.orientation.frontVector) .. " source=" .. tostring(report.orientation.sources.frontVector))
    print("  left=" .. coords.axisLabel(report.orientation.leftVector) .. " source=" .. tostring(report.orientation.sources.leftVector))
    print("  up=" .. coords.axisLabel(report.orientation.upVector) .. " source=" .. tostring(report.orientation.sources.upVector))

    for side, hint in pairs(report.orientation.sideHints or {}) do
      if hint.ambiguous then
        print("  side " .. side .. " ambiguous matches=" .. tostring(hint.count))
      else
        print("  side " .. side .. " -> " .. coords.label(hint.coord) .. " vector=" .. coords.axisLabel(hint.vector))
      end
    end

    if report.orientation.roles then
      for family, roles in pairs(report.orientation.roles) do
        print("Suggested " .. family .. " roles:")

        for _, role in ipairs({ "front_left", "front_right", "rear_left", "rear_right" }) do
          local entry = roles[role]
          if entry then
            local details = ""
            if family == "displaySink" then
              details = " kind=" .. tostring(entry.displayKind or "?")
              if entry.targetCoord then
                details = details .. " target=" .. coords.label(entry.targetCoord)
              end
            elseif family == "rotorBearing" and entry.thrustHandedness then
              details = " handedness=" .. tostring(entry.thrustHandedness)
            end
            print("  " .. role .. "=" .. coords.label(entry.coord) .. details)
          else
            print("  " .. role .. "=missing")
          end
        end
      end
    end
  end

  print("Report: " .. path)
  if report.orientation and report.orientation.frontVector and report.orientation.leftVector then
    print("Next: run aircraft status to read the mapped parts without moving the craft.")
  else
    print("Next: configure frontAxis and leftAxis, then scan again before any control mode exists.")
  end
end

local function runScan()
  local config, source = loadConfig()
  parseOptions(config)

  print("Aircraft scan using " .. source)

  local report = scanner.scan(config)
  local path = config.reportPath or "/aircraft_scan.txt"

  reporting.save(report, path, config, { configSource = source })
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  printSummary(report, path)
end

local function runStatus()
  local config = loadConfig()

  status.run(config)
end

local function parseBoolean(value)
  if value == "true" or value == "yes" or value == "1" then
    return true
  elseif value == "false" or value == "no" or value == "0" then
    return false
  end

  error("boolean value must be true or false", 0)
end

local function normalizeRedstoneSide(side)
  local normalized = string.lower(tostring(side or "up"))
  if normalized == "top" then
    normalized = "up"
  elseif normalized == "bottom" then
    normalized = "down"
  end

  if normalized == "up"
      or normalized == "down"
      or normalized == "north"
      or normalized == "south"
      or normalized == "east"
      or normalized == "west" then
    return normalized
  end

  error("side must be up, down, north, south, east, or west", 0)
end

local function normalizeComputerSide(side)
  local normalized = string.lower(tostring(side or "front"))
  if normalized == "up" then
    normalized = "top"
  elseif normalized == "down" then
    normalized = "bottom"
  end

  if normalized == "front"
      or normalized == "back"
      or normalized == "left"
      or normalized == "right"
      or normalized == "top"
      or normalized == "bottom" then
    return normalized
  end

  error("side must be front, back, left, right, top, or bottom", 0)
end

local function validControllerKey(key)
  return key == "w"
    or key == "q"
    or key == "e"
    or key == "a"
    or key == "s"
    or key == "d"
    or key == "space"
    or key == "shift"
end

local function validRotorRole(role)
  return role == "front_left"
    or role == "front_right"
    or role == "rear_left"
    or role == "rear_right"
end

local function normalizeHandedness(value)
  local normalized = string.lower(tostring(value or ""))
  normalized = string.gsub(normalized, "-", "_")

  if normalized == "right" or normalized == "right_handed" or normalized == "r" then
    return "right_handed"
  elseif normalized == "left" or normalized == "left_handed" or normalized == "l" then
    return "left_handed"
  elseif normalized == "toggle" then
    return "toggle"
  end

  error("handedness must be right_handed, left_handed, or toggle", 0)
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

local function printConfig(config, source)
  print("aircraft config from " .. tostring(source))
  print("  frontAxis=" .. tostring(config.frontAxis))
  print("  leftAxis=" .. tostring(config.leftAxis))
  print("  dryRun=" .. tostring(config.dryRun))
  print("  absoluteSignalMax=" .. tostring(config.absoluteSignalMax))
  print("  brakeSignal=" .. tostring(config.brakeSignal))
  print("  maxAttitudeDelta=" .. tostring(config.maxAttitudeDelta))
  print("  stabilize.axis1Kp=" .. tostring(config.stabilize.axis1Kp))
  print("  stabilize.axis1Kd=" .. tostring(config.stabilize.axis1Kd))
  print("  stabilize.axis2Kp=" .. tostring(config.stabilize.axis2Kp))
  print("  stabilize.axis2Kd=" .. tostring(config.stabilize.axis2Kd))
  print("  stabilize.axis1Trim=" .. tostring(config.stabilize.axis1Trim))
  print("  stabilize.axis2Trim=" .. tostring(config.stabilize.axis2Trim))
  print("  stabilize.yawKd=" .. tostring(config.stabilize.yawKd))
  print("  stabilize.yawTrim=" .. tostring(config.stabilize.yawTrim))
  print("  stabilize.yawSign=" .. tostring(config.stabilize.yawSign))
  print("  stabilize.maxCorrection=" .. tostring(config.stabilize.maxCorrection))
  print("  stabilize.maxYawCorrection=" .. tostring(config.stabilize.maxYawCorrection))
  print("  stabilize.signalDither=" .. tostring(config.stabilize.signalDither))
  print("  rotors.applyHandednessOnStabilize=" .. tostring(config.rotors and config.rotors.applyHandednessOnStabilize))
  if config.rotors and config.rotors.handedness then
    print("  rotors.handedness overrides:")
    print("    front_left=" .. tostring(config.rotors.handedness.front_left))
    print("    front_right=" .. tostring(config.rotors.handedness.front_right))
    print("    rear_left=" .. tostring(config.rotors.handedness.rear_left))
    print("    rear_right=" .. tostring(config.rotors.handedness.rear_right))
  end
  print("  display.enabled=" .. tostring(config.display and config.display.enabled))
  print("  display.stabilizeEnabled=" .. tostring(config.display and config.display.stabilizeEnabled))
  print("  display.stabilizeInterval=" .. tostring(config.display and config.display.stabilizeInterval))
  print("  hud.enabled=" .. tostring(config.hud and config.hud.enabled))
  print("  hud.interval=" .. tostring(config.hud and config.hud.interval))
  print("  hud.monitorName=" .. tostring(config.hud and config.hud.monitorName))
  print("  killSwitch.enabled=" .. tostring(config.killSwitch and config.killSwitch.enabled))
  print("  killSwitch.side=" .. tostring(config.killSwitch and config.killSwitch.side))
  print("  killSwitch.activeHigh=" .. tostring(config.killSwitch and config.killSwitch.activeHigh))
  print("  controller.enabled=" .. tostring(config.controller and config.controller.enabled))
  print("  controller.threshold=" .. tostring(config.controller and config.controller.threshold))
  print("  controller.throttlePower=" .. tostring(config.controller and config.controller.throttlePower))
  print("  controller.axis1TargetDeg=" .. tostring(config.controller and config.controller.axis1TargetDeg))
  print("  controller.axis2TargetDeg=" .. tostring(config.controller and config.controller.axis2TargetDeg))
  print("  controller.axis1Power=" .. tostring(config.controller and config.controller.axis1Power))
  print("  controller.axis2Power=" .. tostring(config.controller and config.controller.axis2Power))
  print("  controller.yawPower=" .. tostring(config.controller and config.controller.yawPower))
  print("  controller.targetSlewDegPerSecond=" .. tostring(config.controller and config.controller.targetSlewDegPerSecond))
  print("  controller.throttleSlewPowerPerSecond=" .. tostring(config.controller and config.controller.throttleSlewPowerPerSecond))
  if config.controller and config.controller.bindings then
    print("  controller.bindings:")
    print("    shift=" .. bindingText(config.controller.bindings.shift))
    print("    a=" .. bindingText(config.controller.bindings.a))
    print("    s=" .. bindingText(config.controller.bindings.s))
    print("    d=" .. bindingText(config.controller.bindings.d))
    print("    space=" .. bindingText(config.controller.bindings.space))
    print("    q=" .. bindingText(config.controller.bindings.q))
    print("    w=" .. bindingText(config.controller.bindings.w))
    print("    e=" .. bindingText(config.controller.bindings.e))
  end
end

local function runConfigShow(config, source)
  printConfig(config, source)

  local report = {
    kind = "aircraft_config",
    command = "aircraft config show",
    createdAt = os.date("%Y-%m-%d %H:%M:%S"),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    configSource = source,
    configSnapshot = configModel.copy(configModel.normalize(config)),
  }
  local path = "/aircraft_config.txt"

  reporting.save(report, path, config, { configSource = source, localReport = false })
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  print("Config report: " .. (config.sendWebhook ~= false and "webhook" or "webhook disabled"))
end

local function runConfig()
  local config, source = loadConfig()
  local subcommand = args[2] or "show"

  if subcommand == "show" then
    runConfigShow(config, source)
    return
  elseif subcommand == "axes" then
    local front = coords.parseAxis(args[3])
    local left = coords.parseAxis(args[4])

    if not front or not left then
      error("Usage: aircraft config axes <frontAxis> <leftAxis>, example: aircraft config axes +Z +X", 0)
    end

    config.frontAxis = coords.axisLabel(front)
    config.leftAxis = coords.axisLabel(left)
    saveConfig(config)
    print("Saved aircraft axes to " .. CONFIG_PATH)
    print("  frontAxis=" .. tostring(config.frontAxis))
    print("  leftAxis=" .. tostring(config.leftAxis))
    print("Next: run aircraft scan to refresh role mappings.")
    return
  elseif subcommand == "dry-run" then
    config.dryRun = parseBoolean(args[3])
    saveConfig(config)
    print("Saved dryRun=" .. tostring(config.dryRun) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "max-signal" then
    local signal = tonumber(args[3])
    if not signal or signal < 0 or signal > 15 then
      error("max-signal must be a number from 0 to 15", 0)
    end

    config.absoluteSignalMax = signal
    config.brakeSignal = signal
    saveConfig(config)
    print("Saved absoluteSignalMax=" .. tostring(signal) .. " and brakeSignal=" .. tostring(signal) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "stabilize-gains" then
    config.stabilize.axis1Kp = parseNumber(args[3], "axis1Kp")
    config.stabilize.axis1Kd = parseNumber(args[4], "axis1Kd")
    config.stabilize.axis2Kp = parseNumber(args[5] or args[3], "axis2Kp")
    config.stabilize.axis2Kd = parseNumber(args[6] or args[4], "axis2Kd")
    saveConfig(config)
    print("Saved stabilize gains to " .. CONFIG_PATH)
    print("  axis1Kp=" .. tostring(config.stabilize.axis1Kp) .. " axis1Kd=" .. tostring(config.stabilize.axis1Kd))
    print("  axis2Kp=" .. tostring(config.stabilize.axis2Kp) .. " axis2Kd=" .. tostring(config.stabilize.axis2Kd))
    return
  elseif subcommand == "stabilize-trim" then
    config.stabilize.axis1Trim = parseNumber(args[3], "axis1Trim")
    config.stabilize.axis2Trim = parseNumber(args[4], "axis2Trim")
    saveConfig(config)
    print("Saved stabilize trim to " .. CONFIG_PATH)
    print("  axis1Trim=" .. tostring(config.stabilize.axis1Trim))
    print("  axis2Trim=" .. tostring(config.stabilize.axis2Trim))
    return
  elseif subcommand == "stabilize-yaw" then
    local yawKd = parseNumber(args[3], "yawKd")
    local maxYawCorrection = args[4] and parseNumber(args[4], "maxYawCorrection") or config.stabilize.maxYawCorrection or config.stabilize.maxCorrection or 1.5
    local yawTrim = args[5] and parseNumber(args[5], "yawTrim") or config.stabilize.yawTrim or 0
    local yawSign = args[6] and parseNumber(args[6], "yawSign") or config.stabilize.yawSign or 1

    if maxYawCorrection < 0 then
      error("maxYawCorrection must be zero or greater", 0)
    end
    if yawSign ~= 1 and yawSign ~= -1 then
      error("yawSign must be 1 or -1", 0)
    end

    config.stabilize.yawKd = yawKd
    config.stabilize.maxYawCorrection = maxYawCorrection
    config.stabilize.yawTrim = yawTrim
    config.stabilize.yawSign = yawSign
    saveConfig(config)
    print("Saved stabilize yaw tuning to " .. CONFIG_PATH)
    print("  yawKd=" .. tostring(config.stabilize.yawKd))
    print("  maxYawCorrection=" .. tostring(config.stabilize.maxYawCorrection))
    print("  yawTrim=" .. tostring(config.stabilize.yawTrim))
    print("  yawSign=" .. tostring(config.stabilize.yawSign))
    return
  elseif subcommand == "rotor-handedness" then
    local role = string.lower(tostring(args[3] or ""))
    if not validRotorRole(role) then
      error("Usage: aircraft config rotor-handedness <front_left|front_right|rear_left|rear_right> <right_handed|left_handed>", 0)
    end

    config.rotors = config.rotors or {}
    config.rotors.handedness = config.rotors.handedness or {}
    config.rotors.handedness[role] = normalizeHandedness(args[4])
    if config.rotors.handedness[role] == "toggle" then
      error("config rotor-handedness needs an explicit right_handed or left_handed value", 0)
    end
    saveConfig(config)
    print("Saved rotors.handedness." .. role .. "=" .. tostring(config.rotors.handedness[role]) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "stabilize-limits" then
    local maxCorrection = parseNumber(args[3], "maxCorrection")
    local maxAttitudeDelta = parseNumber(args[4], "maxAttitudeDelta")

    if maxCorrection < 0 then
      error("maxCorrection must be zero or greater", 0)
    end
    if maxAttitudeDelta <= 0 then
      error("maxAttitudeDelta must be greater than zero", 0)
    end

    config.stabilize.maxCorrection = maxCorrection
    config.maxAttitudeDelta = maxAttitudeDelta
    saveConfig(config)
    print("Saved stabilize limits to " .. CONFIG_PATH)
    print("  maxCorrection=" .. tostring(config.stabilize.maxCorrection))
    print("  maxAttitudeDelta=" .. tostring(config.maxAttitudeDelta))
    return
  elseif subcommand == "stabilize-dither" then
    config.stabilize.signalDither = parseBoolean(args[3])
    saveConfig(config)
    print("Saved stabilize.signalDither=" .. tostring(config.stabilize.signalDither) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "display" then
    config.display = config.display or {}
    config.display.enabled = parseBoolean(args[3])
    saveConfig(config)
    print("Saved display.enabled=" .. tostring(config.display.enabled) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "stabilize-nixies" then
    config.display = config.display or {}
    config.display.stabilizeEnabled = parseBoolean(args[3])
    if args[4] then
      config.display.stabilizeInterval = parseNumber(args[4], "stabilizeInterval")
      if config.display.stabilizeInterval <= 0 then
        error("stabilizeInterval must be greater than zero", 0)
      end
    end
    saveConfig(config)
    print("Saved stabilize Nixie settings to " .. CONFIG_PATH)
    print("  display.stabilizeEnabled=" .. tostring(config.display.stabilizeEnabled))
    print("  display.stabilizeInterval=" .. tostring(config.display.stabilizeInterval))
    return
  elseif subcommand == "hud" then
    config.hud = config.hud or {}
    config.hud.enabled = parseBoolean(args[3])
    saveConfig(config)
    print("Saved hud.enabled=" .. tostring(config.hud.enabled) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "killswitch" then
    config.killSwitch = config.killSwitch or {}
    config.killSwitch.enabled = parseBoolean(args[3])
    if args[4] then
      config.killSwitch.side = normalizeComputerSide(args[4])
    end
    if args[5] then
      config.killSwitch.activeHigh = parseBoolean(args[5])
    elseif config.killSwitch.activeHigh == nil then
      config.killSwitch.activeHigh = true
    end
    saveConfig(config)
    print("Saved kill switch to " .. CONFIG_PATH)
    print("  enabled=" .. tostring(config.killSwitch.enabled))
    print("  side=" .. tostring(config.killSwitch.side))
    print("  activeHigh=" .. tostring(config.killSwitch.activeHigh))
    return
  elseif subcommand == "controller" then
    config.controller = config.controller or {}
    config.controller.enabled = parseBoolean(args[3])
    saveConfig(config)
    print("Saved controller.enabled=" .. tostring(config.controller.enabled) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "controller-layout" then
    local x = parseInteger(args[3], "x")
    local y = parseInteger(args[4], "y")
    local z = parseInteger(args[5], "z")
    local side = normalizeRedstoneSide(args[6] or "up")

    config.controller = config.controller or {}
    config.controller.bindings = controller.defaultBindings(x, y, z, side)
    saveConfig(config)
    print("Saved controller layout to " .. CONFIG_PATH)
    print("  q=" .. bindingText(config.controller.bindings.q))
    print("  w=" .. bindingText(config.controller.bindings.w))
    print("  e=" .. bindingText(config.controller.bindings.e))
    print("  shift=" .. bindingText(config.controller.bindings.shift))
    print("  a=" .. bindingText(config.controller.bindings.a))
    print("  s=" .. bindingText(config.controller.bindings.s))
    print("  d=" .. bindingText(config.controller.bindings.d))
    print("  space=" .. bindingText(config.controller.bindings.space))
    return
  elseif subcommand == "controller-bind" then
    local key = string.lower(tostring(args[3] or ""))
    if not validControllerKey(key) then
      error("controller key must be q, w, e, a, s, d, space, or shift", 0)
    end

    config.controller = config.controller or {}
    config.controller.bindings = config.controller.bindings or {}
    config.controller.bindings[key] = {
      x = parseInteger(args[4], "x"),
      y = parseInteger(args[5], "y"),
      z = parseInteger(args[6], "z"),
      side = normalizeRedstoneSide(args[7] or "up"),
    }
    saveConfig(config)
    print("Saved controller." .. key .. "=" .. bindingText(config.controller.bindings[key]) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "controller-tuning" then
    local controllerConfig = config.controller or {}
    local throttlePower = parseNumber(args[3], "throttlePower")
    local axis1TargetDeg = parseNumber(args[4], "axis1TargetDeg")
    local axis2TargetDeg = parseNumber(args[5] or args[4], "axis2TargetDeg")
    local axis1Power = args[6] and parseNumber(args[6], "axis1Power") or controllerConfig.axis1Power or 0
    local axis2Power = args[7] and parseNumber(args[7], "axis2Power") or args[6] and axis1Power or controllerConfig.axis2Power or 0

    config.controller = controllerConfig
    config.controller.throttlePower = throttlePower
    config.controller.axis1TargetDeg = axis1TargetDeg
    config.controller.axis2TargetDeg = axis2TargetDeg
    config.controller.axis1Power = axis1Power
    config.controller.axis2Power = axis2Power
    saveConfig(config)
    print("Saved controller tuning to " .. CONFIG_PATH)
    print("  throttlePower=" .. tostring(throttlePower))
    print("  axis1TargetDeg=" .. tostring(axis1TargetDeg))
    print("  axis2TargetDeg=" .. tostring(axis2TargetDeg))
    print("  axis1Power=" .. tostring(axis1Power))
    print("  axis2Power=" .. tostring(axis2Power))
    return
  elseif subcommand == "controller-yaw" then
    local controllerConfig = config.controller or {}
    local yawPower = parseNumber(args[3], "yawPower")

    config.controller = controllerConfig
    config.controller.yawPower = yawPower
    saveConfig(config)
    print("Saved controller yaw tuning to " .. CONFIG_PATH)
    print("  yawPower=" .. tostring(yawPower))
    return
  elseif subcommand == "controller-response" then
    local controllerConfig = config.controller or {}
    local targetSlewDegPerSecond = parseNumber(args[3], "targetSlewDegPerSecond")
    local throttleSlewPowerPerSecond = args[4]
      and parseNumber(args[4], "throttleSlewPowerPerSecond")
      or controllerConfig.throttleSlewPowerPerSecond
      or 4

    if targetSlewDegPerSecond < 0 or throttleSlewPowerPerSecond < 0 then
      error("controller-response values must be non-negative", 0)
    end

    config.controller = controllerConfig
    config.controller.targetSlewDegPerSecond = targetSlewDegPerSecond
    config.controller.throttleSlewPowerPerSecond = throttleSlewPowerPerSecond
    saveConfig(config)
    print("Saved controller response to " .. CONFIG_PATH)
    print("  targetSlewDegPerSecond=" .. tostring(targetSlewDegPerSecond))
    print("  throttleSlewPowerPerSecond=" .. tostring(throttleSlewPowerPerSecond))
    return
  elseif subcommand == "controller-threshold" then
    local threshold = parseNumber(args[3], "threshold")
    if threshold < 0 or threshold > 15 then
      error("threshold must be from 0 to 15", 0)
    end

    config.controller = config.controller or {}
    config.controller.threshold = threshold
    saveConfig(config)
    print("Saved controller.threshold=" .. tostring(threshold) .. " to " .. CONFIG_PATH)
    return
  end

  error("Unknown aircraft config command: " .. tostring(subcommand), 0)
end

local function parseCommandOptions(startIndex)
  local options = {}
  local i = startIndex

  while i <= #args do
    local arg = args[i]

    if arg == "--apply" then
      options.apply = true
      i = i + 1
    elseif arg == "--seconds" then
      options.seconds = tonumber(args[i + 1])
      if not options.seconds then
        error("--seconds needs a number", 0)
      end
      i = i + 2
    elseif arg == "--forever" then
      options.forever = true
      i = i + 1
    elseif arg == "--base-power" then
      options.basePower = tonumber(args[i + 1])
      if not options.basePower then
        error("--base-power needs a number", 0)
      end
      i = i + 2
    elseif arg == "--controller" then
      options.controller = true
      i = i + 1
    elseif arg == "--no-controller" then
      options.controller = false
      i = i + 1
    elseif arg == "--killswitch" then
      options.killSwitch = true
      i = i + 1
    elseif arg == "--no-killswitch" then
      options.killSwitch = false
      i = i + 1
    elseif arg == "--no-display" then
      options.display = false
      i = i + 1
    elseif arg == "--display" then
      options.display = true
      i = i + 1
    elseif arg == "--hud" then
      options.hud = true
      i = i + 1
    elseif arg == "--no-hud" then
      options.hud = false
      i = i + 1
    elseif arg == "--hud-interval" then
      options.hudInterval = tonumber(args[i + 1])
      if not options.hudInterval then
        error("--hud-interval needs a number", 0)
      end
      i = i + 2
    elseif arg == "--nixies" then
      options.nixies = true
      i = i + 1
    elseif arg == "--no-nixies" then
      options.nixies = false
      i = i + 1
    elseif arg == "--nixie-interval" then
      options.nixieInterval = tonumber(args[i + 1])
      if not options.nixieInterval then
        error("--nixie-interval needs a number", 0)
      end
      i = i + 2
    elseif arg == "--after-signal" then
      options.afterSignal = tonumber(args[i + 1])
      if not options.afterSignal then
        error("--after-signal needs a number", 0)
      end
      i = i + 2
    elseif arg == "--interval" then
      options.interval = tonumber(args[i + 1])
      if not options.interval then
        error("--interval needs a number", 0)
      end
      i = i + 2
    elseif arg == "--kp" then
      options.kp = tonumber(args[i + 1])
      if not options.kp then
        error("--kp needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-kp" then
      options.axis1Kp = tonumber(args[i + 1])
      if not options.axis1Kp then
        error("--axis1-kp needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-kp" then
      options.axis2Kp = tonumber(args[i + 1])
      if not options.axis2Kp then
        error("--axis2-kp needs a number", 0)
      end
      i = i + 2
    elseif arg == "--kd" then
      options.kd = tonumber(args[i + 1])
      if not options.kd then
        error("--kd needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-kd" then
      options.axis1Kd = tonumber(args[i + 1])
      if not options.axis1Kd then
        error("--axis1-kd needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-kd" then
      options.axis2Kd = tonumber(args[i + 1])
      if not options.axis2Kd then
        error("--axis2-kd needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-trim" then
      options.axis1Trim = tonumber(args[i + 1])
      if not options.axis1Trim then
        error("--axis1-trim needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-trim" then
      options.axis2Trim = tonumber(args[i + 1])
      if not options.axis2Trim then
        error("--axis2-trim needs a number", 0)
      end
      i = i + 2
    elseif arg == "--yaw-kd" then
      options.yawKd = tonumber(args[i + 1])
      if not options.yawKd then
        error("--yaw-kd needs a number", 0)
      end
      i = i + 2
    elseif arg == "--yaw-trim" then
      options.yawTrim = tonumber(args[i + 1])
      if not options.yawTrim then
        error("--yaw-trim needs a number", 0)
      end
      i = i + 2
    elseif arg == "--yaw-sign" then
      options.yawSign = tonumber(args[i + 1])
      if options.yawSign ~= 1 and options.yawSign ~= -1 then
        error("--yaw-sign needs 1 or -1", 0)
      end
      i = i + 2
    elseif arg == "--max-correction" then
      options.maxCorrection = tonumber(args[i + 1])
      if not options.maxCorrection or options.maxCorrection < 0 then
        error("--max-correction needs a non-negative number", 0)
      end
      i = i + 2
    elseif arg == "--max-yaw-correction" then
      options.maxYawCorrection = tonumber(args[i + 1])
      if not options.maxYawCorrection or options.maxYawCorrection < 0 then
        error("--max-yaw-correction needs a non-negative number", 0)
      end
      i = i + 2
    elseif arg == "--max-attitude" then
      options.maxAttitudeDelta = tonumber(args[i + 1])
      if not options.maxAttitudeDelta or options.maxAttitudeDelta <= 0 then
        error("--max-attitude needs a positive number", 0)
      end
      i = i + 2
    elseif arg == "--max-attitude-deg" then
      options.maxAttitudeDeg = tonumber(args[i + 1])
      if not options.maxAttitudeDeg or options.maxAttitudeDeg <= 0 then
        error("--max-attitude-deg needs a positive number", 0)
      end
      i = i + 2
    elseif arg == "--report-frames" then
      options.reportFrameLimit = tonumber(args[i + 1])
      if not options.reportFrameLimit or options.reportFrameLimit < 0 then
        error("--report-frames needs a non-negative number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-target-deg" then
      options.axis1TargetDeg = tonumber(args[i + 1])
      if not options.axis1TargetDeg then
        error("--axis1-target-deg needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-target-deg" then
      options.axis2TargetDeg = tonumber(args[i + 1])
      if not options.axis2TargetDeg then
        error("--axis2-target-deg needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-power" then
      options.axis1Power = tonumber(args[i + 1])
      if not options.axis1Power then
        error("--axis1-power needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-power" then
      options.axis2Power = tonumber(args[i + 1])
      if not options.axis2Power then
        error("--axis2-power needs a number", 0)
      end
      i = i + 2
    elseif arg == "--pulse-seconds" then
      options.pulseSeconds = tonumber(args[i + 1])
      if not options.pulseSeconds or options.pulseSeconds <= 0 then
        error("--pulse-seconds needs a positive number", 0)
      end
      i = i + 2
    elseif arg == "--target-slew-deg" then
      options.targetSlewDegPerSecond = tonumber(args[i + 1])
      if not options.targetSlewDegPerSecond or options.targetSlewDegPerSecond < 0 then
        error("--target-slew-deg needs a non-negative number", 0)
      end
      i = i + 2
    elseif arg == "--throttle-slew" then
      options.throttleSlewPowerPerSecond = tonumber(args[i + 1])
      if not options.throttleSlewPowerPerSecond or options.throttleSlewPowerPerSecond < 0 then
        error("--throttle-slew needs a non-negative number", 0)
      end
      i = i + 2
    else
      error("Unknown aircraft option: " .. tostring(arg), 0)
    end
  end

  return options
end

local function runSignal()
  local config = loadConfig()
  local role = args[2]
  local signal = tonumber(args[3])

  if not role or not signal then
    error("Usage: aircraft signal <role|all> <0-15> [--apply] [--seconds n] [--after-signal n]", 0)
  end

  local options = parseCommandOptions(4)
  options.role = role
  options.signal = signal

  actuatorTest.signal(config, options)
end

local function runBrake()
  local config = loadConfig()
  local role = args[2] or "all"
  local optionStart = 3

  if string.sub(role, 1, 2) == "--" then
    role = "all"
    optionStart = 2
  end

  local options = parseCommandOptions(optionStart)
  options.role = role

  actuatorTest.brake(config, options)
end

local function runRotorHandedness()
  local config = loadConfig()
  local target = args[2]
  local handedness = args[3]
  local optionStart = 4

  if target and string.sub(target, 1, 2) == "--" then
    target = nil
    handedness = nil
    optionStart = 2
  elseif handedness and string.sub(handedness, 1, 2) == "--" then
    handedness = nil
    optionStart = 3
  end

  local options = parseCommandOptions(optionStart)
  options.target = target
  options.handedness = handedness

  flightControl.rotorHandedness(config, options)
end

local function runDisplays()
  local config = loadConfig()
  local options = parseCommandOptions(2)

  displayLoop.run(config, options)
end

local function runController()
  local config = loadConfig()
  local options = parseCommandOptions(2)

  controller.probe(config, options)
end

local function runStabilize()
  local config = loadConfig()
  local options = parseCommandOptions(2)

  flightControl.stabilize(config, options)
end

local function runRecover()
  local config = loadConfig()
  local options = parseCommandOptions(2)
  local degToRad = math.pi / 180
  local axis1TargetDeg = tonumber(options.axis1TargetDeg) or 0
  local axis2TargetDeg = tonumber(options.axis2TargetDeg) or 0
  local axis1Power = tonumber(options.axis1Power) or 0
  local axis2Power = tonumber(options.axis2Power) or 0

  if axis1TargetDeg == 0 and axis2TargetDeg == 0 and axis1Power == 0 and axis2Power == 0 then
    error("recover needs at least one of --axis1-target-deg, --axis2-target-deg, --axis1-power, or --axis2-power", 0)
  end

  options.controller = false
  options.recoveryTest = {
    pulseSeconds = tonumber(options.pulseSeconds) or 1.5,
    axis1Target = axis1TargetDeg * degToRad,
    axis2Target = axis2TargetDeg * degToRad,
    axis1Power = axis1Power,
    axis2Power = axis2Power,
    targetSlewDegPerSecond = tonumber(options.targetSlewDegPerSecond) or 30,
    throttleSlewPowerPerSecond = tonumber(options.throttleSlewPowerPerSecond) or 8,
  }

  flightControl.stabilize(config, options)
end

if command == "help" or command == "--help" or command == "-h" then
  usage()
elseif command == "scan" then
  local ok, result = pcall(runScan)
  if not ok then
    print("aircraft scan failed: " .. tostring(result))
    error("aircraft scan failed", 0)
  end
elseif command == "status" then
  local ok, result = pcall(runStatus)
  if not ok then
    print("aircraft status failed: " .. tostring(result))
    error("aircraft status failed", 0)
  end
elseif command == "config" then
  local ok, result = pcall(runConfig)
  if not ok then
    print("aircraft config failed: " .. tostring(result))
    error("aircraft config failed", 0)
  end
elseif command == "signal" then
  local ok, result = pcall(runSignal)
  if not ok then
    print("aircraft signal failed: " .. tostring(result))
    error("aircraft signal failed", 0)
  end
elseif command == "brake" then
  local ok, result = pcall(runBrake)
  if not ok then
    print("aircraft brake failed: " .. tostring(result))
    error("aircraft brake failed", 0)
  end
elseif command == "rotor-handedness" then
  local ok, result = pcall(runRotorHandedness)
  if not ok then
    print("aircraft rotor-handedness failed: " .. tostring(result))
    error("aircraft rotor-handedness failed", 0)
  end
elseif command == "displays" then
  local ok, result = pcall(runDisplays)
  if not ok then
    print("aircraft displays failed: " .. tostring(result))
    error("aircraft displays failed", 0)
  end
elseif command == "controller" then
  local ok, result = pcall(runController)
  if not ok then
    print("aircraft controller failed: " .. tostring(result))
    error("aircraft controller failed", 0)
  end
elseif command == "stabilize" then
  local ok, result = pcall(runStabilize)
  if not ok then
    print("aircraft stabilize failed: " .. tostring(result))
    error("aircraft stabilize failed", 0)
  end
elseif command == "recover" then
  local ok, result = pcall(runRecover)
  if not ok then
    print("aircraft recover failed: " .. tostring(result))
    error("aircraft recover failed", 0)
  end
else
  usage()
  error("Unknown aircraft command: " .. tostring(command), 0)
end
