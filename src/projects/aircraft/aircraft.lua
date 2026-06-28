local coords = require("lib.aircraft.coords")
local actuatorTest = require("lib.aircraft.actuator_test")
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
  absoluteSignalMax = 10,
  maxAttitudeDelta = 2,
  statusReadLimit = 8,
  reportPath = "/aircraft_scan.txt",
  statusReportPath = "/aircraft_status.txt",
  actuatorReportPath = "/aircraft_actuator_test.txt",
  sendWebhook = true,
}

local function usage()
  print("aircraft scan [options]")
  print("aircraft status")
  print("aircraft config show")
  print("aircraft config axes <frontAxis> <leftAxis>")
  print("aircraft config dry-run <true|false>")
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
  print("  maxAttitudeDelta=" .. tostring(config.maxAttitudeDelta))
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
