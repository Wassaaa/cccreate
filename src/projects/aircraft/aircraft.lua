local coords = require("lib.aircraft.coords")
local actuatorTest = require("lib.aircraft.actuator_test")
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
  statusReportPath = "/aircraft_status.txt",
  actuatorReportPath = "/aircraft_actuator_test.txt",
  stabilizeReportPath = "/aircraft_stabilize.txt",
  stabilize = {
    interval = 0.1,
    seconds = 1,
    basePower = 0,
    axis1Kp = 0.08,
    axis2Kp = 0.08,
    axis1Kd = 0.08,
    axis2Kd = 0.08,
    axis1Sign = 1,
    axis2Sign = 1,
    brakeOnExit = true,
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
  print("aircraft config stabilize-signs <-1|1> <-1|1>")
  print("aircraft config stabilize-gains <axis1Kp> <axis1Kd> [axis2Kp] [axis2Kd]")
  print("aircraft brake [role|all] [--apply]")
  print("aircraft level-set")
  print("aircraft stabilize [--apply] [--seconds n] [--base-power n] [--kp n] [--kd n]")
  print("aircraft signal <role|all> <0-15> [--apply] [--seconds n]")
  print("aircraft zero [role|all] [--apply]")
  print("aircraft help")
  print("")
  print("Options:")
  print("  --radius <n>       set x/z radius")
  print("  --x-radius <n>     set x scan radius")
  print("  --y-radius <n>     set y scan radius")
  print("  --z-radius <n>     set z scan radius")
  print("  --sample-limit <n> max getter samples per peripheral")
  print("  --out <path>       default /aircraft_scan.txt")
  print("  --no-webhook       save local report only")
  print("")
  print("signal/zero are dry-run unless --apply is used and config dryRun=false.")
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
    return config, CONFIG_PATH
  end

  return config, "built-in defaults"
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

  handle.write("return ")
  handle.write(textutils.serialize(config))
  handle.write("\n")
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

local function parseSign(value, label)
  local number = tonumber(value)
  if number == 1 or number == -1 then
    return number
  end

  error(label .. " must be -1 or 1", 0)
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
            print("  " .. role .. "=" .. coords.label(entry.coord))
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

  reporting.save(report, path)
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

local function printConfig(config, source)
  print("aircraft config from " .. tostring(source))
  print("  frontAxis=" .. tostring(config.frontAxis))
  print("  leftAxis=" .. tostring(config.leftAxis))
  print("  dryRun=" .. tostring(config.dryRun))
  print("  absoluteSignalMax=" .. tostring(config.absoluteSignalMax))
  print("  brakeSignal=" .. tostring(config.brakeSignal))
  print("  maxAttitudeDelta=" .. tostring(config.maxAttitudeDelta))
  print("  stabilize.axis1Sign=" .. tostring(config.stabilize.axis1Sign))
  print("  stabilize.axis2Sign=" .. tostring(config.stabilize.axis2Sign))
  print("  stabilize.axis1Kp=" .. tostring(config.stabilize.axis1Kp))
  print("  stabilize.axis1Kd=" .. tostring(config.stabilize.axis1Kd))
  print("  stabilize.axis2Kp=" .. tostring(config.stabilize.axis2Kp))
  print("  stabilize.axis2Kd=" .. tostring(config.stabilize.axis2Kd))
  if config.level and config.level.angles then
    print("  level.angles=" .. textutils.serialize(config.level.angles))
  else
    print("  level.angles=nil")
  end
end

local function runConfig()
  local config, source = loadConfig()
  local subcommand = args[2] or "show"

  if subcommand == "show" then
    printConfig(config, source)
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
  elseif subcommand == "stabilize-signs" then
    config.stabilize.axis1Sign = parseSign(args[3], "axis1Sign")
    config.stabilize.axis2Sign = parseSign(args[4], "axis2Sign")
    saveConfig(config)
    print("Saved stabilize signs to " .. CONFIG_PATH)
    print("  axis1Sign=" .. tostring(config.stabilize.axis1Sign))
    print("  axis2Sign=" .. tostring(config.stabilize.axis2Sign))
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
    elseif arg == "--base-power" then
      options.basePower = tonumber(args[i + 1])
      if not options.basePower then
        error("--base-power needs a number", 0)
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
    elseif arg == "--axis1-sign" then
      options.axis1Sign = parseSign(args[i + 1], "--axis1-sign")
      i = i + 2
    elseif arg == "--axis2-sign" then
      options.axis2Sign = parseSign(args[i + 1], "--axis2-sign")
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
    error("Usage: aircraft signal <role|all> <0-15> [--apply] [--seconds n]", 0)
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

local function runLevelSet()
  local config = loadConfig()
  local report = flightControl.levelSet(config)

  config.level = report.level
  saveConfig(config)
  print("Saved level-set to " .. CONFIG_PATH)
end

local function runStabilize()
  local config = loadConfig()
  local options = parseCommandOptions(2)

  flightControl.stabilize(config, options)
end

local function runZero()
  local config = loadConfig()
  local role = args[2] or "all"
  local optionStart = 3

  if string.sub(role, 1, 2) == "--" then
    role = "all"
    optionStart = 2
  end

  local options = parseCommandOptions(optionStart)
  options.role = role

  actuatorTest.zero(config, options)
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
elseif command == "level-set" then
  local ok, result = pcall(runLevelSet)
  if not ok then
    print("aircraft level-set failed: " .. tostring(result))
    error("aircraft level-set failed", 0)
  end
elseif command == "stabilize" then
  local ok, result = pcall(runStabilize)
  if not ok then
    print("aircraft stabilize failed: " .. tostring(result))
    error("aircraft stabilize failed", 0)
  end
elseif command == "zero" then
  local ok, result = pcall(runZero)
  if not ok then
    print("aircraft zero failed: " .. tostring(result))
    error("aircraft zero failed", 0)
  end
else
  usage()
  error("Unknown aircraft command: " .. tostring(command), 0)
end
