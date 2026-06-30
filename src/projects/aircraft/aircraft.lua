local coords = require("lib.aircraft.coords")
local actuatorTest = require("lib.aircraft.actuator_test")
local actuators = require("lib.aircraft.actuators")
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
    parallelism = 32,
  },
  frontAxis = nil,
  leftAxis = nil,
  dryRun = true,
  absoluteSignalMax = 15,
  brakeSignal = 15,
  actuator = {
    type = "redstone_signal",
    redstoneSignal = {
      roleFamily = "scalarActuator",
      setter = "setSignal",
      getter = "getSignal",
    },
    rotationSpeed = {
      roleFamily = "speedActuator",
      setter = "setTargetSpeed",
      getter = "getTargetSpeed",
      idleRpm = 0,
      powerRpm = 256,
      brakeRpm = 0,
      minRpm = -256,
      maxRpm = 256,
      sign = 1,
      autoRoleSigns = true,
      roleSigns = nil,
      round = false,
      baseRpm = 0,
      throttleRpmPerPower = 16,
      axis1KpRpm = 0,
      axis1KdRpm = 0,
      axis2KpRpm = 0,
      axis2KdRpm = 0,
      axis1TrimRpm = 0,
      axis2TrimRpm = 0,
      maxCorrectionRpm = 0,
      minTargetRpm = 0,
      maxTargetRpm = 256,
      writeInterval = 0.1,
      writeDeadbandRpm = 0.5,
    },
  },
  maxAttitudeDelta = 2,
  statusReadLimit = 8,
  reportPath = "/aircraft_scan.txt",
  stabilize = {
    interval = 0.05,
    seconds = 1,
    basePower = 0,
    axis1Kp = 4,
    axis2Kp = 4,
    axis1Kd = 0.12,
    axis2Kd = 0.2,
    axis1Trim = 0,
    axis2Trim = 0,
    maxCorrection = 1.5,
    desaturate = true,
    desaturateHeadroom = 0.75,
    tiltCompensation = true,
    tiltCompensationGain = 1,
    tiltCompensationMaxPower = 2,
    signalDither = true,
    brakeOnExit = true,
    reportFrameLimit = 600,
  },
  yaw = {
    enabled = true,
    rateKd = 0.15,
    maxTiltDeg = 8,
    deadbandDegPerSecond = 0.5,
    sign = 1,
    commandLateral = 0.08,
    clearOnExit = true,
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
    source = "side",
    side = "front",
    activeHigh = true,
    keyEnabled = true,
    key = "k",
    binding = nil,
  },
  controller = {
    enabled = false,
    type = "redstone_router",
    threshold = 1,
    throttleMode = "hold",
    throttlePower = 1,
    axis1TargetDeg = 5,
    axis2TargetDeg = 5,
    axis1Power = 0,
    axis2Power = 0,
    targetSlewDegPerSecond = 8,
    throttleSlewPowerPerSecond = 4,
    bindings = controller.defaultBindings(3, -1, -5, "up", "+Z", "+X"),
  },
  sendWebhook = true,
}

local function usage()
  print("aircraft scan [options]")
  print("aircraft status")
  print("aircraft config show")
  print("aircraft config axes <frontAxis> <leftAxis>")
  print("aircraft config scan-parallelism <workers>")
  print("aircraft config dry-run <true|false>")
  print("aircraft config max-signal <0-15>")
  print("aircraft config actuator-type <redstone_signal|rotation_speed>")
  print("aircraft config rotation-speed <powerRpm> [idleRpm] [sign] [brakeRpm] [minRpm] [maxRpm]")
  print("aircraft config rotation-speed-control <baseRpm> [maxCorrectionRpm] [axis1KpRpm] [axis1KdRpm] [axis2KpRpm] [axis2KdRpm] [throttleRpmPerPower]")
  print("aircraft config rotation-speed-writes <intervalSeconds> [deadbandRpm]")
  print("aircraft config rotation-speed-signs <auto|fl fr rl rr>")
  print("aircraft config stabilize-gains <axis1Kp> <axis1Kd> [axis2Kp] [axis2Kd]")
  print("aircraft config stabilize-trim <axis1Power> <axis2Power>")
  print("aircraft config stabilize-interval <seconds>")
  print("aircraft config stabilize-limits <maxCorrection> <maxAttitudeDelta>")
  print("aircraft config stabilize-desaturate <true|false> [headroomPower]")
  print("aircraft config stabilize-tilt-comp <true|false> [gain] [maxPower]")
  print("aircraft config stabilize-dither <true|false>")
  print("aircraft config yaw <true|false> [rateKd] [maxTiltDeg] [sign] [commandLateral]")
  print("aircraft config display <true|false>")
  print("aircraft config stabilize-nixies <true|false> [interval]")
  print("aircraft config hud <true|false>")
  print("aircraft config killswitch <true|false> [front|back|left|right|top|bottom] [activeHigh true|false]")
  print("aircraft config killswitch-router <x> <y> <z> [side] [activeHigh true|false]")
  print("aircraft config killswitch-key <true|false> [key]")
  print("aircraft config killswitch-source <key|side|router>")
  print("aircraft config controller <true|false>")
  print("aircraft config controller-type <redstone_router|keyboard>")
  print("aircraft config controller-layout <shiftX> <shiftY> <shiftZ> [side]")
  print("aircraft config controller-bind <key> <x> <y> <z> [side]")
  print("aircraft config controller-tuning <throttlePower> <axis1TargetDeg> [axis2TargetDeg] [axis1Power] [axis2Power]")
  print("aircraft config controller-throttle <hold|momentary> [maxPower] [slewPowerPerSecond]")
  print("aircraft config controller-response <targetSlewDegPerSecond> [throttleSlewPowerPerSecond]")
  print("aircraft config controller-threshold <0-15>")
  print("aircraft brake [role|all] [--apply]")
  print("aircraft controller [--seconds n] [--interval n]")
  print("aircraft killswitch [--seconds n] [--interval n] [--controller-type type]")
  print("aircraft displays [--seconds n] [--interval n]")
  print("aircraft stabilize [--apply] [--seconds n|--forever] [--base-power n] [--base-rpm n] [--kp n] [--kd n] [--kp-rpm n] [--kd-rpm n] [--axis1-trim n] [--axis2-trim n] [--axis1-trim-rpm n] [--axis2-trim-rpm n] [--controller] [--controller-type type] [--yaw|--no-yaw] [--no-hud] [--nixies] [--killswitch|--no-killswitch]")
  print("aircraft recover [--apply] [--seconds n] [--base-power n] [--base-rpm n] [--axis1-target-deg n] [--axis2-target-deg n] [--axis1-power n] [--axis2-power n] [--pulse-seconds n]")
  print("aircraft signal <role|all> <0-15> [--apply] [--seconds n] [--after-signal n]")
  print("aircraft help")
  print("")
  print("Options:")
  print("  --radius <n>       set x/z radius")
  print("  --x-radius <n>     set x scan radius")
  print("  --y-radius <n>     set y scan radius")
  print("  --z-radius <n>     set z scan radius")
  print("  --sample-limit <n> max getter samples per peripheral")
  print("  --parallelism <n>  scan worker count")
  print("  --out <path>       default /aircraft_scan.txt")
  print("  --no-webhook       skip webhook output")
  print("  --hud-interval <n> stabilize HUD refresh seconds")
  print("  --nixie-interval <n> stabilize Nixie refresh seconds")
  print("  --report-frames <n> max stabilize frames kept in report")
  print("  --max-attitude-deg <n> abort when tilt error exceeds degrees")
  print("  --base-rpm <n>     rotation_speed base target RPM for this run")
  print("  --kp-rpm/--kd-rpm <n> rotation_speed PD gains for this run")
  print("  --max-correction-rpm <n> rotation_speed correction cap")
  print("  --yaw-kd <n>       yaw-rate damping gain")
  print("  --yaw-max-tilt-deg <n> max gyro bearing yaw tilt, clamped to 12")
  print("  --yaw-deadband-deg <n> ignore smaller yaw rates")
  print("  --yaw-sign <-1|1>  invert yaw correction if needed")
  print("  --yaw-command <n>  Q/E yaw command strength before max-tilt clamp")
  print("  --actuator-type <type> override actuator backend for this run")
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

    mergeInto(config, fileConfig)

    return configModel.normalize(config), CONFIG_PATH
  end

  return configModel.normalize(config), "built-in defaults"
end

local function loadSerializedTable(path)
  if not path or not fs.exists(path) then
    return nil
  end

  local handle = fs.open(path, "r")
  if not handle then
    return nil
  end

  local contents = handle.readAll()
  handle.close()

  local ok, value = pcall(textutils.unserialize, contents)
  if ok and type(value) == "table" then
    return value
  end

  return nil
end

local function scannedAxis(config, name)
  local scan = loadSerializedTable(config.reportPath or "/aircraft_scan.txt")
  local vector = scan and scan.orientation and scan.orientation[name]

  if coords.isCardinal(vector) then
    return vector
  end

  return nil
end

local function controllerLayoutAxes(config)
  local front = coords.parseAxis(config.frontAxis)
  local left = coords.parseAxis(config.leftAxis)
  local frontSource = front and "config" or nil
  local leftSource = left and "config" or nil

  if not front then
    front = scannedAxis(config, "frontVector")
    frontSource = front and "scan" or nil
  end
  if not left then
    left = scannedAxis(config, "leftVector")
    leftSource = left and "scan" or nil
  end

  front = front or coords.parseAxis("+Z")
  left = left or coords.parseAxis("+X")
  frontSource = frontSource or "default"
  leftSource = leftSource or "default"

  return front, left, frontSource, leftSource
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

local function parseScanParallelism(value, label)
  local number = parseInteger(value, label or "scan parallelism")

  if number < 1 then
    error((label or "scan parallelism") .. " must be one or greater", 0)
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
    elseif arg == "--parallelism" then
      config.scan.parallelism = parseScanParallelism(args[i + 1], "--parallelism")
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

local function printKineticScadaSummary(scada)
  local summary = scada and scada.summary
  if not summary or (summary.nodes or 0) == 0 then
    print("Kinetic SCADA: none")
    return
  end

  print(
    "Kinetic SCADA: nodes="
      .. tostring(summary.nodes or 0)
      .. " networks="
      .. tostring(summary.networks or 0)
      .. " subnetworks="
      .. tostring(summary.subnetworks or 0)
      .. " edges="
      .. tostring(summary.edges or 0)
      .. "/"
      .. tostring(summary.resolvedEdges or 0)
      .. " resolved"
  )
  print(
    "  drivers="
      .. tostring(summary.drivers or 0)
      .. " consumers="
      .. tostring(summary.consumers or 0)
      .. " generators="
      .. tostring(summary.generators or 0)
      .. " leaves="
      .. tostring(summary.leaves or 0)
      .. " unnetworked="
      .. tostring(summary.unnetworked or 0)
      .. " warnings="
      .. tostring(summary.warnings or 0)
  )

  if (summary.missingSourceIds or 0) > 0 or (summary.missingAnchorIds or 0) > 0 then
    print(
      "  missing sources="
        .. tostring(summary.missingSourceIds or 0)
        .. " anchors="
        .. tostring(summary.missingAnchorIds or 0)
    )
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
  print("Scan workers: " .. tostring(report.summary.parallelism or 1))
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

  printKineticScadaSummary(report.kineticScada)

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

    if report.orientation.sensors then
      print("Suggested sensors:")
      for _, category in ipairs({ "navigationSensor", "altitudeSensor" }) do
        local sensor = report.orientation.sensors[category]
        if sensor and sensor.coord then
          print("  " .. category .. "=" .. coords.label(sensor.coord))
        else
          print("  " .. category .. "=missing")
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

local function normalizeKillSwitchSource(source)
  local normalized = string.lower(tostring(source or "side"))
  if normalized == "keyboard" or normalized == "controller" then
    normalized = "key"
  end

  if normalized == "key" or normalized == "side" or normalized == "router" then
    return normalized
  end

  error("killswitch source must be key, side, or router", 0)
end

local function validControllerKey(key)
  return key == "w"
    or key == "a"
    or key == "s"
    or key == "d"
    or key == "q"
    or key == "e"
    or key == "space"
    or key == "shift"
    or key == "k"
end

local function normalizeThrottleMode(value)
  local text = string.lower(tostring(value or "hold"))
  text = string.gsub(text, "%s+", "_")
  text = string.gsub(text, "-", "_")

  if text == "hold" or text == "momentary" then
    return text
  end

  error("throttle mode must be hold or momentary", 0)
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

local function roleSignsText(roleSigns)
  if type(roleSigns) ~= "table" then
    return "nil"
  end

  return "fl="
    .. tostring(roleSigns.front_left)
    .. " fr="
    .. tostring(roleSigns.front_right)
    .. " rl="
    .. tostring(roleSigns.rear_left)
    .. " rr="
    .. tostring(roleSigns.rear_right)
end

local function printConfig(config, source)
  print("aircraft config from " .. tostring(source))
  print("  scan.xRadius=" .. tostring(config.scan and config.scan.xRadius))
  print("  scan.yRadius=" .. tostring(config.scan and config.scan.yRadius))
  print("  scan.zRadius=" .. tostring(config.scan and config.scan.zRadius))
  print("  scan.sampleLimit=" .. tostring(config.scan and config.scan.sampleLimit))
  print("  scan.errorLimit=" .. tostring(config.scan and config.scan.errorLimit))
  print("  scan.parallelism=" .. tostring(config.scan and config.scan.parallelism))
  print("  frontAxis=" .. tostring(config.frontAxis))
  print("  leftAxis=" .. tostring(config.leftAxis))
  print("  dryRun=" .. tostring(config.dryRun))
  print("  absoluteSignalMax=" .. tostring(config.absoluteSignalMax))
  print("  brakeSignal=" .. tostring(config.brakeSignal))
  print("  actuator.type=" .. tostring(config.actuator and config.actuator.type))
  print("  actuator.redstoneSignal.roleFamily=" .. tostring(config.actuator and config.actuator.redstoneSignal and config.actuator.redstoneSignal.roleFamily))
  print("  actuator.rotationSpeed.roleFamily=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.roleFamily))
  print("  actuator.rotationSpeed.setter=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.setter))
  print("  actuator.rotationSpeed.getter=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.getter))
  print("  actuator.rotationSpeed.idleRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.idleRpm))
  print("  actuator.rotationSpeed.powerRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.powerRpm))
  print("  actuator.rotationSpeed.brakeRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.brakeRpm))
  print("  actuator.rotationSpeed.minRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.minRpm))
  print("  actuator.rotationSpeed.maxRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.maxRpm))
  print("  actuator.rotationSpeed.sign=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.sign))
  print("  actuator.rotationSpeed.autoRoleSigns=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.autoRoleSigns))
  print("  actuator.rotationSpeed.roleSigns=" .. roleSignsText(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.roleSigns))
  print("  actuator.rotationSpeed.round=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.round))
  print("  actuator.rotationSpeed.baseRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.baseRpm))
  print("  actuator.rotationSpeed.throttleRpmPerPower=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.throttleRpmPerPower))
  print("  actuator.rotationSpeed.axis1KpRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.axis1KpRpm))
  print("  actuator.rotationSpeed.axis1KdRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.axis1KdRpm))
  print("  actuator.rotationSpeed.axis2KpRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.axis2KpRpm))
  print("  actuator.rotationSpeed.axis2KdRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.axis2KdRpm))
  print("  actuator.rotationSpeed.axis1TrimRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.axis1TrimRpm))
  print("  actuator.rotationSpeed.axis2TrimRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.axis2TrimRpm))
  print("  actuator.rotationSpeed.maxCorrectionRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.maxCorrectionRpm))
  print("  actuator.rotationSpeed.minTargetRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.minTargetRpm))
  print("  actuator.rotationSpeed.maxTargetRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.maxTargetRpm))
  print("  actuator.rotationSpeed.writeInterval=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.writeInterval))
  print("  actuator.rotationSpeed.writeDeadbandRpm=" .. tostring(config.actuator and config.actuator.rotationSpeed and config.actuator.rotationSpeed.writeDeadbandRpm))
  print("  maxAttitudeDelta=" .. tostring(config.maxAttitudeDelta))
  print("  stabilize.interval=" .. tostring(config.stabilize.interval))
  print("  stabilize.seconds=" .. tostring(config.stabilize.seconds))
  print("  stabilize.basePower=" .. tostring(config.stabilize.basePower))
  print("  stabilize.axis1Kp=" .. tostring(config.stabilize.axis1Kp))
  print("  stabilize.axis1Kd=" .. tostring(config.stabilize.axis1Kd))
  print("  stabilize.axis2Kp=" .. tostring(config.stabilize.axis2Kp))
  print("  stabilize.axis2Kd=" .. tostring(config.stabilize.axis2Kd))
  print("  stabilize.axis1Trim=" .. tostring(config.stabilize.axis1Trim))
  print("  stabilize.axis2Trim=" .. tostring(config.stabilize.axis2Trim))
  print("  stabilize.maxCorrection=" .. tostring(config.stabilize.maxCorrection))
  print("  stabilize.desaturate=" .. tostring(config.stabilize.desaturate))
  print("  stabilize.desaturateHeadroom=" .. tostring(config.stabilize.desaturateHeadroom))
  print("  stabilize.tiltCompensation=" .. tostring(config.stabilize.tiltCompensation))
  print("  stabilize.tiltCompensationGain=" .. tostring(config.stabilize.tiltCompensationGain))
  print("  stabilize.tiltCompensationMaxPower=" .. tostring(config.stabilize.tiltCompensationMaxPower))
  print("  stabilize.signalDither=" .. tostring(config.stabilize.signalDither))
  print("  yaw.enabled=" .. tostring(config.yaw and config.yaw.enabled))
  print("  yaw.rateKd=" .. tostring(config.yaw and config.yaw.rateKd))
  print("  yaw.maxTiltDeg=" .. tostring(config.yaw and config.yaw.maxTiltDeg))
  print("  yaw.deadbandDegPerSecond=" .. tostring(config.yaw and config.yaw.deadbandDegPerSecond))
  print("  yaw.sign=" .. tostring(config.yaw and config.yaw.sign))
  print("  yaw.commandLateral=" .. tostring(config.yaw and config.yaw.commandLateral))
  print("  yaw.clearOnExit=" .. tostring(config.yaw and config.yaw.clearOnExit))
  print("  display.enabled=" .. tostring(config.display and config.display.enabled))
  print("  display.stabilizeEnabled=" .. tostring(config.display and config.display.stabilizeEnabled))
  print("  display.stabilizeInterval=" .. tostring(config.display and config.display.stabilizeInterval))
  print("  hud.enabled=" .. tostring(config.hud and config.hud.enabled))
  print("  hud.interval=" .. tostring(config.hud and config.hud.interval))
  print("  hud.monitorName=" .. tostring(config.hud and config.hud.monitorName))
  print("  killSwitch.enabled=" .. tostring(config.killSwitch and config.killSwitch.enabled))
  print("  killSwitch.source=" .. tostring(config.killSwitch and config.killSwitch.source))
  print("  killSwitch.side=" .. tostring(config.killSwitch and config.killSwitch.side))
  print("  killSwitch.activeHigh=" .. tostring(config.killSwitch and config.killSwitch.activeHigh))
  print("  killSwitch.keyEnabled=" .. tostring(config.killSwitch and config.killSwitch.keyEnabled))
  print("  killSwitch.key=" .. tostring(config.killSwitch and config.killSwitch.key))
  print("  killSwitch.binding=" .. bindingText(config.killSwitch and config.killSwitch.binding))
  print("  controller.enabled=" .. tostring(config.controller and config.controller.enabled))
  print("  controller.type=" .. tostring(config.controller and config.controller.type))
  print("  controller.threshold=" .. tostring(config.controller and config.controller.threshold))
  print("  controller.throttleMode=" .. tostring(config.controller and config.controller.throttleMode))
  print("  controller.throttlePower=" .. tostring(config.controller and config.controller.throttlePower))
  print("  controller.axis1TargetDeg=" .. tostring(config.controller and config.controller.axis1TargetDeg))
  print("  controller.axis2TargetDeg=" .. tostring(config.controller and config.controller.axis2TargetDeg))
  print("  controller.axis1Power=" .. tostring(config.controller and config.controller.axis1Power))
  print("  controller.axis2Power=" .. tostring(config.controller and config.controller.axis2Power))
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
    print("    k=" .. bindingText(config.controller.bindings.k))
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
  elseif subcommand == "scan-parallelism" then
    config.scan = config.scan or {}
    config.scan.parallelism = parseScanParallelism(args[3], "scan parallelism")
    saveConfig(config)
    print("Saved scan.parallelism=" .. tostring(config.scan.parallelism) .. " to " .. CONFIG_PATH)
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
  elseif subcommand == "actuator-type" then
    config.actuator = config.actuator or {}
    config.actuator.type = actuators.normalizeType(args[3])
    saveConfig(config)
    print("Saved actuator.type=" .. tostring(config.actuator.type) .. " to " .. CONFIG_PATH)
    if config.actuator.type == "rotation_speed" then
      print("Next: place and wire four rotation speed controllers, run aircraft scan, then verify speedActuator roles.")
    end
    return
  elseif subcommand == "rotation-speed" then
    config.actuator = config.actuator or {}
    config.actuator.rotationSpeed = config.actuator.rotationSpeed or {}

    local rotationSpeed = config.actuator.rotationSpeed
    rotationSpeed.roleFamily = rotationSpeed.roleFamily or "speedActuator"
    rotationSpeed.setter = rotationSpeed.setter or "setTargetSpeed"
    rotationSpeed.getter = rotationSpeed.getter or "getTargetSpeed"
    rotationSpeed.powerRpm = math.abs(parseNumber(args[3], "powerRpm"))

    if args[4] then
      rotationSpeed.idleRpm = parseNumber(args[4], "idleRpm")
    elseif rotationSpeed.idleRpm == nil then
      rotationSpeed.idleRpm = 0
    end

    if args[5] then
      rotationSpeed.sign = parseNumber(args[5], "sign") < 0 and -1 or 1
    elseif rotationSpeed.sign == nil then
      rotationSpeed.sign = 1
    end

    if args[6] then
      rotationSpeed.brakeRpm = parseNumber(args[6], "brakeRpm")
    elseif rotationSpeed.brakeRpm == nil then
      rotationSpeed.brakeRpm = rotationSpeed.idleRpm or 0
    end

    if args[7] then
      rotationSpeed.minRpm = parseNumber(args[7], "minRpm")
    elseif rotationSpeed.minRpm == nil then
      rotationSpeed.minRpm = -256
    end

    if args[8] then
      rotationSpeed.maxRpm = parseNumber(args[8], "maxRpm")
    elseif rotationSpeed.maxRpm == nil then
      rotationSpeed.maxRpm = 256
    end

    if rotationSpeed.minRpm > rotationSpeed.maxRpm then
      error("minRpm must be less than or equal to maxRpm", 0)
    end

    if rotationSpeed.round == nil then
      rotationSpeed.round = false
    end

    saveConfig(config)
    print("Saved rotation speed actuator settings to " .. CONFIG_PATH)
    print("  powerRpm=" .. tostring(rotationSpeed.powerRpm))
    print("  idleRpm=" .. tostring(rotationSpeed.idleRpm))
    print("  sign=" .. tostring(rotationSpeed.sign))
    print("  brakeRpm=" .. tostring(rotationSpeed.brakeRpm))
    print("  minRpm=" .. tostring(rotationSpeed.minRpm))
    print("  maxRpm=" .. tostring(rotationSpeed.maxRpm))
    return
  elseif subcommand == "rotation-speed-control" then
    config.actuator = config.actuator or {}
    config.actuator.rotationSpeed = config.actuator.rotationSpeed or {}

    local rotationSpeed = config.actuator.rotationSpeed
    rotationSpeed.baseRpm = parseNumber(args[3], "baseRpm")

    if args[4] then
      rotationSpeed.maxCorrectionRpm = math.abs(parseNumber(args[4], "maxCorrectionRpm"))
    elseif rotationSpeed.maxCorrectionRpm == nil then
      rotationSpeed.maxCorrectionRpm = 32
    end

    if args[5] then
      rotationSpeed.axis1KpRpm = parseNumber(args[5], "axis1KpRpm")
    elseif rotationSpeed.axis1KpRpm == nil then
      rotationSpeed.axis1KpRpm = 0
    end

    if args[6] then
      rotationSpeed.axis1KdRpm = parseNumber(args[6], "axis1KdRpm")
    elseif rotationSpeed.axis1KdRpm == nil then
      rotationSpeed.axis1KdRpm = 0
    end

    if args[7] then
      rotationSpeed.axis2KpRpm = parseNumber(args[7], "axis2KpRpm")
    elseif rotationSpeed.axis2KpRpm == nil then
      rotationSpeed.axis2KpRpm = rotationSpeed.axis1KpRpm or 0
    end

    if args[8] then
      rotationSpeed.axis2KdRpm = parseNumber(args[8], "axis2KdRpm")
    elseif rotationSpeed.axis2KdRpm == nil then
      rotationSpeed.axis2KdRpm = rotationSpeed.axis1KdRpm or 0
    end

    if args[9] then
      rotationSpeed.throttleRpmPerPower = parseNumber(args[9], "throttleRpmPerPower")
    elseif rotationSpeed.throttleRpmPerPower == nil then
      rotationSpeed.throttleRpmPerPower = 16
    end

    if rotationSpeed.minTargetRpm == nil then
      rotationSpeed.minTargetRpm = 0
    end
    if rotationSpeed.maxTargetRpm == nil then
      rotationSpeed.maxTargetRpm = math.max(math.abs(tonumber(rotationSpeed.minRpm) or -256), math.abs(tonumber(rotationSpeed.maxRpm) or 256))
    end
    rotationSpeed.round = false

    saveConfig(config)
    print("Saved native rotation speed control to " .. CONFIG_PATH)
    print("  baseRpm=" .. tostring(rotationSpeed.baseRpm))
    print("  maxCorrectionRpm=" .. tostring(rotationSpeed.maxCorrectionRpm))
    print("  axis1KpRpm=" .. tostring(rotationSpeed.axis1KpRpm) .. " axis1KdRpm=" .. tostring(rotationSpeed.axis1KdRpm))
    print("  axis2KpRpm=" .. tostring(rotationSpeed.axis2KpRpm) .. " axis2KdRpm=" .. tostring(rotationSpeed.axis2KdRpm))
    print("  throttleRpmPerPower=" .. tostring(rotationSpeed.throttleRpmPerPower))
    return
  elseif subcommand == "rotation-speed-writes" then
    config.actuator = config.actuator or {}
    config.actuator.rotationSpeed = config.actuator.rotationSpeed or {}

    local rotationSpeed = config.actuator.rotationSpeed
    rotationSpeed.writeInterval = parseNumber(args[3], "intervalSeconds")
    if rotationSpeed.writeInterval < 0 then
      error("intervalSeconds must be non-negative", 0)
    end
    if args[4] then
      rotationSpeed.writeDeadbandRpm = parseNumber(args[4], "deadbandRpm")
      if rotationSpeed.writeDeadbandRpm < 0 then
        error("deadbandRpm must be non-negative", 0)
      end
    elseif rotationSpeed.writeDeadbandRpm == nil then
      rotationSpeed.writeDeadbandRpm = 0.5
    end

    saveConfig(config)
    print("Saved rotation speed write cadence to " .. CONFIG_PATH)
    print("  writeInterval=" .. tostring(rotationSpeed.writeInterval))
    print("  writeDeadbandRpm=" .. tostring(rotationSpeed.writeDeadbandRpm))
    return
  elseif subcommand == "rotation-speed-signs" then
    config.actuator = config.actuator or {}
    config.actuator.rotationSpeed = config.actuator.rotationSpeed or {}

    local rotationSpeed = config.actuator.rotationSpeed
    local mode = string.lower(tostring(args[3] or "auto"))

    if mode == "auto" then
      rotationSpeed.autoRoleSigns = true
      rotationSpeed.roleSigns = nil
      saveConfig(config)
      print("Saved rotation speed role signs: auto")
      print("Next: run aircraft scan so controller-to-rotor geometry is fresh.")
      return
    end

    rotationSpeed.autoRoleSigns = false
    rotationSpeed.roleSigns = {
      front_left = parseNumber(args[3], "front_left sign") < 0 and -1 or 1,
      front_right = parseNumber(args[4], "front_right sign") < 0 and -1 or 1,
      rear_left = parseNumber(args[5], "rear_left sign") < 0 and -1 or 1,
      rear_right = parseNumber(args[6], "rear_right sign") < 0 and -1 or 1,
    }

    saveConfig(config)
    print("Saved rotation speed role signs to " .. CONFIG_PATH)
    print("  " .. roleSignsText(rotationSpeed.roleSigns))
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
  elseif subcommand == "stabilize-interval" then
    local interval = parseNumber(args[3], "seconds")
    if interval <= 0 then
      error("stabilize interval must be greater than zero", 0)
    end

    config.stabilize.interval = interval
    saveConfig(config)
    print("Saved stabilize interval to " .. CONFIG_PATH)
    print("  interval=" .. tostring(config.stabilize.interval))
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
  elseif subcommand == "stabilize-desaturate" then
    config.stabilize.desaturate = parseBoolean(args[3])
    if args[4] then
      config.stabilize.desaturateHeadroom = parseNumber(args[4], "headroomPower")
      if config.stabilize.desaturateHeadroom < 0 then
        error("headroomPower must be non-negative", 0)
      end
    elseif config.stabilize.desaturateHeadroom == nil then
      config.stabilize.desaturateHeadroom = 0.75
    end
    saveConfig(config)
    print("Saved stabilize desaturation to " .. CONFIG_PATH)
    print("  desaturate=" .. tostring(config.stabilize.desaturate))
    print("  desaturateHeadroom=" .. tostring(config.stabilize.desaturateHeadroom))
    return
  elseif subcommand == "stabilize-tilt-comp" then
    config.stabilize.tiltCompensation = parseBoolean(args[3])
    if args[4] then
      config.stabilize.tiltCompensationGain = parseNumber(args[4], "tiltCompensationGain")
      if config.stabilize.tiltCompensationGain < 0 then
        error("tiltCompensationGain must be non-negative", 0)
      end
    elseif config.stabilize.tiltCompensationGain == nil then
      config.stabilize.tiltCompensationGain = 1
    end
    if args[5] then
      config.stabilize.tiltCompensationMaxPower = parseNumber(args[5], "tiltCompensationMaxPower")
      if config.stabilize.tiltCompensationMaxPower < 0 then
        error("tiltCompensationMaxPower must be non-negative", 0)
      end
    elseif config.stabilize.tiltCompensationMaxPower == nil then
      config.stabilize.tiltCompensationMaxPower = 2
    end
    saveConfig(config)
    print("Saved stabilize tilt compensation to " .. CONFIG_PATH)
    print("  tiltCompensation=" .. tostring(config.stabilize.tiltCompensation))
    print("  tiltCompensationGain=" .. tostring(config.stabilize.tiltCompensationGain))
    print("  tiltCompensationMaxPower=" .. tostring(config.stabilize.tiltCompensationMaxPower))
    return
  elseif subcommand == "stabilize-dither" then
    config.stabilize.signalDither = parseBoolean(args[3])
    saveConfig(config)
    print("Saved stabilize.signalDither=" .. tostring(config.stabilize.signalDither) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "yaw" then
    config.yaw = config.yaw or {}
    config.yaw.enabled = parseBoolean(args[3])

    if args[4] then
      config.yaw.rateKd = parseNumber(args[4], "rateKd")
      if config.yaw.rateKd < 0 then
        error("rateKd must be non-negative", 0)
      end
    elseif config.yaw.rateKd == nil then
      config.yaw.rateKd = 0.15
    end

    if args[5] then
      config.yaw.maxTiltDeg = parseNumber(args[5], "maxTiltDeg")
      if config.yaw.maxTiltDeg < 0 or config.yaw.maxTiltDeg > 12 then
        error("maxTiltDeg must be from 0 to 12", 0)
      end
    elseif config.yaw.maxTiltDeg == nil then
      config.yaw.maxTiltDeg = 8
    end

    if args[6] then
      local sign = parseNumber(args[6], "sign")
      config.yaw.sign = sign < 0 and -1 or 1
    elseif config.yaw.sign == nil then
      config.yaw.sign = 1
    end

    if args[7] then
      config.yaw.commandLateral = parseNumber(args[7], "commandLateral")
      if config.yaw.commandLateral < 0 then
        error("commandLateral must be non-negative", 0)
      end
    elseif config.yaw.commandLateral == nil then
      config.yaw.commandLateral = 0.08
    end

    if config.yaw.deadbandDegPerSecond == nil then
      config.yaw.deadbandDegPerSecond = 0.5
    end
    if config.yaw.clearOnExit == nil then
      config.yaw.clearOnExit = true
    end

    saveConfig(config)
    print("Saved yaw control to " .. CONFIG_PATH)
    print("  enabled=" .. tostring(config.yaw.enabled))
    print("  rateKd=" .. tostring(config.yaw.rateKd))
    print("  maxTiltDeg=" .. tostring(config.yaw.maxTiltDeg))
    print("  deadbandDegPerSecond=" .. tostring(config.yaw.deadbandDegPerSecond))
    print("  sign=" .. tostring(config.yaw.sign))
    print("  commandLateral=" .. tostring(config.yaw.commandLateral))
    print("  clearOnExit=" .. tostring(config.yaw.clearOnExit))
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
    config.killSwitch.source = "side"
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
    print("  source=" .. tostring(config.killSwitch.source))
    print("  side=" .. tostring(config.killSwitch.side))
    print("  activeHigh=" .. tostring(config.killSwitch.activeHigh))
    return
  elseif subcommand == "killswitch-router" then
    config.killSwitch = config.killSwitch or {}
    config.killSwitch.enabled = true
    config.killSwitch.source = "router"
    config.killSwitch.binding = {
      x = parseInteger(args[3], "x"),
      y = parseInteger(args[4], "y"),
      z = parseInteger(args[5], "z"),
      side = normalizeRedstoneSide(args[6] or "up"),
    }

    if args[7] then
      config.killSwitch.activeHigh = parseBoolean(args[7])
    elseif config.killSwitch.activeHigh == nil then
      config.killSwitch.activeHigh = true
    end

    saveConfig(config)
    print("Saved router kill switch to " .. CONFIG_PATH)
    print("  enabled=" .. tostring(config.killSwitch.enabled))
    print("  source=" .. tostring(config.killSwitch.source))
    print("  binding=" .. bindingText(config.killSwitch.binding))
    print("  activeHigh=" .. tostring(config.killSwitch.activeHigh))
    return
  elseif subcommand == "killswitch-key" then
    config.killSwitch = config.killSwitch or {}
    local wasEnabled = config.killSwitch.enabled == true
    config.killSwitch.keyEnabled = parseBoolean(args[3])
    if args[4] then
      config.killSwitch.key = string.lower(tostring(args[4]))
    elseif not config.killSwitch.key then
      config.killSwitch.key = "k"
    end
    if config.killSwitch.keyEnabled then
      config.killSwitch.enabled = true
      if not wasEnabled and not config.killSwitch.binding then
        config.killSwitch.source = "key"
      end
    end

    saveConfig(config)
    print("Saved kill switch key to " .. CONFIG_PATH)
    print("  enabled=" .. tostring(config.killSwitch.enabled))
    print("  source=" .. tostring(config.killSwitch.source))
    print("  keyEnabled=" .. tostring(config.killSwitch.keyEnabled))
    print("  key=" .. tostring(config.killSwitch.key))
    return
  elseif subcommand == "killswitch-source" then
    config.killSwitch = config.killSwitch or {}
    if not args[3] then
      error("killswitch-source needs key, side, or router", 0)
    end
    local source = normalizeKillSwitchSource(args[3])
    if source == "router" and not config.killSwitch.binding then
      error("source=router needs a binding; use aircraft config killswitch-router <x> <y> <z> [side] [activeHigh]", 0)
    end

    config.killSwitch.enabled = true
    config.killSwitch.source = source
    if source == "key" then
      config.killSwitch.keyEnabled = true
      config.killSwitch.key = config.killSwitch.key or "k"
    elseif source == "side" then
      config.killSwitch.side = config.killSwitch.side or "front"
      if config.killSwitch.activeHigh == nil then
        config.killSwitch.activeHigh = true
      end
    elseif source == "router" and config.killSwitch.activeHigh == nil then
      config.killSwitch.activeHigh = true
    end

    saveConfig(config)
    print("Saved kill switch source to " .. CONFIG_PATH)
    print("  enabled=" .. tostring(config.killSwitch.enabled))
    print("  source=" .. tostring(config.killSwitch.source))
    print("  keyEnabled=" .. tostring(config.killSwitch.keyEnabled))
    print("  key=" .. tostring(config.killSwitch.key))
    print("  side=" .. tostring(config.killSwitch.side))
    print("  binding=" .. bindingText(config.killSwitch.binding))
    return
  elseif subcommand == "controller" then
    config.controller = config.controller or {}
    config.controller.enabled = parseBoolean(args[3])
    saveConfig(config)
    print("Saved controller.enabled=" .. tostring(config.controller.enabled) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "controller-type" then
    local typeName = controller.normalizeType(args[3])
    if typeName ~= "redstone_router" and typeName ~= "keyboard" then
      error("controller type must be redstone_router or keyboard", 0)
    end

    config.controller = config.controller or {}
    config.controller.type = typeName
    saveConfig(config)
    print("Saved controller.type=" .. tostring(typeName) .. " to " .. CONFIG_PATH)
    return
  elseif subcommand == "controller-layout" then
    local x = parseInteger(args[3], "x")
    local y = parseInteger(args[4], "y")
    local z = parseInteger(args[5], "z")
    local side = normalizeRedstoneSide(args[6] or "up")
    local frontAxis, leftAxis, frontSource, leftSource = controllerLayoutAxes(config)

    config.controller = config.controller or {}
    config.controller.bindings = controller.defaultBindings(x, y, z, side, frontAxis, leftAxis)
    saveConfig(config)
    print("Saved controller layout to " .. CONFIG_PATH)
    print("  anchor=shift")
    print("  frontAxis=" .. coords.axisLabel(frontAxis) .. " source=" .. tostring(frontSource))
    print("  leftAxis=" .. coords.axisLabel(leftAxis) .. " source=" .. tostring(leftSource))
    print("  w=" .. bindingText(config.controller.bindings.w))
    print("  shift=" .. bindingText(config.controller.bindings.shift))
    print("  a=" .. bindingText(config.controller.bindings.a))
    print("  s=" .. bindingText(config.controller.bindings.s))
    print("  d=" .. bindingText(config.controller.bindings.d))
    print("  space=" .. bindingText(config.controller.bindings.space))
    print("  q=" .. bindingText(config.controller.bindings.q))
    print("  e=" .. bindingText(config.controller.bindings.e))
    return
  elseif subcommand == "controller-bind" then
    local key = string.lower(tostring(args[3] or ""))
    if not validControllerKey(key) then
      error("controller key must be w, a, s, d, q, e, space, shift, or k", 0)
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
  elseif subcommand == "controller-throttle" then
    local controllerConfig = config.controller or {}
    local throttleMode = normalizeThrottleMode(args[3])

    config.controller = controllerConfig
    config.controller.throttleMode = throttleMode

    if args[4] then
      config.controller.throttlePower = parseNumber(args[4], "maxPower")
      if config.controller.throttlePower < 0 then
        error("maxPower must be non-negative", 0)
      end
    elseif config.controller.throttlePower == nil then
      config.controller.throttlePower = 1
    end

    if args[5] then
      config.controller.throttleSlewPowerPerSecond = parseNumber(args[5], "slewPowerPerSecond")
      if config.controller.throttleSlewPowerPerSecond < 0 then
        error("slewPowerPerSecond must be non-negative", 0)
      end
    elseif config.controller.throttleSlewPowerPerSecond == nil then
      config.controller.throttleSlewPowerPerSecond = 4
    end

    saveConfig(config)
    print("Saved controller throttle to " .. CONFIG_PATH)
    print("  throttleMode=" .. tostring(config.controller.throttleMode))
    print("  throttlePower=" .. tostring(config.controller.throttlePower))
    print("  throttleSlewPowerPerSecond=" .. tostring(config.controller.throttleSlewPowerPerSecond))
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
    elseif arg == "--base-rpm" then
      options.baseRpm = tonumber(args[i + 1])
      if not options.baseRpm then
        error("--base-rpm needs a number", 0)
      end
      i = i + 2
    elseif arg == "--controller" then
      options.controller = true
      i = i + 1
    elseif arg == "--no-controller" then
      options.controller = false
      i = i + 1
    elseif arg == "--controller-type" then
      options.controllerType = args[i + 1]
      if not options.controllerType then
        error("--controller-type needs a type", 0)
      end
      i = i + 2
    elseif arg == "--actuator-type" then
      if not args[i + 1] then
        error("--actuator-type needs a type", 0)
      end
      options.actuatorType = actuators.normalizeType(args[i + 1])
      i = i + 2
    elseif arg == "--yaw" then
      options.yaw = true
      i = i + 1
    elseif arg == "--no-yaw" then
      options.yaw = false
      i = i + 1
    elseif arg == "--yaw-kd" then
      options.yawRateKd = tonumber(args[i + 1])
      if not options.yawRateKd or options.yawRateKd < 0 then
        error("--yaw-kd needs a non-negative number", 0)
      end
      i = i + 2
    elseif arg == "--yaw-max-tilt-deg" then
      options.yawMaxTiltDeg = tonumber(args[i + 1])
      if not options.yawMaxTiltDeg or options.yawMaxTiltDeg < 0 or options.yawMaxTiltDeg > 12 then
        error("--yaw-max-tilt-deg needs a number from 0 to 12", 0)
      end
      i = i + 2
    elseif arg == "--yaw-deadband-deg" then
      options.yawDeadbandDegPerSecond = tonumber(args[i + 1])
      if not options.yawDeadbandDegPerSecond or options.yawDeadbandDegPerSecond < 0 then
        error("--yaw-deadband-deg needs a non-negative number", 0)
      end
      i = i + 2
    elseif arg == "--yaw-sign" then
      local sign = tonumber(args[i + 1])
      if not sign then
        error("--yaw-sign needs -1 or 1", 0)
      end
      options.yawSign = sign < 0 and -1 or 1
      i = i + 2
    elseif arg == "--yaw-command" or arg == "--yaw-command-lateral" then
      options.yawCommandLateral = tonumber(args[i + 1])
      if not options.yawCommandLateral or options.yawCommandLateral < 0 then
        error(arg .. " needs a non-negative number", 0)
      end
      i = i + 2
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
      if args[i + 1] and string.sub(tostring(args[i + 1]), 1, 2) ~= "--" then
        options.nixies = parseBoolean(args[i + 1])
        i = i + 2
      else
        options.nixies = true
        i = i + 1
      end
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
      if not options.interval or options.interval <= 0 then
        error("--interval needs a positive number", 0)
      end
      i = i + 2
    elseif arg == "--kp" then
      options.kp = tonumber(args[i + 1])
      if not options.kp then
        error("--kp needs a number", 0)
      end
      i = i + 2
    elseif arg == "--kp-rpm" then
      options.kpRpm = tonumber(args[i + 1])
      if not options.kpRpm then
        error("--kp-rpm needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-kp" then
      options.axis1Kp = tonumber(args[i + 1])
      if not options.axis1Kp then
        error("--axis1-kp needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-kp-rpm" then
      options.axis1KpRpm = tonumber(args[i + 1])
      if not options.axis1KpRpm then
        error("--axis1-kp-rpm needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-kp" then
      options.axis2Kp = tonumber(args[i + 1])
      if not options.axis2Kp then
        error("--axis2-kp needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-kp-rpm" then
      options.axis2KpRpm = tonumber(args[i + 1])
      if not options.axis2KpRpm then
        error("--axis2-kp-rpm needs a number", 0)
      end
      i = i + 2
    elseif arg == "--kd" then
      options.kd = tonumber(args[i + 1])
      if not options.kd then
        error("--kd needs a number", 0)
      end
      i = i + 2
    elseif arg == "--kd-rpm" then
      options.kdRpm = tonumber(args[i + 1])
      if not options.kdRpm then
        error("--kd-rpm needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-kd" then
      options.axis1Kd = tonumber(args[i + 1])
      if not options.axis1Kd then
        error("--axis1-kd needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-kd-rpm" then
      options.axis1KdRpm = tonumber(args[i + 1])
      if not options.axis1KdRpm then
        error("--axis1-kd-rpm needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-kd" then
      options.axis2Kd = tonumber(args[i + 1])
      if not options.axis2Kd then
        error("--axis2-kd needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-kd-rpm" then
      options.axis2KdRpm = tonumber(args[i + 1])
      if not options.axis2KdRpm then
        error("--axis2-kd-rpm needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-trim" then
      options.axis1Trim = tonumber(args[i + 1])
      if not options.axis1Trim then
        error("--axis1-trim needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis1-trim-rpm" then
      options.axis1TrimRpm = tonumber(args[i + 1])
      if not options.axis1TrimRpm then
        error("--axis1-trim-rpm needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-trim" then
      options.axis2Trim = tonumber(args[i + 1])
      if not options.axis2Trim then
        error("--axis2-trim needs a number", 0)
      end
      i = i + 2
    elseif arg == "--axis2-trim-rpm" then
      options.axis2TrimRpm = tonumber(args[i + 1])
      if not options.axis2TrimRpm then
        error("--axis2-trim-rpm needs a number", 0)
      end
      i = i + 2
    elseif arg == "--max-correction" then
      options.maxCorrection = tonumber(args[i + 1])
      if not options.maxCorrection or options.maxCorrection < 0 then
        error("--max-correction needs a non-negative number", 0)
      end
      i = i + 2
    elseif arg == "--max-correction-rpm" then
      options.maxCorrectionRpm = tonumber(args[i + 1])
      if not options.maxCorrectionRpm or options.maxCorrectionRpm < 0 then
        error("--max-correction-rpm needs a non-negative number", 0)
      end
      i = i + 2
    elseif arg == "--throttle-rpm-per-power" then
      options.throttleRpmPerPower = tonumber(args[i + 1])
      if not options.throttleRpmPerPower then
        error("--throttle-rpm-per-power needs a number", 0)
      end
      i = i + 2
    elseif arg == "--write-interval" then
      options.writeInterval = tonumber(args[i + 1])
      if not options.writeInterval or options.writeInterval < 0 then
        error("--write-interval needs a non-negative number", 0)
      end
      i = i + 2
    elseif arg == "--write-deadband-rpm" then
      options.writeDeadbandRpm = tonumber(args[i + 1])
      if not options.writeDeadbandRpm or options.writeDeadbandRpm < 0 then
        error("--write-deadband-rpm needs a non-negative number", 0)
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

local function runKillSwitch()
  local config = loadConfig()
  local options = parseCommandOptions(2)

  flightControl.probeKillSwitch(config, options)
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
elseif command == "killswitch" then
  local ok, result = pcall(runKillSwitch)
  if not ok then
    print("aircraft killswitch failed: " .. tostring(result))
    error("aircraft killswitch failed", 0)
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
