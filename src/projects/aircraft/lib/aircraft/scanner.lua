local classify = require("lib.aircraft.classify")
local coords = require("lib.aircraft.coords")
local kineticScada = require("lib.aircraft.kinetic_scada")

local scanner = {}
local DEFAULT_SCAN_PARALLELISM = 32

local SIDE_NAMES = {
  front = true,
  back = true,
  left = true,
  right = true,
  top = true,
  bottom = true,
}

local SIDE_AXIS = {
  front = { x = 0, y = 0, z = -1 },
  back = { x = 0, y = 0, z = 1 },
  left = { x = 1, y = 0, z = 0 },
  right = { x = -1, y = 0, z = 0 },
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

local function copyVector(vector)
  if not vector then
    return nil
  end

  return {
    x = vector.x,
    y = vector.y,
    z = vector.z,
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

local KINETIC_FIELD_BY_METHOD = {
  getSelfId = "selfId",
  getSourceId = "sourceId",
  getSubnetworkAnchorId = "subnetworkAnchorId",
  getNetworkId = "networkId",
  getKind = "kind",
  getSpeed = "speed",
  hasSource = "hasSource",
  isOverstressed = "isOverstressed",
  getStressImpact = "stressImpact",
  getStressContribution = "stressContribution",
}

local function toSet(values)
  local set = {}

  for _, value in ipairs(values or {}) do
    set[value] = true
  end

  return set
end

local function safeSingleGetter(object, method)
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

  return {
    ok = true,
    value = sanitize(values[1]),
  }
end

local function readKineticScada(object, methods)
  local methodSet = toSet(methods)
  local found = false
  local result = {
    readErrors = {},
    nilFields = {},
  }

  for _, method in ipairs(classify.KINETIC_SCADA_METHODS or {}) do
    if methodSet[method] then
      found = true
      local field = KINETIC_FIELD_BY_METHOD[method]
      local read = safeSingleGetter(object, method)

      if read.ok then
        result[field] = read.value
        if read.value == nil then
          result.nilFields[field] = true
        end
      else
        result.readErrors[field] = read.error
      end
    end
  end

  if not found then
    return nil
  end

  if not next(result.readErrors) then
    result.readErrors = nil
  end
  if not next(result.nilFields) then
    result.nilFields = nil
  end

  return result
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
    kineticScada = readKineticScada(object, methods),
    samples = sampleGetters(object, methods, config.scan.sampleLimit),
  }
end

local function scanParallelism(config)
  local requested = tonumber(config and config.scan and config.scan.parallelism) or DEFAULT_SCAN_PARALLELISM
  requested = math.floor(requested)

  if requested < 1 then
    return 1
  end

  return requested
end

local function scanCoordinate(router, report, x, y, z, config, errorLimit)
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
end

local function scanCoordinateList(bounds)
  local list = {}

  coords.iterate(bounds, function(x, y, z)
    table.insert(list, {
      x = x,
      y = y,
      z = z,
    })
  end)

  return list
end

local function runCoordinateScan(router, report, coordinateList, config, errorLimit, workerCount)
  local nextIndex = 1

  local function worker()
    while true do
      local index = nextIndex
      nextIndex = nextIndex + 1
      local coord = coordinateList[index]

      if not coord then
        return
      end

      scanCoordinate(router, report, coord.x, coord.y, coord.z, config, errorLimit)
    end
  end

  if workerCount <= 1 or type(parallel) ~= "table" or type(parallel.waitForAll) ~= "function" then
    worker()
    return
  end

  local tasks = {}
  local count = math.min(workerCount, #coordinateList)

  for _ = 1, count do
    table.insert(tasks, worker)
  end

  if #tasks > 0 then
    parallel.waitForAll(unpack(tasks))
  end
end

local function directComputerCoord(routerName)
  local sideAxis = SIDE_AXIS[routerName]
  if not sideAxis then
    return nil, "router is not on a direct computer side, so computer origin needs another side hint"
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

  orientation[field] = copyVector(value)
  orientation.sources[field] = source
end

local function setAxisOverride(orientation, field, value, source)
  local axis = coords.parseAxis(value)
  if not axis then
    return false
  end

  orientation[field] = axis
  orientation.sources[field] = source
  return true
end

local function applyAxisOverrides(report, config)
  local orientation = report.orientation

  if setAxisOverride(orientation, "frontVector", config.frontAxis, "config.frontAxis") then
    orientation.configuredFrontAxis = config.frontAxis
  end

  if setAxisOverride(orientation, "leftVector", config.leftAxis, "config.leftAxis") then
    orientation.configuredLeftAxis = config.leftAxis
  end
end

local function inferAxes(report, config)
  local orientation = report.orientation

  applyAxisOverrides(report, config)

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

local function distanceSquared(left, right)
  local dx = left.x - right.x
  local dy = left.y - right.y
  local dz = left.z - right.z

  return dx * dx + dy * dy + dz * dz
end

local function hasMethod(entry, name)
  for _, method in ipairs(entry.methods or {}) do
    if method == name then
      return true
    end
  end

  return false
end

local function displayKind(entry)
  if hasMethod(entry, "setText") then
    return "text"
  elseif hasMethod(entry, "write") then
    return "terminal"
  elseif hasMethod(entry, "setSignal") then
    return "signal"
  end

  return "unknown"
end

local function displayPriority(entry)
  local kind = displayKind(entry)

  if kind == "text" then
    return 1
  elseif kind == "terminal" then
    return 2
  elseif kind == "signal" then
    return 3
  end

  return 4
end

local function sampleValue(entry, method)
  local sample = entry
    and entry.samples
    and entry.samples[method]

  if type(sample) == "table" and sample.ok then
    return sample.value
  end

  return nil
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
      thrustHandedness = sampleValue(entry, "getThrustHandedness"),
    }
  end

  return roles
end

local function assignNearestDisplays(displayEntries, targetRoles)
  local roles = {}
  local used = {}

  if #displayEntries == 0 or not targetRoles then
    return roles
  end

  for _, role in ipairs({ "front_left", "front_right", "rear_left", "rear_right" }) do
    local target = targetRoles[role]
    local best = nil
    local bestPriority = nil
    local bestDistance = nil

    if target and target.coord then
      for _, display in ipairs(displayEntries) do
        local key = coords.key(display.coord.x, display.coord.y, display.coord.z)

        if not used[key] then
          local distance = distanceSquared(display.coord, target.coord)
          local priority = displayPriority(display)

          if not best
              or priority < bestPriority
              or (priority == bestPriority and distance < bestDistance) then
            best = display
            bestPriority = priority
            bestDistance = distance
          end
        end
      end
    end

    if best then
      local key = coords.key(best.coord.x, best.coord.y, best.coord.z)
      used[key] = true
      roles[role] = {
        coord = copyCoord(best.coord),
        targetCoord = copyCoord(target.coord),
        targetRole = role,
        distanceSquared = bestDistance,
        displayKind = displayKind(best),
        methodCount = best.methodCount,
        categories = copyList(best.categories),
      }
    end
  end

  return roles
end

local STATUS_STRIP_CELLS = {
  { key = "throttle", offset = 0 },
  { key = "hold", offset = 1 },
  { key = "moveTarget", offset = 2 },
}

local function statusStripReservation(config)
  local strip = config
    and config.display
    and config.display.statusStrip

  if type(strip) ~= "table" or strip.enabled ~= true then
    return nil
  end

  local anchor = {
    x = tonumber(strip.x),
    y = tonumber(strip.y),
    z = tonumber(strip.z),
  }
  local axis = coords.parseAxis(strip.axis or "+X")
  local result = {
    enabled = true,
    anchor = copyCoord(anchor),
    axis = axis and coords.axisLabel(axis) or tostring(strip.axis),
    cells = {},
    keys = {},
  }

  if type(anchor.x) ~= "number" or type(anchor.y) ~= "number" or type(anchor.z) ~= "number" then
    result.status = "invalid anchor"
    return result
  elseif not axis then
    result.status = "invalid axis"
    return result
  end

  for _, cell in ipairs(STATUS_STRIP_CELLS) do
    local coord = {
      x = anchor.x + axis.x * cell.offset,
      y = anchor.y + axis.y * cell.offset,
      z = anchor.z + axis.z * cell.offset,
    }
    coord.key = coords.key(coord.x, coord.y, coord.z)
    result.cells[cell.key] = {
      coord = copyCoord(coord),
      offset = cell.offset,
    }
    result.keys[coord.key] = true
  end

  result.status = "reserved"
  return result
end

local function statusStripReservationSummary(reservation)
  if not reservation then
    return nil
  end

  return {
    enabled = reservation.enabled,
    status = reservation.status,
    anchor = copyCoord(reservation.anchor),
    axis = reservation.axis,
    cells = {
      throttle = reservation.cells and reservation.cells.throttle and copyCoord(reservation.cells.throttle.coord) or nil,
      hold = reservation.cells and reservation.cells.hold and copyCoord(reservation.cells.hold.coord) or nil,
      moveTarget = reservation.cells and reservation.cells.moveTarget and copyCoord(reservation.cells.moveTarget.coord) or nil,
    },
  }
end

local function filterReservedDisplays(entries, reservation)
  if not reservation or not reservation.keys then
    return entries
  end

  local result = {}
  for _, entry in ipairs(entries or {}) do
    local key = entry.coord and coords.key(entry.coord.x, entry.coord.y, entry.coord.z)
    if not key or reservation.keys[key] ~= true then
      table.insert(result, entry)
    end
  end

  return result
end

local function assignFirstSensor(entries)
  local sortedEntries = {}

  for _, entry in ipairs(entries or {}) do
    table.insert(sortedEntries, entry)
  end

  table.sort(sortedEntries, function(left, right)
    local leftDistance = math.abs(tonumber(left.coord and left.coord.x) or 0)
      + math.abs(tonumber(left.coord and left.coord.y) or 0)
      + math.abs(tonumber(left.coord and left.coord.z) or 0)
    local rightDistance = math.abs(tonumber(right.coord and right.coord.x) or 0)
      + math.abs(tonumber(right.coord and right.coord.y) or 0)
      + math.abs(tonumber(right.coord and right.coord.z) or 0)

    if leftDistance ~= rightDistance then
      return leftDistance < rightDistance
    end

    return coords.key(left.coord.x, left.coord.y, left.coord.z)
      < coords.key(right.coord.x, right.coord.y, right.coord.z)
  end)

  local first = sortedEntries[1]
  if not first then
    return nil
  end

  return {
    coord = copyCoord(first.coord),
    methodCount = first.methodCount,
    categories = copyList(first.categories),
  }
end

local function sortedSensorEntries(entries)
  local sortedEntries = {}

  for _, entry in ipairs(entries or {}) do
    table.insert(sortedEntries, entry)
  end

  table.sort(sortedEntries, function(left, right)
    local leftDistance = math.abs(tonumber(left.coord and left.coord.x) or 0)
      + math.abs(tonumber(left.coord and left.coord.y) or 0)
      + math.abs(tonumber(left.coord and left.coord.z) or 0)
    local rightDistance = math.abs(tonumber(right.coord and right.coord.x) or 0)
      + math.abs(tonumber(right.coord and right.coord.y) or 0)
      + math.abs(tonumber(right.coord and right.coord.z) or 0)

    if leftDistance ~= rightDistance then
      return leftDistance < rightDistance
    end

    return coords.key(left.coord.x, left.coord.y, left.coord.z)
      < coords.key(right.coord.x, right.coord.y, right.coord.z)
  end)

  return sortedEntries
end

local function velocityAxis(entry)
  local value = sampleValue(entry, "getAxis")
  if type(value) == "string" then
    local axis = string.lower(value)
    if axis == "x" or axis == "y" or axis == "z" then
      return axis
    end
  end

  if hasMethod(entry, "getVelocityX") then
    return "x"
  elseif hasMethod(entry, "getVelocityY") then
    return "y"
  elseif hasMethod(entry, "getVelocityZ") then
    return "z"
  end

  return nil
end

local function sensorSummary(entry, extra)
  if not entry then
    return nil
  end

  local result = {
    coord = copyCoord(entry.coord),
    methodCount = entry.methodCount,
    categories = copyList(entry.categories),
  }

  for key, value in pairs(extra or {}) do
    result[key] = value
  end

  return result
end

local function axisFromVector(vector)
  if not coords.isCardinal(vector) then
    return nil
  elseif vector.x ~= 0 then
    return "x", vector.x
  elseif vector.y ~= 0 then
    return "y", vector.y
  elseif vector.z ~= 0 then
    return "z", vector.z
  end

  return nil
end

local function assignVelocitySensors(entries, frontVector, leftVector)
  local byAxis = {}
  local grouped = {
    x = {},
    y = {},
    z = {},
  }

  for _, entry in ipairs(entries or {}) do
    local axis = velocityAxis(entry)
    if axis and grouped[axis] then
      table.insert(grouped[axis], entry)
    end
  end

  for axis, axisEntries in pairs(grouped) do
    local first = sortedSensorEntries(axisEntries)[1]
    if first then
      byAxis[axis] = sensorSummary(first, {
        axis = axis,
        velocity = sampleValue(first, "getVelocity"),
      })
    end
  end

  local frontAxis, frontSign = axisFromVector(frontVector)
  local leftAxis, leftSign = axisFromVector(leftVector)
  local result = {
    byAxis = byAxis,
    front = frontAxis and byAxis[frontAxis] and sensorSummary(byAxis[frontAxis], {
      axis = frontAxis,
      sign = frontSign,
      role = "front",
    }) or nil,
    left = leftAxis and byAxis[leftAxis] and sensorSummary(byAxis[leftAxis], {
      axis = leftAxis,
      sign = leftSign,
      role = "left",
    }) or nil,
    required = {
      front = frontAxis and {
        axis = frontAxis,
        sign = frontSign,
        vector = copyVector(frontVector),
      } or nil,
      left = leftAxis and {
        axis = leftAxis,
        sign = leftSign,
        vector = copyVector(leftVector),
      } or nil,
    },
  }

  if result.front and result.left then
    result.status = "ready"
  elseif not frontAxis or not leftAxis then
    result.status = "missing aircraft axes"
  else
    result.status = "missing required velocity axes"
  end

  return result
end

local function hasAnyRole(roles)
  for _, role in ipairs({ "front_left", "front_right", "rear_left", "rear_right" }) do
    if roles and roles[role] then
      return true
    end
  end

  return false
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
    return hasCategory(entry, "scalarActuator")
      and not hasCategory(entry, "speedActuator")
      and not hasCategory(entry, "rotorBearing")
      and not hasCategory(entry, "displaySink")
  end)
  local speedControls = roleCandidates(report, function(entry)
    return hasCategory(entry, "speedActuator")
      and not hasCategory(entry, "rotorBearing")
      and not hasCategory(entry, "displaySink")
  end)
  local allDisplays = roleCandidates(report, function(entry)
    return hasCategory(entry, "displaySink")
  end)
  local statusStrip = statusStripReservation(report.config)
  local displays = filterReservedDisplays(allDisplays, statusStrip)
  local navigationSensors = roleCandidates(report, function(entry)
    return hasCategory(entry, "navigationSensor")
  end)
  local altitudeSensors = roleCandidates(report, function(entry)
    return hasCategory(entry, "altitudeSensor")
  end)
  local velocitySensors = roleCandidates(report, function(entry)
    return hasCategory(entry, "velocitySensor")
  end)
  local rotorRoles = assignRoles(rotors, orientation.frontVector, orientation.leftVector)
  local scalarRoles = assignRoles(scalarControls, orientation.frontVector, orientation.leftVector)
  local speedRoles = assignRoles(speedControls, orientation.frontVector, orientation.leftVector)

  orientation.roles = {
    rotorBearing = rotorRoles,
    scalarActuator = scalarRoles,
    speedActuator = speedRoles,
    displaySink = assignNearestDisplays(
      displays,
      hasAnyRole(rotorRoles) and rotorRoles or (hasAnyRole(scalarRoles) and scalarRoles or speedRoles)
    ),
  }
  orientation.reservedDisplays = {
    statusStrip = statusStripReservationSummary(statusStrip),
  }
  orientation.sensors = {
    navigationSensor = assignFirstSensor(navigationSensors),
    altitudeSensor = assignFirstSensor(altitudeSensors),
    velocitySensor = assignVelocitySensors(velocitySensors, orientation.frontVector, orientation.leftVector),
  }
  orientation.roleCounts = {
    rotorBearing = #rotors,
    scalarActuator = #scalarControls,
    speedActuator = #speedControls,
    displaySink = #allDisplays,
    displaySinkAvailable = #displays,
    displaySinkReserved = #allDisplays - #displays,
    navigationSensor = #navigationSensors,
    altitudeSensor = #altitudeSensors,
    velocitySensor = #velocitySensors,
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
  inferAxes(report, report.config or {})
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
      scanParallelism = scanParallelism(config),
      display = {
        absoluteRotorValues = config.display and config.display.absoluteRotorValues,
        statusStrip = sanitize(config.display and config.display.statusStrip),
      },
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
      parallelism = scanParallelism(config),
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

  local coordinateList = scanCoordinateList(bounds)
  report.summary.coordinateCount = #coordinateList
  runCoordinateScan(router, report, coordinateList, config, errorLimit, report.summary.parallelism)

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
  report.kineticScada = kineticScada.build(report)

  for _, entry in ipairs(report.peripherals) do
    entry.methodKey = nil
  end

  return report
end

return scanner
