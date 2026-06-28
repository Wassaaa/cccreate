local classify = require("lib.aircraft.classify")
local coords = require("lib.aircraft.coords")

local scanner = {}

local SIDE_NAMES = {
  front = true,
  back = true,
  left = true,
  right = true,
  top = true,
  bottom = true,
}

local SIDE_AXIS = {
  top = { x = 0, y = 1, z = 0 },
  bottom = { x = 0, y = -1, z = 0 },
}

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

local function methodKey(methods)
  return table.concat(methods or {}, "\n")
end

local function copyCoord(coord)
  if not coord then
    return nil
  end

  return {
    x = coord.x,
    y = coord.y,
    z = coord.z,
    key = coord.key,
  }
end

local function copyList(values)
  local result = {}

  for index, value in ipairs(values or {}) do
    result[index] = value
  end

  return result
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

local function isRouterType(types)
  for _, typeName in ipairs(types or {}) do
    if string.find(string.lower(tostring(typeName)), "peripheral_router", 1, true) then
      return true
    end
  end

  return false
end

local function hasCategory(entry, category)
  for _, value in ipairs(entry.categories or {}) do
    if value == category then
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
    methodKey = methodKey(methods),
    methods = methods,
    samples = sampleGetters(object, methods, config.scan.sampleLimit),
  }
end

local function directComputerCoord(routerName)
  local sideAxis = SIDE_AXIS[routerName]
  if not sideAxis then
    return nil, "router is not on top/bottom, so computer origin needs another side hint"
  end

  return coords.neg(sideAxis), nil
end

local function inferDirectSideHints(report)
  local hints = {}

  if not report.orientation.computerCoord then
    return hints
  end

  for _, direct in ipairs(report.directPeripherals or {}) do
    if SIDE_NAMES[direct.name] and not isRouterType(direct.types) then
      local directKey = methodKey(direct.methods)
      local matches = {}

      if directKey ~= "" then
        for _, entry in ipairs(report.peripherals or {}) do
          if entry.methodKey == directKey
              and coords.manhattan(entry.coord, report.orientation.computerCoord) == 1 then
            table.insert(matches, entry)
          end
        end
      end

      if #matches == 1 then
        local vector = coords.sub(matches[1].coord, report.orientation.computerCoord)
        hints[direct.name] = {
          side = direct.name,
          coord = copyCoord(matches[1].coord),
          vector = vector,
          type = table.concat(direct.types or {}, ","),
          methodCount = #direct.methods,
        }
      elseif #matches > 1 then
        hints[direct.name] = {
          side = direct.name,
          ambiguous = true,
          count = #matches,
          methodCount = #direct.methods,
        }
      end
    end
  end

  return hints
end

local function setAxisIfMissing(orientation, field, value, source)
  if orientation[field] or not coords.isCardinal(value) then
    return
  end

  orientation[field] = value
  orientation.sources[field] = source
end

local function inferAxes(report)
  local orientation = report.orientation

  if report.router and SIDE_AXIS[report.router.name] then
    local routerVector = SIDE_AXIS[report.router.name]
    local computerToRouter = routerVector

    if report.router.name == "top" then
      setAxisIfMissing(orientation, "upVector", computerToRouter, "router on top side")
    elseif report.router.name == "bottom" then
      setAxisIfMissing(orientation, "upVector", coords.neg(computerToRouter), "router on bottom side")
    end
  end

  for side, hint in pairs(orientation.sideHints or {}) do
    if not hint.ambiguous and hint.vector then
      if side == "front" then
        setAxisIfMissing(orientation, "frontVector", hint.vector, "direct front peripheral")
      elseif side == "back" then
        setAxisIfMissing(orientation, "frontVector", coords.neg(hint.vector), "direct back peripheral")
      elseif side == "left" then
        setAxisIfMissing(orientation, "leftVector", hint.vector, "direct left peripheral")
      elseif side == "right" then
        setAxisIfMissing(orientation, "leftVector", coords.neg(hint.vector), "direct right peripheral")
      elseif side == "top" then
        setAxisIfMissing(orientation, "upVector", hint.vector, "direct top peripheral")
      elseif side == "bottom" then
        setAxisIfMissing(orientation, "upVector", coords.neg(hint.vector), "direct bottom peripheral")
      end
    end
  end

  if orientation.upVector and orientation.frontVector and not orientation.leftVector then
    setAxisIfMissing(orientation, "leftVector", coords.cross(orientation.upVector, orientation.frontVector), "cross(up, front)")
  end

  if orientation.leftVector and orientation.upVector and not orientation.frontVector then
    setAxisIfMissing(orientation, "frontVector", coords.cross(orientation.leftVector, orientation.upVector), "cross(left, up)")
  end

  if orientation.frontVector and orientation.leftVector and not orientation.upVector then
    setAxisIfMissing(orientation, "upVector", coords.cross(orientation.frontVector, orientation.leftVector), "cross(front, left)")
  end
end

local function roleCandidates(report, filter)
  local results = {}

  for _, entry in ipairs(report.peripherals or {}) do
    if filter(entry) then
      table.insert(results, entry)
    end
  end

  return results
end

local function averageCoord(entries)
  local total = { x = 0, y = 0, z = 0 }

  for _, entry in ipairs(entries) do
    total.x = total.x + entry.coord.x
    total.y = total.y + entry.coord.y
    total.z = total.z + entry.coord.z
  end

  return {
    x = total.x / #entries,
    y = total.y / #entries,
    z = total.z / #entries,
  }
end

local function assignRoles(entries, frontVector, leftVector)
  local roles = {}

  if #entries == 0 or not frontVector or not leftVector then
    return roles
  end

  local center = averageCoord(entries)

  for _, entry in ipairs(entries) do
    local relative = coords.sub(entry.coord, center)
    local frontScore = coords.dot(frontVector, relative)
    local leftScore = coords.dot(leftVector, relative)
    local frontRear = frontScore >= 0 and "front" or "rear"
    local leftRight = leftScore >= 0 and "left" or "right"
    local role = frontRear .. "_" .. leftRight

    roles[role] = {
      coord = copyCoord(entry.coord),
      frontScore = frontScore,
      leftScore = leftScore,
      methodCount = entry.methodCount,
      categories = copyList(entry.categories),
    }
  end

  return roles
end

local function inferRoles(report)
  local orientation = report.orientation

  if not orientation.frontVector or not orientation.leftVector then
    orientation.roleStatus = "missing front/left vectors"
    return
  end

  local rotors = roleCandidates(report, function(entry)
    return hasCategory(entry, "rotorBearing")
  end)
  local scalarControls = roleCandidates(report, function(entry)
    return hasCategory(entry, "scalarActuator") and not hasCategory(entry, "rotorBearing")
  end)

  orientation.roles = {
    rotorBearing = assignRoles(rotors, orientation.frontVector, orientation.leftVector),
    scalarActuator = assignRoles(scalarControls, orientation.frontVector, orientation.leftVector),
  }
  orientation.roleCounts = {
    rotorBearing = #rotors,
    scalarActuator = #scalarControls,
  }
end

local function inferOrientation(report)
  report.orientation = {
    computerCoord = nil,
    sideHints = {},
    sources = {},
    roles = {},
    roleCounts = {},
  }

  local computerCoord, computerCoordError = directComputerCoord(report.router and report.router.name)
  report.orientation.computerCoord = computerCoord
  report.orientation.computerCoordError = computerCoordError

  report.orientation.sideHints = inferDirectSideHints(report)
  inferAxes(report)
  inferRoles(report)
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

  inferOrientation(report)

  for _, entry in ipairs(report.peripherals) do
    entry.methodKey = nil
  end

  return report
end

return scanner
