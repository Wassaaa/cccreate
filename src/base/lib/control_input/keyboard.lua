local controlInput = require("lib.control_input")

local keyboard = {}

local GLFW_CODES = {
  [32] = "space",
  [65] = "a",
  [68] = "d",
  [83] = "s",
  [87] = "w",
  [75] = "k",
  [340] = "shift",
  [344] = "shift",
}

local NAME_ALIASES = {
  [" "] = "space",
  leftShift = "shift",
  rightShift = "shift",
  left_shift = "shift",
  right_shift = "shift",
  lshift = "shift",
  rshift = "shift",
  shift = "shift",
  space = "space",
}

local function addKeyConstant(codes, name, logical)
  if type(keys) == "table" and keys[name] ~= nil then
    codes[keys[name]] = logical
  end
end

local function defaultKeyCodes()
  local codes = {}

  for code, logical in pairs(GLFW_CODES) do
    codes[code] = logical
  end

  addKeyConstant(codes, "w", "w")
  addKeyConstant(codes, "a", "a")
  addKeyConstant(codes, "s", "s")
  addKeyConstant(codes, "d", "d")
  addKeyConstant(codes, "k", "k")
  addKeyConstant(codes, "space", "space")
  addKeyConstant(codes, "leftShift", "shift")
  addKeyConstant(codes, "rightShift", "shift")
  addKeyConstant(codes, "leftCtrl", "ctrl")
  addKeyConstant(codes, "rightCtrl", "ctrl")

  return codes
end

local function normalizeName(name)
  if name == nil then
    return nil
  end

  local text = tostring(name)
  if NAME_ALIASES[text] then
    return NAME_ALIASES[text]
  end

  text = string.gsub(text, "%s+", "")
  if NAME_ALIASES[text] then
    return NAME_ALIASES[text]
  end

  if #text == 1 then
    return string.lower(text)
  end

  return string.lower(text)
end

local function configuredLogical(settings, code, name)
  local keyMap = settings.keyMap
  if type(keyMap) ~= "table" then
    return nil
  end

  if keyMap[code] then
    return normalizeName(keyMap[code])
  end

  if keyMap[tostring(code)] then
    return normalizeName(keyMap[tostring(code)])
  end

  if name and keyMap[name] then
    return normalizeName(keyMap[name])
  end

  return nil
end

local function logicalKey(context, code)
  local settings = context.settings or {}
  local name = nil

  if type(keys) == "table" and type(keys.getName) == "function" then
    local ok, value = pcall(keys.getName, code)
    if ok then
      name = value
    end
  end

  return configuredLogical(settings, code, name)
    or context.keyCodes[code]
    or normalizeName(name)
    or GLFW_CODES[code]
end

local function isInput(context, name)
  for _, input in ipairs(context.settings.inputs or {}) do
    if input == name then
      return true
    end
  end

  return false
end

local function isPulseInput(context, name)
  local pulseInputs = context.settings and context.settings.pulseInputs

  if type(pulseInputs) ~= "table" then
    return false
  end

  return pulseInputs[name] == true
end

function keyboard.open(context)
  context.pressed = {}
  context.pulses = {}
  context.keyCodes = defaultKeyCodes()
  context.eventCount = 0
end

function keyboard.sample(context)
  local reads = controlInput.readsFromPressed(context.settings, context.pressed, {
    ok = true,
    source = "keyboard",
  })

  for name, pulsed in pairs(context.pulses or {}) do
    if pulsed and reads[name] then
      reads[name].signal = 15
      reads[name].value = 1
      reads[name].pressed = true
      reads[name].pulse = true
    end
  end
  context.pulses = {}

  return {
    reads = reads,
    eventCount = context.eventCount,
  }
end

function keyboard.pump(context)
  while not context.closed do
    local event, code = os.pullEvent()

    if event == "key" or event == "key_up" then
      local name = logicalKey(context, code)
      if name and isInput(context, name) then
        local down = event == "key"
        context.pressed[name] = down
        if down and isPulseInput(context, name) then
          context.pulses[name] = true
        end
        context.eventCount = (context.eventCount or 0) + 1
      end
    end
  end
end

function keyboard.describe(context)
  return {
    eventCount = context.eventCount or 0,
  }
end

return keyboard
