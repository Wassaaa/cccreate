local CONFIG_PATH = "/config/smart_sort.lua"

local DEFAULT_CONFIG = {
  target = "top",
  sources = { "back" },
  pollSeconds = 1,
  targetRefreshSeconds = 60,
  shortItemNames = true,
  allowVoidingFullTargets = true,
  wholeStackMoves = true,
  fallbackLimitedMoves = true,
  blockFailedTargets = true,
  readTargetSlotLimits = true,
  scanTargetDetails = false,
  logMoves = true,
  logIdle = false,
  statusSampleLimit = 12,
  extraTargets = {},
}

local COMMANDS = {
  ["--help"] = true,
  ["-h"] = true,
  help = true,
  once = true,
  peripherals = true,
  status = true,
  watch = true,
}

local args = { ... }

local function usage()
  print("smart_sort status [target] [sources]")
  print("smart_sort once [target] [sources]")
  print("smart_sort watch [target] [sources] [poll-seconds]")
  print("smart_sort peripherals")
  print("")
  print("Legacy: smart_sort [target] [sources] [poll-seconds]")
  print("Copy config/smart_sort.example.lua to config/smart_sort.lua for durable settings.")
end

local function trim(value)
  return tostring(value):match("^%s*(.-)%s*$")
end

local function appendCsv(result, value)
  for part in tostring(value):gmatch("[^,]+") do
    local name = trim(part)
    if name ~= "" then
      table.insert(result, name)
    end
  end
end

local function nameList(value)
  local result = {}

  if type(value) == "table" then
    for _, entry in ipairs(value) do
      appendCsv(result, entry)
    end
  elseif value ~= nil then
    appendCsv(result, value)
  end

  return result
end

local function slotList(value)
  if type(value) == "table" then
    return value
  end

  return { value }
end

local function copyList(values)
  local result = {}

  for _, value in ipairs(values or {}) do
    table.insert(result, value)
  end

  return result
end

local function shallowCopy(tbl)
  local result = {}

  for key, value in pairs(tbl or {}) do
    result[key] = value
  end

  return result
end

local function positiveNumber(value, fallback)
  local number = tonumber(value)

  if number and number > 0 then
    return number
  end

  return fallback
end

local function nonNegativeNumber(value, fallback)
  local number = tonumber(value)

  if number and number >= 0 then
    return number
  end

  return fallback
end

local function boolDefault(value, fallback)
  if value == nil then
    return fallback
  end

  return value and true or false
end

local function safeCall(target, methodName, ...)
  if type(target[methodName]) ~= "function" then
    return false, "Missing method " .. methodName
  end

  local results = { pcall(target[methodName], ...) }
  local ok = table.remove(results, 1)

  if not ok then
    return false, tostring(results[1])
  end

  return true, results
end

local function itemLabel(config, itemName)
  if not config.shortItemNames then
    return itemName
  end

  return tostring(itemName):match("^[^:]+:(.+)$") or tostring(itemName)
end

local function countText(count)
  return count and tostring(count) or "?"
end

local function nowSeconds()
  if type(os.epoch) == "function" then
    return os.epoch("utc") / 1000
  end

  return os.clock()
end

local function readConfig()
  local config = shallowCopy(DEFAULT_CONFIG)
  config.sources = copyList(DEFAULT_CONFIG.sources)
  config.extraTargets = {}
  local source = "built-in defaults"

  if fs.exists(CONFIG_PATH) then
    local chunk, loadError = loadfile(CONFIG_PATH)
    if not chunk then
      error("Failed to load " .. CONFIG_PATH .. ": " .. tostring(loadError), 0)
    end

    local ok, loaded = pcall(chunk)
    if not ok then
      error("Failed to run " .. CONFIG_PATH .. ": " .. tostring(loaded), 0)
    end

    if type(loaded) ~= "table" then
      error(CONFIG_PATH .. " must return a table", 0)
    end

    for key, value in pairs(loaded) do
      config[key] = value
    end

    source = CONFIG_PATH
  end

  config.target = config.to
    or config.toInventory
    or config.targetInventory
    or config.target
    or DEFAULT_CONFIG.target

  local sources = config.from
    or config.fromInventories
    or config.sourceInventories
    or config.sources
    or DEFAULT_CONFIG.sources

  config.sources = nameList(sources)
  if #config.sources == 0 then
    config.sources = copyList(DEFAULT_CONFIG.sources)
  end

  config.pollSeconds = positiveNumber(
    config.intervalSeconds or config.interval or config.pollSeconds,
    DEFAULT_CONFIG.pollSeconds
  )
  config.targetRefreshSeconds = nonNegativeNumber(
    config.refreshTargetSeconds or config.targetRefreshSeconds,
    DEFAULT_CONFIG.targetRefreshSeconds
  )
  config.shortItemNames = boolDefault(config.shortItemNames, DEFAULT_CONFIG.shortItemNames)
  config.allowVoidingFullTargets = boolDefault(
    config.allowVoidingFullTargets,
    DEFAULT_CONFIG.allowVoidingFullTargets
  )
  config.wholeStackMoves = boolDefault(config.wholeStackMoves, DEFAULT_CONFIG.wholeStackMoves)
  config.fallbackLimitedMoves = boolDefault(config.fallbackLimitedMoves, DEFAULT_CONFIG.fallbackLimitedMoves)
  config.blockFailedTargets = boolDefault(config.blockFailedTargets, DEFAULT_CONFIG.blockFailedTargets)
  config.readTargetSlotLimits = boolDefault(config.readTargetSlotLimits, DEFAULT_CONFIG.readTargetSlotLimits)
  config.scanTargetDetails = boolDefault(config.scanTargetDetails, DEFAULT_CONFIG.scanTargetDetails)
  config.logMoves = boolDefault(config.logMoves, DEFAULT_CONFIG.logMoves)
  config.logIdle = boolDefault(config.logIdle, DEFAULT_CONFIG.logIdle)
  config.statusSampleLimit = positiveNumber(config.statusSampleLimit, DEFAULT_CONFIG.statusSampleLimit)
  config.extraTargets = config.extraTargetSlots or config.extraTargets or {}

  return config, source
end

local function commandFromArgs()
  if args[1] and COMMANDS[args[1]] then
    return args[1], 2
  end

  return "watch", 1
end

local function applyPositionalOverrides(config, startIndex)
  if args[startIndex] then
    config.target = args[startIndex]
  end

  if args[startIndex + 1] then
    config.sources = nameList(args[startIndex + 1])
  end

  if args[startIndex + 2] then
    config.pollSeconds = positiveNumber(args[startIndex + 2], config.pollSeconds)
  end
end

local function validateConfig(config)
  if not config.target or config.target == "" then
    error("Set a target inventory", 0)
  end

  if #config.sources == 0 then
    error("Set at least one source inventory", 0)
  end

  for _, sourceName in ipairs(config.sources) do
    if sourceName == config.target then
      error("Source and target inventory are both " .. sourceName, 0)
    end
  end
end

local function wrapInventory(name, role, requirePush)
  local wrapped = peripheral.wrap(name)

  if not wrapped then
    error(role .. " inventory not found: " .. tostring(name), 0)
  end

  if type(wrapped.list) ~= "function" then
    error(role .. " is not an inventory: " .. tostring(name), 0)
  end

  if requirePush and type(wrapped.pushItems) ~= "function" then
    error(role .. " cannot push items: " .. tostring(name), 0)
  end

  return {
    name = name,
    object = wrapped,
  }
end

local function wrapSources(config)
  local sources = {}

  for _, sourceName in ipairs(config.sources) do
    table.insert(sources, wrapInventory(sourceName, "Source", true))
  end

  return sources
end

local function readTargetLimit(target, slot, config)
  if not config.readTargetSlotLimits then
    return nil
  end

  local ok, results = safeCall(target.object, "getItemLimit", slot)
  if not ok then
    return nil
  end

  return tonumber(results[1])
end

local function addTarget(index, target, itemName, slot, count, source, config)
  if not itemName or slot == nil then
    return
  end

  local numericSlot = tonumber(slot)
  if not numericSlot then
    return
  end

  local slots = index.byName[itemName]
  if not slots then
    slots = {}
    index.byName[itemName] = slots
    index.itemTypes = index.itemTypes + 1
  end

  for _, existing in ipairs(slots) do
    if existing.slot == numericSlot then
      existing.count = tonumber(count) or existing.count
      existing.source = source or existing.source
      return
    end
  end

  local entry = {
    itemName = itemName,
    slot = numericSlot,
    count = tonumber(count) or 0,
    limit = readTargetLimit(target, numericSlot, config),
    source = source,
    blocked = false,
  }

  if not config.allowVoidingFullTargets
    and entry.limit
    and entry.count
    and entry.count >= entry.limit
  then
    entry.blocked = true
    index.fullSlots = index.fullSlots + 1
  end

  table.insert(slots, entry)
  index.slots = index.slots + 1
end

local function buildTargetIndex(target, config)
  local index = {
    byName = {},
    slots = 0,
    itemTypes = 0,
    fullSlots = 0,
    detailSlotsScanned = 0,
    scannedAt = nowSeconds(),
  }

  local ok, results = safeCall(target.object, "list")
  if not ok then
    error("Failed to list target " .. target.name .. ": " .. tostring(results), 0)
  end

  for slot, item in pairs(results[1] or {}) do
    if item and item.name then
      addTarget(index, target, item.name, slot, item.count, "list", config)
    end
  end

  if config.scanTargetDetails then
    local okSize, sizeResults = safeCall(target.object, "size")
    if okSize then
      for slot = 1, tonumber(sizeResults[1]) or 0 do
        local okDetail, detailResults = safeCall(target.object, "getItemDetail", slot)
        index.detailSlotsScanned = index.detailSlotsScanned + 1

        if okDetail then
          local item = detailResults[1]
          if item and item.name then
            addTarget(index, target, item.name, slot, item.count, "detail", config)
          end
        end
      end
    end
  end

  for itemName, slots in pairs(config.extraTargets or {}) do
    for _, slot in ipairs(slotList(slots)) do
      addTarget(index, target, itemName, slot, 0, "config", config)
    end
  end

  return index
end

local function targetHasRoom(target, config)
  if config.allowVoidingFullTargets then
    return true
  end

  if target.limit and target.count and target.count >= target.limit then
    target.blocked = true
    return false
  end

  return true
end

local function callPush(source, targetName, fromSlot, limit, toSlot)
  if toSlot ~= nil then
    return safeCall(source.object, "pushItems", targetName, fromSlot, limit, toSlot)
  end

  if limit ~= nil then
    return safeCall(source.object, "pushItems", targetName, fromSlot, limit)
  end

  return safeCall(source.object, "pushItems", targetName, fromSlot)
end

local function pushStack(source, targetName, fromSlot, fallbackLimit, toSlot, config)
  if config.wholeStackMoves then
    local ok, results = callPush(source, targetName, fromSlot, nil, toSlot)
    if ok then
      return tonumber(results[1]) or 0, nil, false
    end

    if not config.fallbackLimitedMoves then
      return 0, results, false
    end

    local okLimited, limitedResults = callPush(
      source,
      targetName,
      fromSlot,
      tonumber(fallbackLimit) or 64,
      toSlot
    )

    if okLimited then
      return tonumber(limitedResults[1]) or 0, nil, true
    end

    return 0, tostring(results) .. "; fallback: " .. tostring(limitedResults), true
  end

  local ok, results = callPush(source, targetName, fromSlot, tonumber(fallbackLimit) or 64, toSlot)
  if not ok then
    return 0, results, false
  end

  return tonumber(results[1]) or 0, nil, false
end

local function logMove(config, source, item, fromSlot, moved, target, before, after, usedFallback)
  if not config.logMoves then
    return
  end

  local suffix = usedFallback and " limited" or ""
  print(
    itemLabel(config, item.name)
      .. " "
      .. source.name
      .. ":"
      .. fromSlot
      .. " "
      .. moved
      .. "/"
      .. countText(item.count)
      .. " -> "
      .. target.slot
      .. " "
      .. countText(before)
      .. ">"
      .. countText(after)
      .. suffix
  )
end

local function newStats()
  return {
    attempts = 0,
    moved = 0,
    movedSlots = 0,
    sourceScans = 0,
    zeroMoves = 0,
    blockedTargets = 0,
    errors = {},
  }
end

local function moveFromSource(source, target, index, config, stats)
  local ok, results = safeCall(source.object, "list")
  stats.sourceScans = stats.sourceScans + 1

  if not ok then
    table.insert(stats.errors, source.name .. " list failed: " .. tostring(results))
    return
  end

  for fromSlot, item in pairs(results[1] or {}) do
    if item and item.name and item.count and item.count > 0 then
      local targetSlots = index.byName[item.name]

      if targetSlots then
        local remaining = tonumber(item.count) or 0
        local slotMoved = 0

        for _, targetSlot in ipairs(targetSlots) do
          if remaining <= 0 then
            break
          end

          if not targetSlot.blocked and targetHasRoom(targetSlot, config) then
            local before = targetSlot.count
            local moved, moveError, usedFallback = pushStack(
              source,
              target.name,
              fromSlot,
              remaining,
              targetSlot.slot,
              config
            )
            stats.attempts = stats.attempts + 1

            if moveError then
              targetSlot.blocked = true
              stats.blockedTargets = stats.blockedTargets + 1
              table.insert(
                stats.errors,
                source.name
                  .. ":"
                  .. fromSlot
                  .. " -> "
                  .. target.name
                  .. ":"
                  .. targetSlot.slot
                  .. " failed: "
                  .. tostring(moveError)
              )
            elseif moved > 0 then
              local after = before and (before + moved) or nil
              targetSlot.count = after or targetSlot.count
              remaining = math.max(0, remaining - moved)
              stats.moved = stats.moved + moved
              slotMoved = slotMoved + moved
              logMove(config, source, item, fromSlot, moved, targetSlot, before, after, usedFallback)

              if not config.allowVoidingFullTargets
                and targetSlot.limit
                and targetSlot.count
                and targetSlot.count >= targetSlot.limit
              then
                targetSlot.blocked = true
              end
            else
              stats.zeroMoves = stats.zeroMoves + 1

              if config.blockFailedTargets then
                targetSlot.blocked = true
                stats.blockedTargets = stats.blockedTargets + 1
              end
            end
          end
        end

        if slotMoved > 0 then
          stats.movedSlots = stats.movedSlots + 1
        end
      end
    end
  end
end

local function runPass(sources, target, index, config)
  local stats = newStats()

  for _, source in ipairs(sources) do
    moveFromSource(source, target, index, config, stats)
  end

  return stats
end

local function printRunResult(stats, always)
  if stats.moved > 0 then
    print(
      "Moved "
        .. stats.moved
        .. " item(s) from "
        .. stats.movedSlots
        .. " source slot(s) in "
        .. stats.attempts
        .. " move attempt(s)."
    )
  elseif always then
    print("Nothing to move.")
  end

  if stats.zeroMoves > 0 then
    print("Zero-move attempts: " .. stats.zeroMoves)
  end

  if stats.blockedTargets > 0 then
    print("Blocked target slots until refresh: " .. stats.blockedTargets)
  end

  for _, line in ipairs(stats.errors) do
    print("Error: " .. line)
  end
end

local function sortedKeys(tbl)
  local keys = {}

  for key in pairs(tbl or {}) do
    table.insert(keys, key)
  end

  table.sort(keys)
  return keys
end

local function printTargetIndex(index, config)
  print("Target slots: " .. index.slots .. " across " .. index.itemTypes .. " item type(s)")

  if index.fullSlots > 0 then
    print("Full target slots skipped: " .. index.fullSlots)
  end

  if index.detailSlotsScanned > 0 then
    print("Detail slots scanned: " .. index.detailSlotsScanned)
  end

  local shown = 0
  for _, itemName in ipairs(sortedKeys(index.byName)) do
    if shown >= config.statusSampleLimit then
      break
    end

    local slots = {}
    for _, target in ipairs(index.byName[itemName]) do
      table.insert(slots, tostring(target.slot))
    end

    print("  " .. itemLabel(config, itemName) .. ": " .. table.concat(slots, ", "))
    shown = shown + 1
  end
end

local function printSourceStatus(source, index, config)
  local ok, results = safeCall(source.object, "list")
  if not ok then
    print(source.name .. ": " .. tostring(results))
    return
  end

  local usedSlots = 0
  local totalItems = 0
  local matchingSlots = 0
  local matchingItems = 0

  for _, item in pairs(results[1] or {}) do
    usedSlots = usedSlots + 1
    totalItems = totalItems + (tonumber(item.count) or 0)

    if item.name and index.byName[item.name] then
      matchingSlots = matchingSlots + 1
      matchingItems = matchingItems + (tonumber(item.count) or 0)
    end
  end

  print(
    source.name
      .. ": "
      .. usedSlots
      .. " used slot(s), "
      .. totalItems
      .. " item(s), "
      .. matchingSlots
      .. " sortable slot(s), "
      .. matchingItems
      .. " sortable item(s)"
  )
end

local function printStatus(config, configSource, target, sources, index)
  print("Config: " .. configSource)
  print("Target: " .. target.name)
  print("Sources: " .. table.concat(config.sources, ", "))
  print("Poll: " .. config.pollSeconds .. "s")

  if config.targetRefreshSeconds == 0 then
    print("Target refresh: startup only")
  else
    print("Target refresh: " .. config.targetRefreshSeconds .. "s")
  end

  print("Whole-stack moves: " .. tostring(config.wholeStackMoves))
  print("Target detail scan: " .. tostring(config.scanTargetDetails))
  print("")
  printTargetIndex(index, config)
  print("")
  print("Sources:")

  for _, source in ipairs(sources) do
    printSourceStatus(source, index, config)
  end
end

local function printPeripheralList()
  for _, name in ipairs(peripheral.getNames()) do
    local types = { pcall(peripheral.getType, name) }
    local ok = table.remove(types, 1)
    print(name .. ": " .. (ok and table.concat(types, ", ") or tostring(types[1])))
  end
end

local function runWatch(config, target, sources, index)
  print("Smart sort running.")
  print("To: " .. target.name)
  print("From: " .. table.concat(config.sources, ", "))
  print("Poll: " .. config.pollSeconds .. "s")

  if config.targetRefreshSeconds == 0 then
    print("Target index: startup only")
  else
    print("Target index: refresh every " .. config.targetRefreshSeconds .. "s")
  end

  printTargetIndex(index, config)

  while true do
    if config.targetRefreshSeconds > 0
      and nowSeconds() - index.scannedAt >= config.targetRefreshSeconds
    then
      index = buildTargetIndex(target, config)
      print("Refreshed target index: " .. index.slots .. " slot(s), " .. index.itemTypes .. " item type(s)")
    end

    local stats = runPass(sources, target, index, config)
    if stats.moved > 0 or #stats.errors > 0 or config.logIdle then
      print("")
      print(os.date("%H:%M:%S"))
      printRunResult(stats, config.logIdle)
    end

    sleep(config.pollSeconds)
  end
end

local ok, result = pcall(function()
  local command, overrideIndex = commandFromArgs()

  if command == "help" or command == "--help" or command == "-h" then
    usage()
    return true
  end

  if command == "peripherals" then
    printPeripheralList()
    return true
  end

  local config, configSource = readConfig()
  applyPositionalOverrides(config, overrideIndex)
  validateConfig(config)

  local target = wrapInventory(config.target, "Target", false)
  local sources = wrapSources(config)
  local index = buildTargetIndex(target, config)

  if command == "status" then
    printStatus(config, configSource, target, sources, index)
    return true
  elseif command == "once" then
    printRunResult(runPass(sources, target, index, config), true)
    return true
  elseif command == "watch" then
    runWatch(config, target, sources, index)
    return true
  end

  print("Unknown command: " .. tostring(command))
  usage()
  return false
end)

if not ok then
  print("smart_sort failed: " .. tostring(result))
  error(result, 0)
end

if result == false then
  error("smart_sort command failed", 0)
end
