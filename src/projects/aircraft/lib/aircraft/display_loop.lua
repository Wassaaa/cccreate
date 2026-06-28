local coords = require("lib.aircraft.coords")
local displays = require("lib.aircraft.displays")
local reporting = require("lib.aircraft.reporting")

local displayLoop = {}

local ROLE_ORDER = {
  "front_left",
  "front_right",
  "rear_left",
  "rear_right",
}

local function now()
  return os.date("%Y-%m-%d %H:%M:%S")
end

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

local function safePeripheralTypes(name)
  local values = { pcall(peripheral.getType, name) }
  local ok = table.remove(values, 1)

  if not ok then
    return {}
  end

  return values
end

local function isRouterType(types)
  for _, typeName in ipairs(types or {}) do
    if string.find(string.lower(tostring(typeName)), "peripheral_router", 1, true) then
      return true
    end
  end

  return false
end

local function findRouter()
  for _, peripheralName in ipairs(peripheral.getNames()) do
    local types = safePeripheralTypes(peripheralName)

    if isRouterType(types) then
      local wrapped = peripheral.wrap(peripheralName)
      if wrapped and type(wrapped.wrap) == "function" then
        return wrapped, peripheralName
      end
    end
  end

  local router = peripheral.find("peripheral_router")
  if router and type(router.wrap) == "function" then
    return router, nil
  end

  return nil, nil
end

local function loadScan(path)
  if not fs.exists(path) then
    error("No aircraft scan at " .. path .. ". Run aircraft scan first.", 0)
  end

  local handle = fs.open(path, "r")
  if not handle then
    error("Could not open " .. path, 0)
  end

  local contents = handle.readAll()
  handle.close()

  local report = textutils.unserialize(contents)
  if type(report) ~= "table" or report.kind ~= "aircraft_scan" then
    error(path .. " is not an aircraft_scan report", 0)
  end

  return report
end

local function wrapRole(router, scan, role)
  local mapped = scan.orientation
    and scan.orientation.roles
    and scan.orientation.roles.scalarActuator
    and scan.orientation.roles.scalarActuator[role]

  if not mapped or not mapped.coord then
    return nil, "missing scalar role"
  end

  local coord = mapped.coord
  local ok, objectOrError = pcall(router.wrap, coord.x, coord.y, coord.z)

  if not ok then
    return nil, "wrap error: " .. tostring(objectOrError)
  elseif not objectOrError then
    return nil, "no peripheral at " .. coords.label(coord)
  end

  return {
    coord = copyPlain(coord),
    object = objectOrError,
  }, nil
end

local function readSignal(device)
  if type(device.object.getSignal) ~= "function" then
    return nil, {
      ok = false,
      error = "missing getSignal",
    }
  end

  local ok, valueOrError = pcall(device.object.getSignal)
  if not ok then
    return nil, {
      ok = false,
      error = tostring(valueOrError),
    }
  end

  return tonumber(valueOrError), {
    ok = true,
    value = valueOrError,
  }
end

local function wrapActuators(router, scan)
  local devices = {}
  local errors = {}

  for _, role in ipairs(ROLE_ORDER) do
    local device, errorMessage = wrapRole(router, scan, role)

    if device then
      devices[role] = device
    else
      errors[role] = errorMessage
    end
  end

  return devices, errors
end

local function readSignals(devices)
  local signals = {}
  local reads = {}

  for _, role in ipairs(ROLE_ORDER) do
    local device = devices[role]

    if device then
      local signal, read = readSignal(device)
      reads[role] = {
        coord = copyPlain(device.coord),
        signal = read,
      }

      if signal ~= nil then
        signals[role] = signal
      end
    end
  end

  return signals, reads
end

local function signalLine(signals)
  local parts = {}

  for _, role in ipairs(ROLE_ORDER) do
    table.insert(parts, role .. "=" .. tostring(signals[role] or "?"))
  end

  return table.concat(parts, " ")
end

local function saveAndSend(config, report)
  local path = config.displayReportPath or "/aircraft_displays.txt"

  reporting.save(report, path)
  if config.sendWebhook ~= false then
    reporting.send(report)
  end

  return path
end

function displayLoop.run(config, options)
  local scan = loadScan(config.reportPath or "/aircraft_scan.txt")
  local router, routerName = findRouter()

  if not router then
    error("No peripheral_router with wrap(x, y, z) found", 0)
  end

  local actuatorDevices, actuatorErrors = wrapActuators(router, scan)
  local displayContext = displays.collect(config, router, scan, options)
  local interval = tonumber(options.interval) or 0.5
  local seconds = tonumber(options.seconds)
  local deadline = seconds and (os.clock() + seconds) or nil
  local report = {
    kind = "aircraft_display_loop",
    createdAt = now(),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    request = {
      seconds = seconds,
      interval = interval,
    },
    router = {
      name = routerName or (scan.router and scan.router.name),
    },
    actuatorErrors = actuatorErrors,
    displays = displays.describe(displayContext),
    frames = {},
  }

  repeat
    local signals, reads = readSignals(actuatorDevices)
    local frame = {
      index = #report.frames + 1,
      reads = reads,
      signals = copyPlain(signals),
      displayResults = displays.updateSignals(displayContext, signals),
    }

    table.insert(report.frames, frame)
    print(signalLine(signals))

    if not deadline or os.clock() >= deadline then
      break
    end

    sleep(math.min(interval, math.max(0, deadline - os.clock())))
  until false

  local path = saveAndSend(config, report)
  print("Aircraft display report: " .. path)
  print("frames=" .. tostring(#report.frames))

  return report
end

return displayLoop
