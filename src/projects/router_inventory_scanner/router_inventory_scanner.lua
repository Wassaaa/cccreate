local reporter = require("lib.reporter")

local DEFAULT_RADIUS = 2
local DEFAULT_SAMPLE_LIMIT = 5
local MAX_RADIUS = 16

local args = { ... }

local function usage()
  print("router_inventory_scanner [scan|report] [radius]")
  print("router_inventory_scanner scan --radius 2 --sample 5")
  print("router_inventory_scanner scan --all")
  print("")
  print("Default radius 2 scans a 5x5x5 cube around the router.")
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

local function parseArgs(rawArgs)
  local config = {
    command = "scan",
    radius = DEFAULT_RADIUS,
    sampleLimit = DEFAULT_SAMPLE_LIMIT,
    includeAll = false,
    includeOrigin = false,
  }

  local index = 1
  if rawArgs[index] == "scan" or rawArgs[index] == "report" then
    config.command = rawArgs[index]
    index = index + 1
  elseif rawArgs[index] == "help" or rawArgs[index] == "--help" or rawArgs[index] == "-h" then
    config.command = "help"
    return config
  elseif tonumber(rawArgs[index]) then
    config.radius = parsePositiveInteger(rawArgs[index], "radius")
    index = index + 1
  elseif rawArgs[index] ~= nil then
    error("Unknown command: " .. tostring(rawArgs[index]), 0)
  end

  while index <= #rawArgs do
    local arg = rawArgs[index]

    if arg == "--radius" or arg == "-r" then
      config.radius = parsePositiveInteger(rawArgs[index + 1], "radius")
      index = index + 2
    elseif arg == "--sample" or arg == "-s" then
      config.sampleLimit = parsePositiveInteger(rawArgs[index + 1], "sample")
      index = index + 2
    elseif arg == "--all" then
      config.includeAll = true
      index = index + 1
    elseif arg == "--include-origin" then
      config.includeOrigin = true
      index = index + 1
    elseif tonumber(arg) and index == 2 then
      config.radius = parsePositiveInteger(arg, "radius")
      index = index + 1
    else
      error("Unknown option: " .. tostring(arg), 0)
    end
  end

  if config.radius > MAX_RADIUS then
    error("radius must be " .. MAX_RADIUS .. " or less", 0)
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

  return entry
end

local function scan(config)
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

  for y = -config.radius, config.radius do
    for x = -config.radius, config.radius do
      for z = -config.radius, config.radius do
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

          if entry.inventory or (config.includeAll and entry.ok) or (entry.error and entry.error ~= "no peripheral") then
            table.insert(results, entry)
          end
        end
      end
    end
  end

  return {
    kind = "router_inventory_scan",
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    router = routerName,
    radius = config.radius,
    cubeSize = config.radius * 2 + 1,
    sampleLimit = config.sampleLimit,
    includeAll = config.includeAll,
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

  if not entry.ok then
    print("  error: " .. tostring(entry.error))
    return
  end

  if not entry.inventory then
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
  print("Router inventory scan")
  print("Router: " .. tostring(report.router))
  print("Area: " .. report.cubeSize .. "x" .. report.cubeSize .. "x" .. report.cubeSize)
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

local ok, result = pcall(function()
  local config = parseArgs(args)

  if config.command == "help" then
    usage()
    return true
  end

  local report = scan(config)
  printReport(report)
  reporter.saveLocal(report, "router_inventory_scan_report.txt")

  if config.command == "report" then
    reporter.send(report)
  end

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
