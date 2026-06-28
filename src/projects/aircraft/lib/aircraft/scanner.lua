local classify = require("lib.aircraft.classify")
local coords = require("lib.aircraft.coords")

local scanner = {}

local function now()
  if os and type(os.date) == "function" then
    return os.date("%Y-%m-%d %H:%M:%S")
  end

  return "unknown"
end

local function sortedFunctionNames(object)
  local names = {}

  for name, value in pairs(object or {}) do
    if type(value) == "function" then
      table.insert(names, name)
    end
  end

  table.sort(names)
  return names
end

local function sorted(values)
  local copy = {}

  for _, value in ipairs(values or {}) do
    table.insert(copy, value)
  end

  table.sort(copy)
  return copy
end

local function sanitize(value, depth)
  depth = depth or 0

  if type(value) == "number" or type(value) == "string" or type(value) == "boolean" or value == nil then
    return value
  end

  if type(value) ~= "table" then
    return tostring(value)
  end

  if depth >= 2 then
    return "<table>"
  end

  local result = {}
  local count = 0

  for key, child in pairs(value) do
    count = count + 1
    if count > 16 then
      result["..."] = "truncated"
      break
    end

    result[tostring(key)] = sanitize(child, depth + 1)
  end

  return result
end

local function safeCall(object, method)
  if type(object[method]) ~= "function" then
    return {
      ok = false,
      error = "missing method",
    }
  end

  local values = { pcall(object[method]) }
  local ok = table.remove(values, 1)

  if not ok then
    return {
      ok = false,
      error = tostring(values[1]),
    }
  end

  if #values == 1 then
    return {
      ok = true,
      value = sanitize(values[1]),
    }
  end

  local cleanValues = {}
  for index, value in ipairs(values) do
    cleanValues[index] = sanitize(value)
  end

  return {
    ok = true,
    values = cleanValues,
  }
end

local function sampleGetters(object, methods, limit)
  local samples = {}

  for _, method in ipairs(classify.sampleMethodList(methods, limit)) do
    samples[method] = safeCall(object, method)
  end

  return samples
end

local function safePeripheralTypes(name)
  local values = { pcall(peripheral.getType, name) }
  local ok = table.remove(values, 1)

  if not ok then
    return {}, tostring(values[1])
  end

  return values, nil
end

local function directPeripherals()
  local entries = {}

  for _, name in ipairs(peripheral.getNames()) do
    local types, typeError = safePeripheralTypes(name)
    local methods = {}
    local methodsError = nil

    local ok, result = pcall(peripheral.getMethods, name)
    if ok and type(result) == "table" then
      methods = sorted(result)
    elseif not ok then
      methodsError = tostring(result)
    end

    table.insert(entries, {
      name = name,
      types = types,
      typeError = typeError,
      methods = methods,
      methodsError = methodsError,
    })
  end

  table.sort(entries, function(left, right)
    return tostring(left.name) < tostring(right.name)
  end)

  return entries
end

local function findRouter()
  local router, name = peripheral.find("peripheral_router")

  if router and type(router.wrap) == "function" then
    return router, name
  end

  for _, peripheralName in ipairs(peripheral.getNames()) do
    local types = { safePeripheralTypes(peripheralName) }
    local typeText = table.concat(types[1] or {}, " ")

    if string.find(string.lower(typeText), "peripheral_router", 1, true) then
      local wrapped = peripheral.wrap(peripheralName)
      if wrapped and type(wrapped.wrap) == "function" then
        return wrapped, peripheralName
      end
    end
  end

  return nil, nil
end

local function routerMethods(routerName, router)
  local methods = {}

  if routerName then
    local ok, result = pcall(peripheral.getMethods, routerName)
    if ok and type(result) == "table" then
      methods = sorted(result)
    end
  end

  if #methods == 0 then
    methods = sortedFunctionNames(router)
  end

  return methods
end

local function includeError(report, entry, limit, field)
  field = field or "errors"
  report.summary.errors = report.summary.errors + 1

  if #report[field] < limit then
    table.insert(report[field], entry)
  end
end

local function routerHasPresenceCheck(router)
  return router and type(router.isPresent) == "function"
end

local function shouldWrapCoordinate(router, report, x, y, z, errorLimit)
  if not routerHasPresenceCheck(router) then
    return true
  end

  report.summary.presenceChecks = report.summary.presenceChecks + 1

  local ok, presentOrError = pcall(router.isPresent, x, y, z)
  if not ok then
    report.summary.presenceErrors = report.summary.presenceErrors + 1
    includeError(report, {
      phase = "presence",
      coord = {
        x = x,
        y = y,
        z = z,
        key = coords.key(x, y, z),
      },
      error = tostring(presentOrError),
    }, errorLimit, "presenceErrors")
    return true
  end

  if not presentOrError then
    report.summary.presenceMisses = report.summary.presenceMisses + 1
    return false
  end

  return true
end

local function makeEntry(object, x, y, z, config)
  local methods = sortedFunctionNames(object)
  local categories, reasons = classify.classifyMethods(methods)
  local categoryList = classify.categoryList(categories)

  return {
    coord = {
      x = x,
      y = y,
      z = z,
      key = coords.key(x, y, z),
    },
    categories = categoryList,
    categoryReasons = reasons,
    methodCount = #methods,
    methods = methods,
    samples = sampleGetters(object, methods, config.scan.sampleLimit),
  }
end

function scanner.scan(config)
  local router, routerName = findRouter()
  local bounds = coords.scanBounds(config)
  local report = {
    kind = "aircraft_scan",
    createdAt = now(),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    scanBounds = bounds,
    config = {
      frontAxis = config.frontAxis,
      leftAxis = config.leftAxis,
      dryRun = config.dryRun ~= false,
      absoluteSignalMax = config.absoluteSignalMax,
      maxAttitudeDelta = config.maxAttitudeDelta,
    },
    router = {
      name = routerName,
      methods = router and routerMethods(routerName, router) or {},
      presenceMethod = routerHasPresenceCheck(router) and "isPresent" or nil,
    },
    directPeripherals = directPeripherals(),
    peripherals = {},
    errors = {},
    presenceErrors = {},
    summary = {
      scanned = 0,
      found = 0,
      errors = 0,
      presenceChecks = 0,
      presenceMisses = 0,
      presenceErrors = 0,
      wrapAttempts = 0,
      wrapErrors = 0,
      categories = {},
    },
  }

  for _, category in ipairs(classify.CATEGORY_ORDER) do
    report.summary.categories[category] = 0
  end

  if not router then
    report.error = "No peripheral_router with wrap(x, y, z) found"
    return report
  end

  local errorLimit = tonumber(config.scan.errorLimit) or 12

  coords.iterate(bounds, function(x, y, z)
    report.summary.scanned = report.summary.scanned + 1

    if not shouldWrapCoordinate(router, report, x, y, z, errorLimit) then
      return
    end

    report.summary.wrapAttempts = report.summary.wrapAttempts + 1
    local ok, objectOrError = pcall(router.wrap, x, y, z)

    if not ok then
      report.summary.wrapErrors = report.summary.wrapErrors + 1
      includeError(report, {
        phase = "wrap",
        coord = {
          x = x,
          y = y,
          z = z,
          key = coords.key(x, y, z),
        },
        error = tostring(objectOrError),
      }, errorLimit)
      return
    end

    if not objectOrError then
      return
    end

    local entry = makeEntry(objectOrError, x, y, z, config)
    table.insert(report.peripherals, entry)
    report.summary.found = report.summary.found + 1

    for _, category in ipairs(entry.categories) do
      report.summary.categories[category] = (report.summary.categories[category] or 0) + 1
    end
  end)

  table.sort(report.peripherals, function(left, right)
    if left.coord.y ~= right.coord.y then
      return left.coord.y < right.coord.y
    end

    if left.coord.z ~= right.coord.z then
      return left.coord.z < right.coord.z
    end

    return left.coord.x < right.coord.x
  end)

  return report
end

return scanner
