local controlInput = require("lib.control_input")

local redstoneRouter = {}
local unpackArgs = table.unpack or unpack

local SIDE_ALIASES = {
  top = "up",
  bottom = "down",
}

local function clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  elseif value > maxValue then
    return maxValue
  end

  return value
end

local function safePeripheralTypes(name)
  local values = { pcall(peripheral.getType, name) }
  local ok = table.remove(values, 1)

  if not ok then
    return {}
  end

  return values
end

local function isRedstoneRouterType(types)
  for _, typeName in ipairs(types or {}) do
    if string.find(string.lower(tostring(typeName)), "redstone_router", 1, true) then
      return true
    end
  end

  return false
end

local function findRedstoneRouter()
  for _, peripheralName in ipairs(peripheral.getNames()) do
    local types = safePeripheralTypes(peripheralName)

    if isRedstoneRouterType(types) then
      local wrapped = peripheral.wrap(peripheralName)
      if wrapped and type(wrapped.getRedstone) == "function" then
        return wrapped, peripheralName
      end
    end
  end

  local router = peripheral.find("redstone_router")
  if router and type(router.getRedstone) == "function" then
    return router, nil
  end

  return nil, nil
end

local function normalizeSide(side)
  local value = string.lower(tostring(side or "up"))
  return SIDE_ALIASES[value] or value
end

local function normalizeBinding(binding)
  if type(binding) ~= "table" then
    return nil
  end

  return {
    x = tonumber(binding.x) or 0,
    y = tonumber(binding.y) or 0,
    z = tonumber(binding.z) or 0,
    side = normalizeSide(binding.side),
  }
end

local function readBinding(context, binding)
  local normalized = normalizeBinding(binding)
  if not normalized then
    return {
      ok = false,
      signal = 0,
      value = 0,
      pressed = false,
      error = "missing binding",
    }
  end

  local ok, valueOrError = pcall(
    context.router.getRedstone,
    normalized.x,
    normalized.y,
    normalized.z,
    normalized.side
  )

  if not ok then
    return {
      ok = false,
      signal = 0,
      value = 0,
      pressed = false,
      coord = normalized,
      error = tostring(valueOrError),
    }
  end

  local signal = valueOrError
  if signal == true then
    signal = 15
  elseif signal == false or signal == nil then
    signal = 0
  else
    signal = tonumber(signal) or 0
  end

  signal = clamp(signal, 0, 15)

  return {
    ok = true,
    signal = signal,
    value = signal / 15,
    pressed = signal >= (tonumber(context.settings.threshold) or 1),
    coord = normalized,
    source = "redstone_router",
  }
end

function redstoneRouter.open(context)
  local router, routerName = findRedstoneRouter()
  if not router then
    error("No redstone_router with getRedstone(x, y, z, side) found", 0)
  end

  context.router = router
  context.routerName = routerName
end

function redstoneRouter.sample(context)
  local reads = controlInput.defaultReads(context.settings, "not sampled")
  local tasks = {}

  for _, inputName in ipairs(context.settings.inputs or {}) do
    local name = inputName
    table.insert(tasks, function()
      reads[name] = readBinding(context, context.settings.bindings and context.settings.bindings[name])
    end)
  end

  parallel.waitForAll(unpackArgs(tasks))

  return {
    reads = reads,
    routerName = context.routerName,
  }
end

function redstoneRouter.describe(context)
  return {
    routerName = context.routerName,
  }
end

return redstoneRouter
