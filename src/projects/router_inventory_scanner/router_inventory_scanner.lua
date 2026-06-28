local reporter = require("lib.reporter")

local DEFAULT_RADIUS = 8
local DEFAULT_Y_RADIUS = 1
local DEFAULT_SAMPLE_LIMIT = 0
local MAX_RADIUS = 16
local DEFAULT_MAP_REPORT_PATH = "router_base_map_report.txt"
local DEFAULT_STACK_REPORT_PATH = "router_stack_report.txt"

local args = { ... }
local unpackArgs = table.unpack or unpack

local function usage()
  print("router_inventory_scanner [map] [options]")
  print("router_inventory_scanner map --radius 8 --height 3")
  print("router_inventory_scanner map --x-radius 8 --y-radius 1 --z-radius 8")
  print("router_inventory_scanner map --cube-radius 4")
  print("router_inventory_scanner map --out base_map.txt")
  print("router_inventory_scanner stack-preview --to <x> <y> <z> [--out path]")
  print("router_inventory_scanner stack --to <x> <y> <z> [--fluids] [--out path]")
  print("router_inventory_scanner stack --to <x> <y> <z> --from-report base_map.txt")
  print("")
  print("Default map is 17x3x17: x/z radius 8, y radius 1.")
  print("Reports write a local file and send webhook unless --no-webhook is set.")
  print("Default files: " .. DEFAULT_MAP_REPORT_PATH .. ", " .. DEFAULT_STACK_REPORT_PATH .. ".")
end

local function contains(values, target)
  for _, value in ipairs(values or {}) do
    if value == target then
      return true
    end
  end

  return false
end

local function parsePositiveInteger(value, label)
  local number = tonumber(value)
  if not number or number ~= math.floor(number) or number < 0 then
    error(label .. " must be a positive integer", 0)
  end

  return number
end

local function parseInteger(value, label)
  local number = tonumber(value)
  if not number or number ~= math.floor(number) then
    error(label .. " must be an integer", 0)
  end

  return number
end

local function setHorizontalRadius(config, value)
  config.radius = value
  config.xRadius = value
  config.zRadius = value
end

local function setCubeRadius(config, value)
  config.radius = value
  config.xRadius = value
  config.yRadius = value
  config.zRadius = value
end

local function radiusFromHeight(value)
  local height = parsePositiveInteger(value, "height")
  if height < 1 or height % 2 == 0 then
    error("height must be an odd positive integer", 0)
  end

  return math.floor(height / 2)
end

local function setDestination(config, x, y, z)
  config.destination = {
    x = parseInteger(x, "destination x"),
    y = parseInteger(y, "destination y"),
    z = parseInteger(z, "destination z"),
  }
end

local function isStackCommand(command)
  return command == "stack" or command == "stack-preview"
end

local function parseArgs(rawArgs)
  local config = {
    command = "map",
    radius = DEFAULT_RADIUS,
    xRadius = DEFAULT_RADIUS,
    yRadius = DEFAULT_Y_RADIUS,
    zRadius = DEFAULT_RADIUS,
    sampleLimit = DEFAULT_SAMPLE_LIMIT,
    includeOrigin = false,
    reportPath = nil,
    outputPath = nil,
    dryRun = false,
    includeItems = true,
    includeFluids = false,
    noWebhook = false,
  }

  local index = 1
  if rawArgs[index] == "map" or rawArgs[index] == "stack" or rawArgs[index] == "stack-preview" then
    config.command = rawArgs[index]
    config.dryRun = rawArgs[index] == "stack-preview"
    index = index + 1
  elseif rawArgs[index] == "help" or rawArgs[index] == "--help" or rawArgs[index] == "-h" then
    config.command = "help"
    return config
  elseif tonumber(rawArgs[index]) then
    setHorizontalRadius(config, parsePositiveInteger(rawArgs[index], "radius"))
    index = index + 1
  elseif rawArgs[index] ~= nil then
    error("Unknown command: " .. tostring(rawArgs[index]), 0)
  end

  while index <= #rawArgs do
    local arg = rawArgs[index]

    if arg == "--radius" or arg == "-r" then
      setHorizontalRadius(config, parsePositiveInteger(rawArgs[index + 1], "radius"))
      index = index + 2
    elseif arg == "--cube-radius" or arg == "--cr" then
      setCubeRadius(config, parsePositiveInteger(rawArgs[index + 1], "cube radius"))
      index = index + 2
    elseif arg == "--x-radius" or arg == "--xr" then
      config.xRadius = parsePositiveInteger(rawArgs[index + 1], "x radius")
      index = index + 2
    elseif arg == "--y-radius" or arg == "--yr" then
      config.yRadius = parsePositiveInteger(rawArgs[index + 1], "y radius")
      index = index + 2
    elseif arg == "--height" then
      config.yRadius = radiusFromHeight(rawArgs[index + 1])
      index = index + 2
    elseif arg == "--z-radius" or arg == "--zr" then
      config.zRadius = parsePositiveInteger(rawArgs[index + 1], "z radius")
      index = index + 2
    elseif arg == "--sample" or arg == "-s" then
      config.sampleLimit = parsePositiveInteger(rawArgs[index + 1], "sample")
      index = index + 2
    elseif arg == "--include-origin" then
      config.includeOrigin = true
      index = index + 1
    elseif arg == "--to" then
      setDestination(config, rawArgs[index + 1], rawArgs[index + 2], rawArgs[index + 3])
      index = index + 4
    elseif arg == "--from-report" then
      config.reportPath = rawArgs[index + 1]
      if not config.reportPath or config.reportPath == "" then
        error("from-report path is required", 0)
      end
      index = index + 2
    elseif arg == "--out" or arg == "--output" or arg == "-o" then
      config.outputPath = rawArgs[index + 1]
      if not config.outputPath or config.outputPath == "" then
        error("out path is required", 0)
      end
      index = index + 2
    elseif arg == "--dry-run" then
      config.dryRun = true
      index = index + 1
    elseif arg == "--items" then
      config.includeItems = true
      index = index + 1
    elseif arg == "--no-items" then
      config.includeItems = false
      index = index + 1
    elseif arg == "--fluids" then
      config.includeFluids = true
      index = index + 1
    elseif arg == "--no-webhook" then
      config.noWebhook = true
      index = index + 1
    elseif isStackCommand(config.command) and tonumber(arg) and tonumber(rawArgs[index + 1]) and tonumber(rawArgs[index + 2]) then
      setDestination(config, arg, rawArgs[index + 1], rawArgs[index + 2])
      index = index + 3
    elseif tonumber(arg) and index == 2 then
      setHorizontalRadius(config, parsePositiveInteger(arg, "radius"))
      index = index + 1
    else
      error("Unknown option: " .. tostring(arg), 0)
    end
  end

  if config.xRadius > MAX_RADIUS or config.yRadius > MAX_RADIUS or config.zRadius > MAX_RADIUS then
    error("axis radii must be " .. MAX_RADIUS .. " or less", 0)
  end

  config.width = config.xRadius * 2 + 1
  config.height = config.yRadius * 2 + 1
  config.depth = config.zRadius * 2 + 1

  if isStackCommand(config.command) then
    if not config.destination then
      error("stack requires --to <x> <y> <z>", 0)
    end

    if not config.includeItems and not config.includeFluids then
      error("stack needs --items and/or --fluids", 0)
    end
  end

  return config
end

local function pack(...)
  return { ... }
end

local function sortedMethodNames(object)
  local methods = {}

  for name, value in pairs(object or {}) do
    if type(name) == "string" and type(value) == "function" then
      table.insert(methods, name)
    end
  end

  table.sort(methods)
  return methods
end

local function methodFlags(object, methods)
  return {
    list = type(object.list) == "function" or contains(methods, "list"),
    size = type(object.size) == "function" or contains(methods, "size"),
    getItemDetail = type(object.getItemDetail) == "function" or contains(methods, "getItemDetail"),
    getItemLimit = type(object.getItemLimit) == "function" or contains(methods, "getItemLimit"),
    pushItems = type(object.pushItems) == "function" or contains(methods, "pushItems"),
    pullItems = type(object.pullItems) == "function" or contains(methods, "pullItems"),
  }
end

local function isInventory(flags)
  return flags.size and flags.list
end

local function safeObjectCall(object, methodName, ...)
  if type(object[methodName]) ~= "function" then
    return false, "missing method " .. methodName
  end

  local results = pack(pcall(object[methodName], ...))
  local ok = table.remove(results, 1)
  if not ok then
    return false, tostring(results[1])
  end

  return true, results
end

local function compactDetail(detail)
  if type(detail) ~= "table" then
    return detail
  end

  return {
    name = detail.name,
    displayName = detail.displayName,
    count = detail.count,
    nbt = detail.nbt,
  }
end

local function compactItem(slot, item)
  if type(item) ~= "table" then
    return {
      slot = slot,
      raw = tostring(item),
    }
  end

  return {
    slot = slot,
    name = item.name,
    count = tonumber(item.count) or 0,
    nbt = item.nbt,
  }
end

local function sortedSlots(items)
  local slots = {}

  for slot in pairs(items or {}) do
    table.insert(slots, tonumber(slot) or slot)
  end

  table.sort(slots, function(left, right)
    local leftNumber = tonumber(left)
    local rightNumber = tonumber(right)

    if leftNumber and rightNumber then
      return leftNumber < rightNumber
    end

    return tostring(left) < tostring(right)
  end)

  return slots
end

local function itemTotalsList(itemTotals)
  local totals = {}

  for name, count in pairs(itemTotals or {}) do
    table.insert(totals, {
      name = name,
      count = count,
    })
  end

  table.sort(totals, function(left, right)
    if left.count == right.count then
      return left.name < right.name
    end

    return left.count > right.count
  end)

  return totals
end

local function sampleItems(object, items, limit, flags)
  local sample = {}
  local itemTotals = {}
  local usedSlots = 0
  local totalItems = 0

  for _, slot in ipairs(sortedSlots(items)) do
    local item = compactItem(slot, items[slot])
    usedSlots = usedSlots + 1
    totalItems = totalItems + item.count

    if item.name then
      itemTotals[item.name] = (itemTotals[item.name] or 0) + item.count
    end

    if #sample < limit then
      if flags.getItemDetail then
        local ok, detail = safeObjectCall(object, "getItemDetail", slot)
        if ok then
          item.detail = compactDetail(detail[1])
        end
      end

      table.insert(sample, item)
    end
  end

  return usedSlots, totalItems, itemTotalsList(itemTotals), sample
end

local function inspectInventory(object, flags, sampleLimit)
  local entry = {
    inventory = true,
    size = nil,
    usedSlots = 0,
    totalItems = 0,
    itemTotals = {},
    sample = {},
    errors = {},
  }

  local sizeOk, sizeResult = safeObjectCall(object, "size")
  if sizeOk then
    entry.size = tonumber(sizeResult[1]) or sizeResult[1]
  else
    table.insert(entry.errors, "size: " .. tostring(sizeResult))
  end

  local listOk, listResult = safeObjectCall(object, "list")
  if listOk and type(listResult[1]) == "table" then
    entry.usedSlots, entry.totalItems, entry.itemTotals, entry.sample =
      sampleItems(object, listResult[1], sampleLimit, flags)
  elseif listOk then
    table.insert(entry.errors, "list: expected table")
  else
    table.insert(entry.errors, "list: " .. tostring(listResult))
  end

  return entry
end

local function readOptionalNames(object, methods)
  local names = {}
  local candidates = { "getLabel", "getName", "getID", "getId", "getTitle" }

  for _, methodName in ipairs(candidates) do
    if contains(methods, methodName) and type(object[methodName]) == "function" then
      local ok, results = safeObjectCall(object, methodName)
      if ok and results[1] ~= nil then
        names[methodName] = tostring(results[1])
      end
    end
  end

  return names
end

local function classifyEntry(entry)
  if entry.inventory then
    return "inventory"
  end

  if contains(entry.methods, "write") and contains(entry.methods, "setCursorPos") then
    return "terminal"
  end

  if contains(entry.methods, "getNamesRemote") or contains(entry.methods, "isWireless") then
    return "modem"
  end

  if contains(entry.methods, "getInput") and contains(entry.methods, "setOutput") then
    return "redstone"
  end

  if contains(entry.methods, "getEnergy") or contains(entry.methods, "getEnergyStored") then
    return "energy"
  end

  if contains(entry.methods, "tanks") or contains(entry.methods, "pushFluid") or contains(entry.methods, "pullFluid") then
    return "fluid"
  end

  return "wrappable"
end

local function firstName(names)
  if type(names) ~= "table" then
    return nil
  end

  return names.getLabel or names.getName or names.getTitle or names.getID or names.getId
end

local function displayName(entry)
  local explicitName = firstName(entry.names)
  if explicitName and explicitName ~= "" then
    return explicitName
  end

  if entry.inventory then
    if entry.itemTotals and entry.itemTotals[1] then
      return "inventory: " .. tostring(entry.itemTotals[1].name)
    end

    return "empty inventory"
  end

  if entry.kind == "wrappable" then
    return "wrappable: " .. tostring(entry.methodCount or #entry.methods) .. " methods"
  end

  return entry.kind
end

local function typeText(types)
  if type(types) ~= "table" or #types == 0 then
    return ""
  end

  return table.concat(types, ", ")
end

local cachedRouter = nil
local cachedRouterName = nil

local function findRouter()
  if cachedRouter then
    return cachedRouter, cachedRouterName
  end

  for _, peripheralName in ipairs(peripheral.getNames()) do
    local ok, wrapped = pcall(peripheral.wrap, peripheralName)
    if ok and wrapped and type(wrapped.wrap) == "function" then
      local typeResults = pack(pcall(peripheral.getType, peripheralName))
      local typeOk = table.remove(typeResults, 1)
      local types = typeOk and typeResults or {}
      if string.find(string.lower(typeText(types)), "peripheral_router", 1, true) then
        cachedRouter = wrapped
        cachedRouterName = peripheralName
        return wrapped, peripheralName
      end
    end
  end

  local router = peripheral.find("peripheral_router")
  if router and type(router.wrap) == "function" then
    cachedRouter = router
    cachedRouterName = "(found by type)"
    return router, cachedRouterName
  end

  return nil, nil
end

local function offsetLabel(x, y, z)
  return "router(" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. ")"
end

local function isNoPeripheralError(message)
  local lower = string.lower(tostring(message or ""))

  return string.find(lower, "no peripheral", 1, true) ~= nil
    or string.find(lower, "not a peripheral", 1, true) ~= nil
    or string.find(lower, "could not find", 1, true) ~= nil
    or string.find(lower, "cannot find", 1, true) ~= nil
end

local function inspectOffset(router, x, y, z, config)
  local entry = {
    x = x,
    y = y,
    z = z,
    label = offsetLabel(x, y, z),
    ok = false,
    inventory = false,
    methods = {},
    flags = {},
  }

  local ok, object = pcall(router.wrap, x, y, z)
  if not ok then
    if isNoPeripheralError(object) then
      entry.empty = true
      entry.error = "no peripheral"
    else
      entry.error = tostring(object)
    end

    return entry
  end

  if not object then
    entry.empty = true
    entry.error = "no peripheral"
    return entry
  end

  entry.ok = true
  entry.methods = sortedMethodNames(object)
  entry.flags = methodFlags(object, entry.methods)
  entry.methodCount = #entry.methods

  if isInventory(entry.flags) then
    local inventory = inspectInventory(object, entry.flags, config.sampleLimit)
    for key, value in pairs(inventory) do
      entry[key] = value
    end
  end

  entry.names = readOptionalNames(object, entry.methods)
  entry.kind = classifyEntry(entry)
  entry.displayName = displayName(entry)

  return entry
end

local function buildMap(config)
  local router, routerName = findRouter()
  if not router then
    error("No peripheral_router with wrap(x, y, z) found", 0)
  end

  local results = {}
  local inspected = 0
  local wrappable = 0
  local inventories = 0
  local totalSlots = 0
  local totalUsedSlots = 0
  local totalItems = 0
  local errors = 0

  for y = -config.yRadius, config.yRadius do
    for x = -config.xRadius, config.xRadius do
      for z = -config.zRadius, config.zRadius do
        if config.includeOrigin or x ~= 0 or y ~= 0 or z ~= 0 then
          inspected = inspected + 1
          local entry = inspectOffset(router, x, y, z, config)

          if entry.ok then
            wrappable = wrappable + 1
          elseif entry.error ~= "no peripheral" then
            errors = errors + 1
          end

          if entry.inventory then
            inventories = inventories + 1
            totalSlots = totalSlots + (tonumber(entry.size) or 0)
            totalUsedSlots = totalUsedSlots + (tonumber(entry.usedSlots) or 0)
            totalItems = totalItems + (tonumber(entry.totalItems) or 0)
          end

          if entry.ok or (entry.error and entry.error ~= "no peripheral") then
            table.insert(results, entry)
          end
        end
      end
    end
  end

  return {
    kind = "router_base_map",
    command = config.command,
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    router = routerName,
    radius = config.radius,
    xRadius = config.xRadius,
    yRadius = config.yRadius,
    zRadius = config.zRadius,
    width = config.width,
    height = config.height,
    depth = config.depth,
    sampleLimit = config.sampleLimit,
    includeOrigin = config.includeOrigin,
    inspected = inspected,
    wrappable = wrappable,
    inventories = inventories,
    totalSlots = totalSlots,
    totalUsedSlots = totalUsedSlots,
    totalItems = totalItems,
    errors = errors,
    results = results,
  }
end

local function sameCoords(left, right)
  return left
    and right
    and tonumber(left.x) == tonumber(right.x)
    and tonumber(left.y) == tonumber(right.y)
    and tonumber(left.z) == tonumber(right.z)
end

local function coordLabel(coord)
  return offsetLabel(coord.x, coord.y, coord.z)
end

local function readAll(path)
  local handle = fs.open(path, "r")
  if not handle then
    return nil, "Could not open " .. tostring(path)
  end

  local contents = handle.readAll()
  handle.close()
  return contents, nil
end

local function readStoredReport(path)
  path = path or DEFAULT_MAP_REPORT_PATH

  if not fs.exists(path) then
    error("Report not found: " .. tostring(path) .. ". Run router_inventory_scanner map --radius <n> first.", 0)
  end

  local contents, readError = readAll(path)
  if not contents then
    error(readError, 0)
  end

  local report = textutils.unserialize(contents)
  if type(report) ~= "table" and textutils.unserializeJSON then
    report = textutils.unserializeJSON(contents)
  end

  if type(report) ~= "table" then
    error("Could not parse report " .. tostring(path), 0)
  end

  if type(report.results) ~= "table" then
    error("Report has no results: " .. tostring(path), 0)
  end

  return report, path
end

local function wrapRouterCoords(router, coord, role)
  local ok, object = pcall(router.wrap, coord.x, coord.y, coord.z)
  if not ok then
    return nil, role .. " " .. coordLabel(coord) .. " wrap failed: " .. tostring(object)
  end

  if not object then
    return nil, role .. " " .. coordLabel(coord) .. " is not wrappable"
  end

  return {
    object = object,
    label = coordLabel(coord),
    transferName = coord.transferName or coord.side or coord.id,
    x = coord.x,
    y = coord.y,
    z = coord.z,
  }, nil
end

local function hasMethodList(entry, methodName)
  return contains(entry.methods or {}, methodName)
end

local function isReportInventory(entry)
  return entry
    and entry.ok ~= false
    and entry.inventory == true
    and hasMethodList(entry, "list")
    and (hasMethodList(entry, "pushItems") or hasMethodList(entry, "pullItems"))
end

local function isReportFluid(entry)
  return entry
    and entry.ok ~= false
    and (entry.kind == "fluid" or hasMethodList(entry, "tanks"))
    and (hasMethodList(entry, "pushFluid") or hasMethodList(entry, "pullFluid"))
end

local function stackSources(report, destination, includeItems, includeFluids)
  local sources = {}

  for _, entry in ipairs(report.results or {}) do
    if not sameCoords(entry, destination) then
      if includeItems and isReportInventory(entry) then
        table.insert(sources, {
          mode = "items",
          x = tonumber(entry.x),
          y = tonumber(entry.y),
          z = tonumber(entry.z),
          label = entry.label or offsetLabel(entry.x, entry.y, entry.z),
          transferName = entry.transferName or entry.side or entry.id,
          displayName = entry.displayName,
        })
      end

      if includeFluids and isReportFluid(entry) then
        table.insert(sources, {
          mode = "fluids",
          x = tonumber(entry.x),
          y = tonumber(entry.y),
          z = tonumber(entry.z),
          label = entry.label or offsetLabel(entry.x, entry.y, entry.z),
          transferName = entry.transferName or entry.side or entry.id,
          displayName = entry.displayName,
        })
      end
    end
  end

  return sources
end

local function newStackStats()
  return {
    sources = 0,
    itemSources = 0,
    fluidSources = 0,
    itemSnapshots = 0,
    fluidSnapshots = 0,
    itemAttempts = 0,
    fluidAttempts = 0,
    movedItems = 0,
    movedItemSlots = 0,
    movedFluid = 0,
    zeroMoves = 0,
    errors = {},
    moves = {},
  }
end

local function addTransferAttempt(attempts, mode, caller, target, label)
  if caller and caller.object and target ~= nil then
    table.insert(attempts, {
      mode = mode,
      caller = caller,
      target = target,
      label = label,
    })
  end
end

local function itemTransferAttempts(source, destination)
  local attempts = {}

  addTransferAttempt(attempts, "push", source, destination.object, "push to destination object")
  addTransferAttempt(attempts, "pull", destination, source.object, "pull from source object")
  addTransferAttempt(attempts, "push", source, destination.transferName, "push to " .. tostring(destination.transferName))
  addTransferAttempt(attempts, "pull", destination, source.transferName, "pull from " .. tostring(source.transferName))

  return attempts
end

local function callItemTransfer(attempt, slot, limit)
  if attempt.mode == "push" then
    if limit ~= nil then
      return safeObjectCall(attempt.caller.object, "pushItems", attempt.target, slot, limit)
    end

    return safeObjectCall(attempt.caller.object, "pushItems", attempt.target, slot)
  end

  if limit ~= nil then
    return safeObjectCall(attempt.caller.object, "pullItems", attempt.target, slot, limit)
  end

  return safeObjectCall(attempt.caller.object, "pullItems", attempt.target, slot)
end

local function runItemTransferAttempts(attempts, slot, limit)
  local firstZero = nil
  local lastError = nil

  for _, attempt in ipairs(attempts) do
    local methodName = attempt.mode == "push" and "pushItems" or "pullItems"

    if type(attempt.caller.object[methodName]) == "function" then
      local ok, results = callItemTransfer(attempt, slot, limit)
      if ok then
        local moved = tonumber(results[1]) or 0
        if moved > 0 then
          return moved, nil, attempt.label
        end

        firstZero = firstZero or attempt.label
      else
        lastError = attempt.label .. ": " .. tostring(results)
      end
    end
  end

  if firstZero then
    return 0, nil, firstZero
  end

  return nil, lastError or "No item transfer method"
end

local function transferItems(source, destination, slot, limit)
  local attempts = itemTransferAttempts(source, destination)
  local moved, moveError, method = runItemTransferAttempts(attempts, slot, nil)

  if moveError and limit ~= nil then
    local limitedMoved, limitedError, limitedMethod = runItemTransferAttempts(attempts, slot, limit)
    if limitedError then
      return nil, tostring(moveError) .. "; fallback: " .. tostring(limitedError)
    end

    return limitedMoved, nil, limitedMethod and (limitedMethod .. " limited") or nil
  end

  return moved, moveError, method
end

local function moveItemsFromSource(source, destination, config, stats)
  local ok, results = safeObjectCall(source.object, "list")
  if not ok then
    table.insert(stats.errors, source.label .. " list failed: " .. tostring(results))
    return
  end

  local items = results[1] or {}
  stats.itemSnapshots = stats.itemSnapshots + 1

  for slot, item in pairs(items) do
    local count = item and tonumber(item.count) or 0

    if count > 0 then
      stats.itemAttempts = stats.itemAttempts + 1

      if config.dryRun then
        stats.movedItems = stats.movedItems + count
        stats.movedItemSlots = stats.movedItemSlots + 1
        table.insert(stats.moves, {
          mode = "items",
          source = source.label,
          slot = slot,
          item = item.name,
          count = count,
          dryRun = true,
        })
      else
        local moved, moveError, method = transferItems(source, destination, slot, count)
        if moveError then
          table.insert(stats.errors, source.label .. " slot " .. tostring(slot) .. ": " .. tostring(moveError))
        elseif moved and moved > 0 then
          stats.movedItems = stats.movedItems + moved
          stats.movedItemSlots = stats.movedItemSlots + 1
          table.insert(stats.moves, {
            mode = "items",
            source = source.label,
            slot = slot,
            item = item.name,
            count = moved,
            method = method,
          })
        else
          stats.zeroMoves = stats.zeroMoves + 1
        end
      end
    end
  end
end

local function fluidName(tank)
  if type(tank) ~= "table" then
    return nil
  end

  if type(tank.name) == "string" then
    return tank.name
  end

  if type(tank.fluidName) == "string" then
    return tank.fluidName
  end

  if type(tank.fluid) == "string" then
    return tank.fluid
  end

  if type(tank.fluid) == "table" and type(tank.fluid.name) == "string" then
    return tank.fluid.name
  end

  return nil
end

local function fluidAmount(tank)
  if type(tank) ~= "table" then
    return 0
  end

  return tonumber(tank.amount or tank.count) or 0
end

local function transferFluid(source, destination, amount, name)
  local attempts = {
    {
      caller = source.object,
      method = "pushFluid",
      args = name and { destination.object, amount, name } or { destination.object, amount },
      label = "push fluid to destination object",
    },
    {
      caller = destination.object,
      method = "pullFluid",
      args = name and { source.object, amount, name } or { source.object, amount },
      label = "pull fluid from source object",
    },
  }

  local firstZero = nil
  local lastError = nil

  for _, attempt in ipairs(attempts) do
    if type(attempt.caller[attempt.method]) == "function" then
      local ok, results = safeObjectCall(attempt.caller, attempt.method, unpackArgs(attempt.args))
      if ok then
        local moved = tonumber(results[1]) or 0
        if moved > 0 then
          return moved, nil, attempt.label
        end

        firstZero = firstZero or attempt.label
      else
        lastError = attempt.label .. ": " .. tostring(results)
      end
    end
  end

  if firstZero then
    return 0, nil, firstZero
  end

  return nil, lastError or "No fluid transfer method"
end

local function moveFluidsFromSource(source, destination, config, stats)
  local ok, results = safeObjectCall(source.object, "tanks")
  if not ok then
    table.insert(stats.errors, source.label .. " tanks failed: " .. tostring(results))
    return
  end

  local tanks = results[1] or {}
  stats.fluidSnapshots = stats.fluidSnapshots + 1

  for _, tank in pairs(tanks) do
    local amount = fluidAmount(tank)

    if amount > 0 then
      stats.fluidAttempts = stats.fluidAttempts + 1

      if config.dryRun then
        stats.movedFluid = stats.movedFluid + amount
        table.insert(stats.moves, {
          mode = "fluids",
          source = source.label,
          fluid = fluidName(tank),
          amount = amount,
          dryRun = true,
        })
      else
        local moved, moveError, method = transferFluid(source, destination, amount, fluidName(tank))
        if moveError then
          table.insert(stats.errors, source.label .. " fluid: " .. tostring(moveError))
        elseif moved and moved > 0 then
          stats.movedFluid = stats.movedFluid + moved
          table.insert(stats.moves, {
            mode = "fluids",
            source = source.label,
            fluid = fluidName(tank),
            amount = moved,
            method = method,
          })
        else
          stats.zeroMoves = stats.zeroMoves + 1
        end
      end
    end
  end
end

local function runStack(config)
  local storedReport, reportPath = readStoredReport(config.reportPath)
  local router, routerName = findRouter()
  if not router then
    error("No peripheral_router with wrap(x, y, z) found", 0)
  end

  local destination, destinationError = wrapRouterCoords(router, config.destination, "Destination")
  if not destination then
    error(destinationError, 0)
  end

  local sources = stackSources(storedReport, config.destination, config.includeItems, config.includeFluids)
  local stats = newStackStats()
  stats.sources = #sources

  for _, sourceInfo in ipairs(sources) do
    local source, sourceError = wrapRouterCoords(router, sourceInfo, "Source")
    if not source then
      table.insert(stats.errors, sourceError)
    elseif sourceInfo.mode == "items" then
      stats.itemSources = stats.itemSources + 1
      moveItemsFromSource(source, destination, config, stats)
    elseif sourceInfo.mode == "fluids" then
      stats.fluidSources = stats.fluidSources + 1
      moveFluidsFromSource(source, destination, config, stats)
    end
  end

  return {
    kind = "router_stack",
    command = config.command,
    dryRun = config.dryRun,
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    router = routerName,
    sourceReport = reportPath,
    destination = {
      x = config.destination.x,
      y = config.destination.y,
      z = config.destination.z,
      label = coordLabel(config.destination),
    },
    includeItems = config.includeItems,
    includeFluids = config.includeFluids,
    stats = stats,
  }
end

local function itemLine(item)
  local label = item.name or item.raw or "(unknown)"
  return label .. " x" .. tostring(item.count or "?")
end

local function printTopItems(items, limit)
  local printed = 0

  for _, item in ipairs(items or {}) do
    if printed >= limit then
      return
    end

    print("    " .. itemLine(item))
    printed = printed + 1
  end
end

local function printResultEntry(entry, sampleLimit)
  print(entry.label)
  if entry.displayName then
    print("  name: " .. tostring(entry.displayName))
  end

  if not entry.ok then
    print("  error: " .. tostring(entry.error))
    return
  end

  if not entry.inventory then
    print("  kind: " .. tostring(entry.kind or "wrappable"))
    print("  not inventory; methods: " .. tostring(entry.methodCount or #entry.methods))
    return
  end

  print("  slots: " .. tostring(entry.usedSlots) .. "/" .. tostring(entry.size) .. " used")
  print("  items: " .. tostring(entry.totalItems))

  if entry.itemTotals and #entry.itemTotals > 0 then
    print("  top:")
    printTopItems(entry.itemTotals, sampleLimit)
  else
    print("  empty")
  end

  if entry.errors and #entry.errors > 0 then
    print("  errors:")
    for _, errorLine in ipairs(entry.errors) do
      print("    " .. tostring(errorLine))
    end
  end
end

local function printReport(report)
  print("Router base map")
  print("Router: " .. tostring(report.router))
  print("Area: " .. report.width .. "x" .. report.height .. "x" .. report.depth)
  print("Radii: x=" .. report.xRadius .. " y=" .. report.yRadius .. " z=" .. report.zRadius)
  print("Offsets checked: " .. report.inspected)
  print("Wrappable: " .. report.wrappable)
  print("Inventories: " .. report.inventories)
  print("Slots: " .. report.totalUsedSlots .. "/" .. report.totalSlots .. " used")
  print("Items: " .. report.totalItems)

  if #report.results == 0 then
    print("No inventory peripherals found.")
    return
  end

  print("")
  for index, entry in ipairs(report.results) do
    print("[" .. index .. "]")
    printResultEntry(entry, report.sampleLimit)

    if index < #report.results then
      print("")
    end
  end
end

local function printStackReport(report)
  local stats = report.stats or {}
  local prefix = report.dryRun and "Stack preview" or "Stack"

  print(prefix .. " from " .. tostring(report.sourceReport))
  print("Destination: " .. tostring(report.destination and report.destination.label))
  print("Sources: " .. tostring(stats.sources or 0))
  print("Item sources: " .. tostring(stats.itemSources or 0))
  print("Fluid sources: " .. tostring(stats.fluidSources or 0))
  print("Item snapshots: " .. tostring(stats.itemSnapshots or 0))
  print("Fluid snapshots: " .. tostring(stats.fluidSnapshots or 0))
  print((report.dryRun and "Would move items: " or "Moved items: ") .. tostring(stats.movedItems or 0))
  print("Moved item slots: " .. tostring(stats.movedItemSlots or 0))

  if report.includeFluids then
    print((report.dryRun and "Would move fluid: " or "Moved fluid: ") .. tostring(stats.movedFluid or 0))
  end

  if stats.zeroMoves and stats.zeroMoves > 0 then
    print("Zero-move attempts: " .. tostring(stats.zeroMoves))
  end

  if stats.errors and #stats.errors > 0 then
    print("Errors:")
    for _, errorLine in ipairs(stats.errors) do
      print("  " .. tostring(errorLine))
    end
  end
end

local function defaultOutputPath(report)
  if report.kind == "router_stack" then
    return DEFAULT_STACK_REPORT_PATH
  end

  return DEFAULT_MAP_REPORT_PATH
end

local function saveAndMaybeSend(report, config)
  reporter.saveLocal(report, config.outputPath or defaultOutputPath(report))

  if not config.noWebhook then
    reporter.send(report)
  end
end

local ok, result = pcall(function()
  local config = parseArgs(args)

  if config.command == "help" then
    usage()
    return true
  end

  if isStackCommand(config.command) then
    local stackReport = runStack(config)
    printStackReport(stackReport)
    saveAndMaybeSend(stackReport, config)
    return true
  end

  local report = buildMap(config)
  printReport(report)
  saveAndMaybeSend(report, config)
  return true
end)

if not ok then
  print("router_inventory_scanner failed: " .. tostring(result))
  usage()
  error(result, 0)
end

if result == false then
  error("router_inventory_scanner command failed", 0)
end
