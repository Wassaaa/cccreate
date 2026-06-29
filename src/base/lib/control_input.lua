local controlInput = {}

local DEFAULT_INPUTS = {
  "shift",
  "a",
  "s",
  "d",
  "space",
  "w",
  "k",
}

local TYPE_ALIASES = {
  redstone = "redstone_router",
  router = "redstone_router",
  redstone_router = "redstone_router",
  keyboard = "keyboard",
  typewriter = "keyboard",
  linked_typewriter = "keyboard",
  modem = "modem",
  rednet = "modem",
}

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

local function normalizeType(value)
  local text = string.lower(tostring(value or "redstone_router"))
  text = string.gsub(text, "%s+", "_")
  text = string.gsub(text, "-", "_")
  return TYPE_ALIASES[text] or text
end

local function inputOrder(settings)
  if type(settings) == "table" and type(settings.inputs) == "table" and #settings.inputs > 0 then
    return settings.inputs
  end

  return DEFAULT_INPUTS
end

function controlInput.defaultReads(settings, errorText)
  local reads = {}

  for _, name in ipairs(inputOrder(settings)) do
    reads[name] = {
      ok = errorText == nil,
      signal = 0,
      value = 0,
      pressed = false,
      error = errorText,
    }
  end

  return reads
end

function controlInput.readsFromPressed(settings, pressed, meta)
  local reads = {}
  local ok = true

  if meta and meta.ok ~= nil then
    ok = meta.ok == true
  end

  for _, name in ipairs(inputOrder(settings)) do
    local down = pressed and pressed[name] == true
    reads[name] = {
      ok = ok,
      signal = down and 15 or 0,
      value = down and 1 or 0,
      pressed = down,
      source = meta and meta.source,
      error = meta and meta.error,
      stale = meta and meta.stale == true,
    }
  end

  return reads
end

function controlInput.inputValue(read)
  if read and read.pressed then
    return read.value or 1
  end

  return 0
end

function controlInput.open(settings)
  settings = settings or {}
  local enabled = settings.enabled == true
  local typeName = normalizeType(settings.type)
  local context = {
    enabled = enabled,
    type = typeName,
    settings = copyPlain(settings),
    closed = false,
  }

  context.settings.type = typeName
  context.settings.inputs = inputOrder(settings)

  if not enabled then
    return context
  end

  local ok, backendOrError = pcall(require, "lib.control_input." .. typeName)
  if not ok then
    error("Unknown control input type " .. tostring(typeName) .. ": " .. tostring(backendOrError), 0)
  end

  context.backend = backendOrError
  if type(context.backend.open) == "function" then
    context.backend.open(context)
  end

  return context
end

function controlInput.sample(context)
  if not context or not context.enabled then
    return {
      enabled = false,
      type = context and context.type,
      reads = {},
    }
  end

  if context.backend and type(context.backend.sample) == "function" then
    local sample = context.backend.sample(context)
    sample.enabled = true
    sample.type = context.type
    return sample
  end

  return {
    enabled = true,
    type = context.type,
    reads = controlInput.defaultReads(context.settings, "backend has no sample"),
  }
end

function controlInput.pump(context)
  if not context or not context.enabled then
    return
  end

  if context.backend and type(context.backend.pump) == "function" then
    return context.backend.pump(context)
  end
end

function controlInput.needsPump(context)
  return context
    and context.enabled == true
    and context.backend
    and type(context.backend.pump) == "function"
end

function controlInput.close(context)
  if context then
    context.closed = true
  end
end

function controlInput.describe(context)
  if not context then
    return {
      enabled = false,
    }
  end

  local details = {
    enabled = context.enabled == true,
    type = context.type,
    settings = copyPlain(context.settings),
  }

  if context.backend and type(context.backend.describe) == "function" then
    local backendDetails = context.backend.describe(context)
    for key, value in pairs(backendDetails or {}) do
      details[key] = copyPlain(value)
    end
  end

  return details
end

controlInput.DEFAULT_INPUTS = DEFAULT_INPUTS
controlInput.normalizeType = normalizeType
controlInput.copyPlain = copyPlain

return controlInput
