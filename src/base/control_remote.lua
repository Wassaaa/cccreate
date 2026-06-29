local args = { ... }

local INPUT_ORDER = {
  "w",
  "shift",
  "a",
  "s",
  "d",
  "space",
}

local GLFW_CODES = {
  [32] = "space",
  [65] = "a",
  [68] = "d",
  [83] = "s",
  [87] = "w",
  [340] = "shift",
  [344] = "shift",
}

local config = {
  protocol = "cc_control",
  targetId = nil,
  interval = 0.2,
}

local function usage()
  print("control_remote [protocol] [targetId]")
  print("Options:")
  print("  --protocol <name>  default cc_control")
  print("  --target <id>      send to one computer instead of broadcast")
  print("  --interval <sec>   state heartbeat interval, default 0.2")
end

local function parseNumber(value, label)
  local number = tonumber(value)
  if not number then
    error(label .. " must be a number", 0)
  end

  return number
end

local function parseArgs()
  local positional = {}
  local i = 1

  while i <= #args do
    local arg = args[i]

    if arg == "help" or arg == "--help" or arg == "-h" then
      usage()
      return false
    elseif arg == "--protocol" then
      config.protocol = tostring(args[i + 1] or "")
      if config.protocol == "" then
        error("--protocol needs a name", 0)
      end
      i = i + 2
    elseif arg == "--target" then
      config.targetId = parseNumber(args[i + 1], "--target")
      i = i + 2
    elseif arg == "--interval" then
      config.interval = parseNumber(args[i + 1], "--interval")
      if config.interval <= 0 then
        error("--interval must be greater than zero", 0)
      end
      i = i + 2
    else
      table.insert(positional, arg)
      i = i + 1
    end
  end

  if positional[1] then
    local target = tonumber(positional[1])
    if target then
      config.targetId = target
    else
      config.protocol = tostring(positional[1])
    end
  end

  if positional[2] then
    config.targetId = parseNumber(positional[2], "targetId")
  end

  return true
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
  if type(rednet.isOpen) == "function" then
    local ok, isOpen = pcall(rednet.isOpen, name)
    if ok and isOpen then
      return true
    end
  end

  local ok = pcall(rednet.open, name)
  return ok == true
end

local function openRednet()
  if type(rednet) ~= "table" or type(rednet.open) ~= "function" then
    error("rednet is unavailable on this computer", 0)
  end

  local opened = {}

  for _, name in ipairs(peripheral.getNames()) do
    if isModem(name) and openRednetOn(name) then
      table.insert(opened, name)
    end
  end

  if #opened == 0 then
    error("No modem found. Attach a wired or wireless modem to this computer.", 0)
  end

  return opened
end

local function addKeyConstant(codes, name, logical)
  if type(keys) == "table" and keys[name] ~= nil then
    codes[keys[name]] = logical
  end
end

local function keyCodes()
  local codes = {}

  for code, logical in pairs(GLFW_CODES) do
    codes[code] = logical
  end

  addKeyConstant(codes, "w", "w")
  addKeyConstant(codes, "a", "a")
  addKeyConstant(codes, "s", "s")
  addKeyConstant(codes, "d", "d")
  addKeyConstant(codes, "space", "space")
  addKeyConstant(codes, "leftShift", "shift")
  addKeyConstant(codes, "rightShift", "shift")

  return codes
end

local function normalizeName(name)
  if name == nil then
    return nil
  end

  local text = tostring(name)
  if text == "leftShift" or text == "rightShift" or text == "left_shift" or text == "right_shift" then
    return "shift"
  elseif text == " " then
    return "space"
  elseif #text == 1 then
    return string.lower(text)
  end

  return string.lower(text)
end

local function logicalKey(codes, code)
  local name = nil
  if type(keys) == "table" and type(keys.getName) == "function" then
    local ok, value = pcall(keys.getName, code)
    if ok then
      name = value
    end
  end

  return codes[code] or normalizeName(name) or GLFW_CODES[code]
end

local function isInput(name)
  for _, input in ipairs(INPUT_ORDER) do
    if input == name then
      return true
    end
  end

  return false
end

local function send(message)
  if config.targetId then
    rednet.send(config.targetId, message, config.protocol)
  else
    rednet.broadcast(message, config.protocol)
  end
end

local function draw(pressed, seq, opened)
  term.clear()
  term.setCursorPos(1, 1)
  print("Control remote")
  print("protocol=" .. tostring(config.protocol) .. " target=" .. tostring(config.targetId or "broadcast"))
  print("modems=" .. table.concat(opened, ","))
  print("seq=" .. tostring(seq))
  print("")
  print("Hold W/A/S/D, Space, Shift. Ctrl+T exits.")
  print("")

  for _, key in ipairs(INPUT_ORDER) do
    print((pressed[key] and "[x] " or "[ ] ") .. key)
  end
end

if not parseArgs() then
  return
end

local opened = openRednet()
local codes = keyCodes()
local pressed = {}
local seq = 0
local timer = os.startTimer(config.interval)

draw(pressed, seq, opened)

while true do
  local event, first = os.pullEventRaw()

  if event == "terminate" then
    seq = seq + 1
    send({
      kind = "control_state",
      seq = seq,
      pressed = {},
    })
    print("Released controls and stopped.")
    break
  elseif event == "timer" and first == timer then
    seq = seq + 1
    send({
      kind = "control_state",
      seq = seq,
      pressed = pressed,
    })
    draw(pressed, seq, opened)
    timer = os.startTimer(config.interval)
  elseif event == "key" or event == "key_up" then
    local key = logicalKey(codes, first)
    if key and isInput(key) then
      local down = event == "key"
      if pressed[key] ~= down then
        pressed[key] = down or nil
        seq = seq + 1
        send({
          kind = "control",
          seq = seq,
          key = key,
          down = down,
        })
        draw(pressed, seq, opened)
      end
    end
  end
end
