local CONFIG_PATH = "/config/processing_router.lua"

local args = { ... }
local command = args[1] or "status"

local DEFAULT_CONFIG = {
  storage = "back",
  pollSeconds = 2,
  maxJobsPerScan = 1,
  jobs = {
    {
      name = "example_press",
      input = "bottom",
      output = "top",
      items = {
        { name = "minecraft:iron_ingot", count = 1, to = "left" },
      },
    },
  },
}

local function usage()
  print("processing_router status")
  print("processing_router once")
  print("processing_router watch")
  print("processing_router drain")
  print("processing_router peripherals")
  print("")
  print("Copy config/processing_router.example.lua to config/processing_router.lua and edit jobs.")
end

local function sortedKeys(tbl)
  local keys = {}

  for key in pairs(tbl or {}) do
    table.insert(keys, key)
  end

  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)
  return keys
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

local function isInventory(object)
  return object
    and type(object.size) == "function"
    and type(object.list) == "function"
    and type(object.pushItems) == "function"
end

local function readConfig()
  if fs.exists(CONFIG_PATH) then
    local chunk, loadError = loadfile(CONFIG_PATH)
    if not chunk then
      error("Failed to load " .. CONFIG_PATH .. ": " .. tostring(loadError), 0)
    end

    local ok, config = pcall(chunk)
    if not ok then
      error("Failed to run " .. CONFIG_PATH .. ": " .. tostring(config), 0)
    end

    return config, CONFIG_PATH
  end

  return DEFAULT_CONFIG, "built-in example"
end

local function locationCoords(location)
  if type(location) ~= "table" then
    return nil, nil, nil
  end

  if location.x ~= nil and location.y ~= nil and location.z ~= nil then
    return location.x, location.y, location.z
  end

  if type(location.router) == "table" then
    return location.router.x or location.router[1], location.router.y or location.router[2], location.router.z or location.router[3]
  end

  if location[1] ~= nil and location[2] ~= nil and location[3] ~= nil then
    return location[1], location[2], location[3]
  end

  return nil, nil, nil
end

local function hasLocationCoords(location)
  local x = locationCoords(location)
  return x ~= nil
end

local function locationTransferName(location)
  if type(location) == "string" then
    return location
  end

  if type(location) == "table" then
    if location.transferName or location.side or location.id then
      return location.transferName or location.side or location.id
    end

    if not hasLocationCoords(location) then
      return location.name
    end
  end

  return nil
end

local function locationLabel(location)
  if type(location) == "string" then
    return location
  end

  if type(location) == "table" then
    if location.label then
      return location.label
    end

    if location.name and hasLocationCoords(location) then
      return location.name
    end

    local transferName = locationTransferName(location)
    if transferName then
      return transferName
    end

    local x, y, z = locationCoords(location)
    if x ~= nil then
      return "router(" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. ")"
    end
  end

  return tostring(location)
end

local cachedRouter = nil
local cachedRouterName = nil

local function findRouter()
  if cachedRouter then
    return cachedRouter, cachedRouterName
  end

  local router, name = peripheral.find("peripheral_router")
  if router and type(router.wrap) == "function" then
    cachedRouter = router
    cachedRouterName = name
    return router, name
  end

  for _, peripheralName in ipairs(peripheral.getNames()) do
    local types = { pcall(peripheral.getType, peripheralName) }
    local ok = table.remove(types, 1)
    local typeText = ok and table.concat(types, " ") or ""

    if string.find(string.lower(typeText), "peripheral_router", 1, true) then
      router = peripheral.wrap(peripheralName)
      if router and type(router.wrap) == "function" then
        cachedRouter = router
        cachedRouterName = peripheralName
        return router, peripheralName
      end
    end
  end

  return nil, nil
end

local function resolveLocation(location)
  if isInventory(location) then
    return {
      object = location,
      transferName = nil,
      label = tostring(location),
    }
  end

  if type(location) == "table" and location.object then
    return {
      object = location.object,
      transferName = location.transferName or location.side or location.id,
      label = location.label or location.name or tostring(location.object),
    }
  end

  local transferName = locationTransferName(location)
  if transferName then
    if not peripheral.isPresent(transferName) then
      return nil, "No peripheral named " .. transferName
    end

    local object = peripheral.wrap(transferName)
    if not object then
      return nil, "Failed to wrap " .. transferName
    end

    return {
      object = object,
      transferName = transferName,
      label = locationLabel(location),
    }
  end

  local x, y, z = locationCoords(location)
  if x ~= nil then
    local router, routerName = findRouter()
    if not router then
      return nil, "No peripheral_router with wrap(x, y, z) found"
    end

    local ok, object = pcall(router.wrap, x, y, z)
    if not ok then
      return nil, "Router wrap failed for " .. locationLabel(location) .. ": " .. tostring(object)
    end

    if not object then
      return nil, "Router returned no object for " .. locationLabel(location)
    end

    return {
      object = object,
      transferName = nil,
      label = locationLabel(location),
      routerName = routerName,
    }
  end

  return nil, "Invalid location " .. locationLabel(location)
end

local function resolveInventory(location, role)
  local resolved, resolveError = resolveLocation(location)
  if not resolved then
    return nil, resolveError
  end

  if not isInventory(resolved.object) then
    return nil, role .. " " .. resolved.label .. " is not an inventory"
  end

  return resolved, nil
end

local function resolveTransferTarget(location, role)
  local resolved, resolveError = resolveLocation(location)
  if not resolved then
    return nil, resolveError
  end

  return resolved, nil
end

local function normalizeItemSpec(raw)
  if type(raw) ~= "table" then
    error("Job item must be a table", 0)
  end

  local name = raw.name or raw[1]
  local count = tonumber(raw.count or raw.qty or raw.amount or raw[2] or 1)
  local to = raw.to or raw.target or raw.destination or raw.side or raw[3]

  if not name or name == "" then
    error("Job item is missing name", 0)
  end

  if not count or count < 1 or count ~= math.floor(count) then
    error("Job item " .. name .. " has invalid count", 0)
  end

  if not to then
    error("Job item " .. name .. " is missing to/target/destination", 0)
  end

  return {
    name = name,
    count = count,
    nbt = raw.nbt,
    to = to,
    toSlot = raw.toSlot or raw.slot,
  }
end

local function jobItems(job)
  local rawItems = job.items or job.ingredients or {}
  local normalized = {}

  for _, raw in ipairs(rawItems) do
    table.insert(normalized, normalizeItemSpec(raw))
  end

  if #normalized == 0 then
    error("Job " .. tostring(job.name or "(unnamed)") .. " has no items", 0)
  end

  return normalized
end

local function jobName(job)
  return tostring(job.name or "(unnamed)")
end

local function itemMatches(item, spec)
  if not item then
    return false
  end

  if item.name ~= spec.name then
    return false
  end

  if spec.nbt and item.nbt ~= spec.nbt then
    return false
  end

  return true
end

local function inventoryList(inventory)
  local ok, results = safeCall(inventory.object, "list")
  if not ok then
    return nil, results
  end

  return results[1] or {}, nil
end

local function callPushItems(inventory, destination, slot, limit, toSlot)
  if toSlot ~= nil then
    return safeCall(inventory.object, "pushItems", destination, slot, limit, toSlot)
  end

  return safeCall(inventory.object, "pushItems", destination, slot, limit)
end

local function callPullItems(inventory, source, slot, limit, toSlot)
  if toSlot ~= nil then
    return safeCall(inventory.object, "pullItems", source, slot, limit, toSlot)
  end

  return safeCall(inventory.object, "pullItems", source, slot, limit)
end

local function addTransferCandidate(candidates, mode, caller, target, label)
  if caller and caller.object and target ~= nil then
    table.insert(candidates, {
      mode = mode,
      caller = caller,
      target = target,
      label = label,
    })
  end
end

local function pushItems(inventory, destination, slot, limit, toSlot)
  local candidates = {}

  addTransferCandidate(candidates, "push", inventory, destination.object, "push to " .. destination.label .. " object")
  addTransferCandidate(candidates, "pull", destination, inventory.object, "pull from " .. inventory.label .. " object")
  addTransferCandidate(candidates, "push", inventory, destination.transferName, "push to " .. tostring(destination.transferName))
  addTransferCandidate(candidates, "pull", destination, inventory.transferName, "pull from " .. tostring(inventory.transferName))

  local firstZeroResults = nil
  local lastError = nil

  for _, candidate in ipairs(candidates) do
    local ok, results

    if candidate.mode == "push" then
      ok, results = callPushItems(candidate.caller, candidate.target, slot, limit, toSlot)
    else
      ok, results = callPullItems(candidate.caller, candidate.target, slot, limit, toSlot)
    end

    if ok then
      local moved = tonumber(results[1]) or 0

      if moved > 0 then
        return true, results, candidate.label
      end

      if not firstZeroResults then
        firstZeroResults = results
      end
    else
      lastError = candidate.label .. ": " .. tostring(results)
    end
  end

  if firstZeroResults then
    return true, firstZeroResults
  end

  return false, lastError or "No transfer target for " .. destination.label
end

local function countAvailable(items, spec)
  local count = 0

  for _, slot in ipairs(sortedSlots(items)) do
    local item = items[slot]
    if itemMatches(item, spec) then
      count = count + (tonumber(item.count) or 0)
    end
  end

  return count
end

local function checkJob(job)
  local input, inputError = resolveInventory(job.input, "input")
  if not input then
    return false, { inputError }, nil
  end

  local items, listError = inventoryList(input)
  if not items then
    return false, { listError }, input
  end

  local missing = {}
  for _, spec in ipairs(jobItems(job)) do
    local available = countAvailable(items, spec)
    if available < spec.count then
      table.insert(missing, spec.name .. " " .. available .. "/" .. spec.count)
    end
  end

  return #missing == 0, missing, input
end

local function moveMatching(source, spec, destination)
  local remaining = spec.count
  local movedTotal = 0
  local items, listError = inventoryList(source)

  if not items then
    return 0, listError
  end

  for _, slot in ipairs(sortedSlots(items)) do
    local item = items[slot]

    if itemMatches(item, spec) and remaining > 0 then
      local limit = math.min(remaining, tonumber(item.count) or 0)
      local ok, results = pushItems(source, destination, slot, limit, spec.toSlot)

      if not ok then
        return movedTotal, results
      end

      local moved = tonumber(results[1]) or 0
      movedTotal = movedTotal + moved
      remaining = remaining - moved

      if remaining <= 0 then
        return movedTotal, nil
      end
    end
  end

  return movedTotal, "Only moved " .. movedTotal .. "/" .. spec.count .. " of " .. spec.name .. " to " .. destination.label
end

local function storageLocation(config, job)
  return job.storage or config.storage
end

local function drainOutput(config, job)
  if not job.output then
    return 0, nil
  end

  local output, outputError = resolveInventory(job.output, "output")
  if not output then
    return 0, outputError
  end

  local storage, storageError = resolveTransferTarget(storageLocation(config, job), "storage")
  if not storage then
    return 0, storageError
  end

  local items, listError = inventoryList(output)
  if not items then
    return 0, listError
  end

  local totalMoved = 0
  for _, slot in ipairs(sortedSlots(items)) do
    local item = items[slot]
    if item and item.count and item.count > 0 then
      local ok, results = pushItems(output, storage, slot, item.count)
      if not ok then
        return totalMoved, results
      end

      totalMoved = totalMoved + (tonumber(results[1]) or 0)
    end
  end

  return totalMoved, nil
end

local function startJob(job)
  local ready, missing, input = checkJob(job)
  if not ready then
    return false, "Not ready: " .. table.concat(missing, ", ")
  end

  local prepared = {}
  for _, spec in ipairs(jobItems(job)) do
    local destination, destinationError = resolveTransferTarget(spec.to, "destination")
    if not destination then
      return false, destinationError
    end

    table.insert(prepared, {
      spec = spec,
      destination = destination,
    })
  end

  local moves = {}
  for _, move in ipairs(prepared) do
    local moved, moveError = moveMatching(input, move.spec, move.destination)
    table.insert(moves, move.spec.name .. " x" .. moved .. " -> " .. move.destination.label)

    if moveError then
      return false, moveError .. " after moves: " .. table.concat(moves, "; ")
    end
  end

  return true, table.concat(moves, "; ")
end

local function runDrain(config)
  local totalMoved = 0
  local errors = {}

  for _, job in ipairs(config.jobs or {}) do
    local moved, drainError = drainOutput(config, job)
    totalMoved = totalMoved + moved

    if drainError then
      table.insert(errors, jobName(job) .. ": " .. tostring(drainError))
    end
  end

  return totalMoved, errors
end

local function runOnce(config)
  local moved, errors = runDrain(config)
  local maxJobs = tonumber(config.maxJobsPerScan or config.maxJobsPerTick or 1) or 1
  local started = 0
  local startedLines = {}

  while started < maxJobs do
    local startedThisPass = false

    for _, job in ipairs(config.jobs or {}) do
      local ready = checkJob(job)

      if ready then
        local ok, detail = startJob(job)
        if ok then
          started = started + 1
          startedThisPass = true
          table.insert(startedLines, jobName(job) .. ": " .. detail)
        else
          table.insert(errors, jobName(job) .. ": " .. tostring(detail))
        end

        break
      end
    end

    if not startedThisPass then
      break
    end
  end

  return {
    drained = moved,
    started = started,
    startedLines = startedLines,
    errors = errors,
  }
end

local function printInventorySummary(location, label)
  local inventory, inventoryError = resolveInventory(location, label)
  print(label .. ": " .. locationLabel(location))

  if not inventory then
    print("  " .. tostring(inventoryError))
    return
  end

  local ok, sizeResult = safeCall(inventory.object, "size")
  local items, listError = inventoryList(inventory)

  if not ok then
    print("  " .. tostring(sizeResult))
    return
  end

  if not items then
    print("  " .. tostring(listError))
    return
  end

  local usedSlots = 0
  local totalItems = 0
  for _, slot in ipairs(sortedSlots(items)) do
    usedSlots = usedSlots + 1
    totalItems = totalItems + (tonumber(items[slot].count) or 0)
  end

  print("  Slots: " .. usedSlots .. " used / " .. tostring(sizeResult[1]) .. " total")
  print("  Items: " .. totalItems)
end

local function printStatus(config, source)
  print("Config: " .. source)
  print("Storage: " .. locationLabel(config.storage))
  print("Poll: " .. tostring(config.pollSeconds or 2) .. "s")
  print("Max jobs per scan: " .. tostring(config.maxJobsPerScan or config.maxJobsPerTick or 1))
  print("")

  local seenInputs = {}
  local seenOutputs = {}
  for _, job in ipairs(config.jobs or {}) do
    seenInputs[locationLabel(job.input)] = job.input
    if job.output then
      seenOutputs[locationLabel(job.output)] = job.output
    end
  end

  printInventorySummary(config.storage, "storage")
  for _, label in ipairs(sortedKeys(seenInputs)) do
    printInventorySummary(seenInputs[label], "input")
  end
  for _, label in ipairs(sortedKeys(seenOutputs)) do
    printInventorySummary(seenOutputs[label], "output")
  end

  print("")
  print("Jobs:")
  for _, job in ipairs(config.jobs or {}) do
    local ready, missing = checkJob(job)
    print("  " .. tostring(job.name or "(unnamed)") .. ": " .. (ready and "ready" or "waiting"))

    if not ready and #missing > 0 then
      print("    missing: " .. table.concat(missing, ", "))
    end
  end
end

local function printPeripheralList()
  for _, name in ipairs(peripheral.getNames()) do
    local types = { pcall(peripheral.getType, name) }
    local ok = table.remove(types, 1)
    print(name .. ": " .. (ok and table.concat(types, ", ") or tostring(types[1])))
  end
end

local function printRunResult(result)
  if result.drained > 0 then
    print("Returned output items: " .. result.drained)
  end

  for _, line in ipairs(result.startedLines) do
    print("Started " .. line)
  end

  if result.drained == 0 and result.started == 0 and #result.errors == 0 then
    print("Nothing to do.")
  end

  for _, errorLine in ipairs(result.errors) do
    print("Error: " .. errorLine)
  end
end

local ok, result = pcall(function()
  if command == "help" or command == "--help" or command == "-h" then
    usage()
    return true
  end

  if command == "peripherals" then
    printPeripheralList()
    return true
  end

  local config, source = readConfig()

  if command == "status" then
    printStatus(config, source)
    return true
  elseif command == "drain" then
    local moved, errors = runDrain(config)
    print("Returned output items: " .. moved)
    for _, errorLine in ipairs(errors) do
      print("Error: " .. errorLine)
    end
    return #errors == 0
  elseif command == "once" then
    printRunResult(runOnce(config))
    return true
  elseif command == "watch" then
    local pollSeconds = tonumber(config.pollSeconds or 2) or 2
    print("Watching processing jobs every " .. pollSeconds .. " second(s). Hold Ctrl+T to stop.")

    while true do
      local runResult = runOnce(config)
      if runResult.drained > 0 or runResult.started > 0 or #runResult.errors > 0 then
        print("")
        print(os.date("%H:%M:%S"))
        printRunResult(runResult)
      end

      sleep(pollSeconds)
    end
  else
    print("Unknown command: " .. tostring(command))
    usage()
    return false
  end
end)

if not ok then
  print("processing_router failed: " .. tostring(result))
  error(result, 0)
end

if result == false then
  error("processing_router command failed", 0)
end
