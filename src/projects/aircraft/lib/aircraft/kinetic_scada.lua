local coords = require("lib.aircraft.coords")

local kineticScada = {}

local CONTROL_METHODS = {
  "setSignal",
  "setTargetSpeed",
  "setGeneratedSpeed",
  "setSpeed",
  "setPower",
  "setPowerNormalized",
  "setThrust",
  "setThrustNormalized",
  "setShiftLevel",
  "setTransmissionMode",
  "setManualTarget",
  "setLimit",
  "setSteering",
  "setBrake",
}

kineticScada.CONTROL_METHODS = CONTROL_METHODS

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

local function copyCoord(coord)
  if not coord then
    return nil
  end

  return {
    x = coord.x,
    y = coord.y,
    z = coord.z,
    key = coord.key or coords.key(coord.x, coord.y, coord.z),
  }
end

local function idValue(value)
  if value == nil then
    return nil
  end

  return tostring(value)
end

local function methodSet(entry)
  local set = {}

  for _, method in ipairs(entry and entry.methods or {}) do
    set[method] = true
  end

  return set
end

local function append(list, value)
  table.insert(list, value)
end

local function appendUnique(list, value)
  if value == nil then
    return
  end

  for _, existing in ipairs(list) do
    if existing == value then
      return
    end
  end

  table.insert(list, value)
end

local function sortedKeys(map)
  local keys = {}

  for key, _ in pairs(map or {}) do
    table.insert(keys, key)
  end

  table.sort(keys, function(left, right)
    return tostring(left) < tostring(right)
  end)

  return keys
end

local function sortList(list)
  table.sort(list, function(left, right)
    return tostring(left) < tostring(right)
  end)
end

local function countKeys(map)
  local count = 0

  for _, _ in pairs(map or {}) do
    count = count + 1
  end

  return count
end

local function controlMethods(entry)
  local methods = methodSet(entry)
  local result = {}

  for _, method in ipairs(CONTROL_METHODS) do
    if methods[method] then
      table.insert(result, method)
    end
  end

  return result
end

local function updateRange(target, prefix, value)
  value = tonumber(value)
  if value == nil then
    return
  end

  local minKey = prefix .. "Min"
  local maxKey = prefix .. "Max"
  if target[minKey] == nil or value < target[minKey] then
    target[minKey] = value
  end
  if target[maxKey] == nil or value > target[maxKey] then
    target[maxKey] = value
  end
end

local function addWarning(result, kind, details)
  table.insert(result.warnings, {
    kind = kind,
    details = copyPlain(details),
  })
  result.summary.warnings = #result.warnings
end

local function addMissing(map, id, referencedBy)
  if not id then
    return
  end

  local entry = map[id]
  if not entry then
    entry = {
      id = id,
      referencedBy = {},
    }
    map[id] = entry
  end

  appendUnique(entry.referencedBy, referencedBy)
end

local function ensureGroup(map, id)
  if not id then
    return nil
  end

  local group = map[id]
  if not group then
    group = {
      id = id,
      nodeIds = {},
      roots = {},
      leaves = {},
      drivers = {},
      consumers = {},
      generators = {},
      splitShafts = {},
      subnetworks = {},
      kindCounts = {},
      stressImpact = 0,
      stressContribution = 0,
      overstressed = false,
    }
    map[id] = group
  end

  return group
end

local function addNodeToGroup(group, node)
  if not group or not node then
    return
  end

  appendUnique(group.nodeIds, node.id)
  if node.kind then
    group.kindCounts[node.kind] = (group.kindCounts[node.kind] or 0) + 1
  end

  if node.subnetworkAnchorId then
    appendUnique(group.subnetworks, node.subnetworkAnchorId)
  end

  if type(node.stressImpact) == "number" then
    group.stressImpact = group.stressImpact + node.stressImpact
  end
  if type(node.stressContribution) == "number" then
    group.stressContribution = group.stressContribution + node.stressContribution
  end
  if node.isOverstressed == true then
    group.overstressed = true
  end

  updateRange(group, "speed", node.speed)
end

local function makeNode(entry, kinetic)
  local methods = controlMethods(entry)
  local kind = kinetic.kind and tostring(kinetic.kind) or nil
  local stressImpact = tonumber(kinetic.stressImpact)
  local stressContribution = tonumber(kinetic.stressContribution)
  local node = {
    id = idValue(kinetic.selfId),
    coord = copyCoord(entry.coord),
    categories = copyPlain(entry.categories or {}),
    kind = kind,
    networkId = idValue(kinetic.networkId),
    subnetworkAnchorId = idValue(kinetic.subnetworkAnchorId),
    sourceId = idValue(kinetic.sourceId),
    speed = tonumber(kinetic.speed),
    hasSource = kinetic.hasSource,
    isOverstressed = kinetic.isOverstressed,
    stressImpact = stressImpact,
    stressContribution = stressContribution,
    methodCount = entry.methodCount,
    controlMethods = methods,
    childIds = {},
  }

  node.isDriver = #methods > 0
  node.isGenerator = kind == "generator" or (stressContribution and stressContribution > 0) or false
  node.isConsumer = kind == "consumer" or (stressImpact and stressImpact > 0) or false
  node.isSplitShaft = kind == "split_shaft"

  return node
end

local function sourcePath(nodes, startId)
  local path = {}
  local seen = {}
  local currentId = startId

  while currentId do
    if seen[currentId] then
      return {
        ids = path,
        complete = false,
        stoppedBy = "cycle",
        repeatedId = currentId,
      }
    end

    seen[currentId] = true
    table.insert(path, currentId)

    local node = nodes[currentId]
    if not node then
      return {
        ids = path,
        complete = false,
        stoppedBy = "missing_source",
        missingId = currentId,
      }
    end

    if not node.sourceId then
      return {
        ids = path,
        complete = true,
        stoppedBy = "root",
      }
    end

    currentId = node.sourceId
  end

  return {
    ids = path,
    complete = true,
    stoppedBy = "root",
  }
end

local function nearestDriver(nodes, path)
  for _, id in ipairs(path.ids or {}) do
    local node = nodes[id]
    if node and node.isDriver then
      return id
    end
  end

  return nil
end

local function finalizeGroup(group)
  sortList(group.nodeIds)
  sortList(group.roots)
  sortList(group.leaves)
  sortList(group.drivers)
  sortList(group.consumers)
  sortList(group.generators)
  sortList(group.splitShafts)
  sortList(group.subnetworks)
end

function kineticScada.build(scan)
  local result = {
    nodes = {},
    nodeIds = {},
    edges = {},
    networks = {},
    networkIds = {},
    subnetworks = {},
    subnetworkIds = {},
    rootIds = {},
    leafIds = {},
    driverIds = {},
    consumerIds = {},
    generatorIds = {},
    splitShaftIds = {},
    unnetworkedIds = {},
    unanchoredIds = {},
    leafControls = {},
    missingSourceIds = {},
    missingAnchorIds = {},
    unidentifiedEntries = {},
    duplicateIds = {},
    warnings = {},
    summary = {
      scannedEntries = 0,
      nodes = 0,
      edges = 0,
      resolvedEdges = 0,
      missingSourceIds = 0,
      missingAnchorIds = 0,
      networks = 0,
      subnetworks = 0,
      roots = 0,
      leaves = 0,
      drivers = 0,
      consumers = 0,
      generators = 0,
      splitShafts = 0,
      unnetworked = 0,
      unanchored = 0,
      overstressedNodes = 0,
      unidentifiedEntries = 0,
      duplicateIds = 0,
      warnings = 0,
    },
  }

  for _, entry in ipairs(scan and scan.peripherals or {}) do
    local kinetic = entry.kineticScada or entry.kinetic
    if kinetic then
      result.summary.scannedEntries = result.summary.scannedEntries + 1
      local selfId = idValue(kinetic.selfId)

      if not selfId then
        table.insert(result.unidentifiedEntries, {
          coord = copyCoord(entry.coord),
          categories = copyPlain(entry.categories or {}),
          readErrors = copyPlain(kinetic.readErrors),
          nilFields = copyPlain(kinetic.nilFields),
        })
        addWarning(result, "kinetic_entry_without_self_id", {
          coord = copyCoord(entry.coord),
        })
      else
        local node = makeNode(entry, kinetic)
        if result.nodes[selfId] then
          local duplicate = {
            id = selfId,
            coord = copyCoord(entry.coord),
            existingCoord = copyCoord(result.nodes[selfId].coord),
          }
          table.insert(result.duplicateIds, duplicate)
          result.nodes[selfId].duplicates = result.nodes[selfId].duplicates or {}
          table.insert(result.nodes[selfId].duplicates, duplicate)
          addWarning(result, "duplicate_self_id", duplicate)
        else
          result.nodes[selfId] = node
          table.insert(result.nodeIds, selfId)
        end
      end
    end
  end

  sortList(result.nodeIds)

  for _, id in ipairs(result.nodeIds) do
    local node = result.nodes[id]

    if node.sourceId then
      local resolved = result.nodes[node.sourceId] ~= nil
      table.insert(result.edges, {
        from = node.sourceId,
        to = id,
        networkId = node.networkId,
        resolved = resolved,
      })

      if resolved then
        appendUnique(result.nodes[node.sourceId].childIds, id)
      else
        addMissing(result.missingSourceIds, node.sourceId, id)
        addWarning(result, "missing_source_id", {
          id = node.sourceId,
          referencedBy = id,
        })
      end
    end

    if node.subnetworkAnchorId and not result.nodes[node.subnetworkAnchorId] then
      addMissing(result.missingAnchorIds, node.subnetworkAnchorId, id)
      addWarning(result, "missing_subnetwork_anchor_id", {
        id = node.subnetworkAnchorId,
        referencedBy = id,
      })
    end

    addNodeToGroup(ensureGroup(result.networks, node.networkId), node)
    addNodeToGroup(ensureGroup(result.subnetworks, node.subnetworkAnchorId), node)
  end

  table.sort(result.edges, function(left, right)
    local leftKey = tostring(left.from) .. ">" .. tostring(left.to)
    local rightKey = tostring(right.from) .. ">" .. tostring(right.to)
    return leftKey < rightKey
  end)

  for _, id in ipairs(result.nodeIds) do
    local node = result.nodes[id]
    sortList(node.childIds)
    node.isLeaf = #node.childIds == 0
    node.isRoot = not node.sourceId or node.hasSource == false
    node.hasMissingSource = node.sourceId and result.nodes[node.sourceId] == nil or false

    if node.isRoot then
      append(result.rootIds, id)
    end
    if node.isLeaf then
      append(result.leafIds, id)
    end
    if node.isDriver then
      append(result.driverIds, id)
    end
    if node.isConsumer then
      append(result.consumerIds, id)
    end
    if node.isGenerator then
      append(result.generatorIds, id)
    end
    if node.isSplitShaft then
      append(result.splitShaftIds, id)
    end
    if not node.networkId then
      append(result.unnetworkedIds, id)
    end
    if not node.subnetworkAnchorId then
      append(result.unanchoredIds, id)
    end
    if node.isOverstressed == true then
      result.summary.overstressedNodes = result.summary.overstressedNodes + 1
    end

    local network = result.networks[node.networkId]
    local subnetwork = result.subnetworks[node.subnetworkAnchorId]

    if network then
      if node.isRoot then appendUnique(network.roots, id) end
      if node.isLeaf then appendUnique(network.leaves, id) end
      if node.isDriver then appendUnique(network.drivers, id) end
      if node.isConsumer then appendUnique(network.consumers, id) end
      if node.isGenerator then appendUnique(network.generators, id) end
      if node.isSplitShaft then appendUnique(network.splitShafts, id) end
    end

    if subnetwork then
      if node.isRoot then appendUnique(subnetwork.roots, id) end
      if node.isLeaf then appendUnique(subnetwork.leaves, id) end
      if node.isDriver then appendUnique(subnetwork.drivers, id) end
      if node.isConsumer then appendUnique(subnetwork.consumers, id) end
      if node.isGenerator then appendUnique(subnetwork.generators, id) end
      if node.isSplitShaft then appendUnique(subnetwork.splitShafts, id) end
    end
  end

  sortList(result.rootIds)
  sortList(result.leafIds)
  sortList(result.driverIds)
  sortList(result.consumerIds)
  sortList(result.generatorIds)
  sortList(result.splitShaftIds)
  sortList(result.unnetworkedIds)
  sortList(result.unanchoredIds)

  for _, leafId in ipairs(result.leafIds) do
    local path = sourcePath(result.nodes, leafId)
    result.leafControls[leafId] = {
      leafId = leafId,
      upstreamDriverId = nearestDriver(result.nodes, path),
      sourcePath = path,
    }

    if path.stoppedBy == "cycle" then
      addWarning(result, "source_cycle", {
        leafId = leafId,
        repeatedId = path.repeatedId,
      })
    end
  end

  result.networkIds = sortedKeys(result.networks)
  result.subnetworkIds = sortedKeys(result.subnetworks)

  for _, id in ipairs(result.networkIds) do
    finalizeGroup(result.networks[id])
  end
  for _, id in ipairs(result.subnetworkIds) do
    finalizeGroup(result.subnetworks[id])
  end

  result.summary.nodes = #result.nodeIds
  result.summary.edges = #result.edges
  result.summary.resolvedEdges = 0
  for _, edge in ipairs(result.edges) do
    if edge.resolved then
      result.summary.resolvedEdges = result.summary.resolvedEdges + 1
    end
  end
  result.summary.missingSourceIds = countKeys(result.missingSourceIds)
  result.summary.missingAnchorIds = countKeys(result.missingAnchorIds)
  result.summary.networks = #result.networkIds
  result.summary.subnetworks = #result.subnetworkIds
  result.summary.roots = #result.rootIds
  result.summary.leaves = #result.leafIds
  result.summary.drivers = #result.driverIds
  result.summary.consumers = #result.consumerIds
  result.summary.generators = #result.generatorIds
  result.summary.splitShafts = #result.splitShaftIds
  result.summary.unnetworked = #result.unnetworkedIds
  result.summary.unanchored = #result.unanchoredIds
  result.summary.unidentifiedEntries = #result.unidentifiedEntries
  result.summary.duplicateIds = #result.duplicateIds
  result.summary.warnings = #result.warnings

  return result
end

return kineticScada
