local controlInput = require("lib.control_input")

local modem = {}

local function now()
  if type(os.epoch) == "function" then
    local ok, value = pcall(os.epoch, "utc")
    if ok and type(value) == "number" then
      return value / 1000
    end
  end

  return os.clock()
end

local function safePeripheralTypes(name)
  local values = { pcall(peripheral.getType, name) }
  local ok = table.remove(values, 1)

  if not ok then
    return {}
  end

  return values
end

local function isModem(name)
  for _, typeName in ipairs(safePeripheralTypes(name)) do
    if tostring(typeName) == "modem" then
      return true
    end
  end

  return false
end

local function openRednetOn(name)
  if type(rednet) ~= "table" or type(rednet.open) ~= "function" then
    return false, "rednet unavailable"
  end

  if type(rednet.isOpen) == "function" then
    local ok, isOpen = pcall(rednet.isOpen, name)
    if ok and isOpen then
      return true
    end
  end

  local ok, errorText = pcall(rednet.open, name)
  if ok then
    return true
  end

  return false, tostring(errorText)
end

local function openRednet(settings)
  if settings.modemSide then
    local ok, errorText = openRednetOn(settings.modemSide)
    if ok then
      return { settings.modemSide }
    end

    error("Could not open rednet on " .. tostring(settings.modemSide) .. ": " .. tostring(errorText), 0)
  end

  local opened = {}
  local errors = {}

  for _, name in ipairs(peripheral.getNames()) do
    if isModem(name) then
      local ok, errorText = openRednetOn(name)
      if ok then
        table.insert(opened, name)
      else
        table.insert(errors, name .. ": " .. tostring(errorText))
      end
    end
  end

  if #opened == 0 then
    error("No modem could be opened for rednet control input: " .. table.concat(errors, "; "), 0)
  end

  return opened
end

local function normalizeKey(key)
  if key == nil then
    return nil
  end

  local text = string.lower(tostring(key))
  if text == "leftshift" or text == "rightshift" or text == "left_shift" or text == "right_shift" then
    return "shift"
  elseif text == " " then
    return "space"
  end

  return text
end

local function isInput(context, name)
  for _, input in ipairs(context.settings.inputs or {}) do
    if input == name then
      return true
    end
  end

  return false
end

local function acceptsSender(context, senderId)
  local trusted = tonumber(context.remote.senderId)
  if trusted then
    return tonumber(senderId) == trusted
  end

  return true
end

local function copyPressed(context, pressed)
  local result = {}

  for key, value in pairs(pressed or {}) do
    local name = normalizeKey(key)
    if name and value == true and isInput(context, name) then
      result[name] = true
    end
  end

  return result
end

local function applyMessage(context, senderId, message)
  if not acceptsSender(context, senderId) or type(message) ~= "table" then
    return false
  end

  local seq = tonumber(message.seq)
  local senderKey = tostring(senderId)
  context.remote.lastSeqBySender = context.remote.lastSeqBySender or {}
  if seq and context.remote.lastSeqBySender[senderKey] and seq <= context.remote.lastSeqBySender[senderKey] then
    return false
  end
  if seq then
    context.remote.lastSeqBySender[senderKey] = seq
  end

  context.remote.senderLastSeen = senderId
  context.remote.lastSeen = now()
  context.remote.messageCount = (context.remote.messageCount or 0) + 1

  if message.kind == "control_state" then
    context.pressed = copyPressed(context, message.pressed)
    return true
  elseif message.kind == "control" then
    local key = normalizeKey(message.key)
    if key and isInput(context, key) then
      context.pressed[key] = message.down == true
      return true
    end
  elseif message.kind == "control_heartbeat" then
    if type(message.pressed) == "table" then
      context.pressed = copyPressed(context, message.pressed)
    end
    return true
  end

  return false
end

function modem.open(context)
  local settings = context.settings or {}
  context.pressed = {}
  context.remote = {
    protocol = tostring(settings.protocol or "cc_control"),
    senderId = settings.senderId or settings.trustedSender,
    timeout = tonumber(settings.timeout) or 0.75,
    opened = openRednet(settings),
    messageCount = 0,
    lastSeqBySender = {},
  }
end

function modem.sample(context)
  local remote = context.remote or {}
  local age = remote.lastSeen and (now() - remote.lastSeen) or nil
  local stale = false
  local errorText = nil

  if not remote.lastSeen then
    stale = true
    errorText = "waiting for remote"
  elseif age and remote.timeout and age > remote.timeout then
    stale = true
    errorText = "remote timeout"
    context.pressed = {}
  end

  return {
    reads = controlInput.readsFromPressed(context.settings, context.pressed, {
      ok = not stale,
      stale = stale,
      source = "modem",
      error = errorText,
    }),
    remote = {
      protocol = remote.protocol,
      senderId = remote.senderId,
      senderLastSeen = remote.senderLastSeen,
      lastSeenAge = age,
      timeout = remote.timeout,
      messageCount = remote.messageCount,
      opened = remote.opened,
    },
  }
end

function modem.pump(context)
  local protocol = context.remote and context.remote.protocol

  while not context.closed do
    local event, senderId, message, receivedProtocol = os.pullEvent("rednet_message")
    if event == "rednet_message" and receivedProtocol == protocol then
      applyMessage(context, senderId, message)
    end
  end
end

function modem.describe(context)
  return {
    remote = {
      protocol = context.remote and context.remote.protocol,
      senderId = context.remote and context.remote.senderId,
      senderLastSeen = context.remote and context.remote.senderLastSeen,
      timeout = context.remote and context.remote.timeout,
      opened = context.remote and controlInput.copyPlain(context.remote.opened),
      messageCount = context.remote and context.remote.messageCount,
    },
  }
end

return modem
