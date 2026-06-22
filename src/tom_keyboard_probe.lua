local unpackArgs = table.unpack or unpack
local args = { ... }

local config = {
  mode = "prefixed",
  duration = 20,
  router = true,
  routerX = -3,
  routerY = 0,
  routerZ = -1,
  direct = nil,
}

local function usage()
  print("tom_keyboard_probe [prefixed|native|observe] [seconds]")
  print("Options:")
  print("  --router <x> <y> <z>  default: -3 0 -1")
  print("  --direct <name>")
  print("")
  print("prefixed: setFireNativeEvents(false), expects tm_keyboard_*")
  print("native:   setFireNativeEvents(true), expects key/char directly")
  print("observe:  do not change keyboard event mode")
end

local function readNumber(value, name)
  local n = tonumber(value)

  if not n then
    error("Expected number for " .. name .. ", got " .. tostring(value), 0)
  end

  return n
end

local function parseArgs()
  local i = 1

  while i <= #args do
    local arg = args[i]

    if arg == "help" or arg == "--help" or arg == "-h" then
      usage()
      return false
    elseif arg == "prefixed" or arg == "native" or arg == "observe" then
      config.mode = arg
      i = i + 1
    elseif arg == "--router" then
      config.router = true
      config.direct = nil
      config.routerX = readNumber(args[i + 1], "--router x")
      config.routerY = readNumber(args[i + 2], "--router y")
      config.routerZ = readNumber(args[i + 3], "--router z")
      i = i + 4
    elseif arg == "--direct" then
      config.router = false
      config.direct = args[i + 1]

      if not config.direct then
        error("--direct needs a peripheral name", 0)
      end

      i = i + 2
    else
      config.duration = readNumber(arg, "seconds")
      i = i + 1
    end
  end

  return true
end

local function sortedFunctionNames(object)
  local names = {}

  for name, value in pairs(object or {}) do
    if type(value) == "function" then
      table.insert(names, name)
    end
  end

  table.sort(names)
  return names
end

local function callIfPresent(object, method, ...)
  if type(object[method]) ~= "function" then
    return false, "missing"
  end

  local results = { pcall(object[method], ...) }
  local ok = table.remove(results, 1)

  if ok then
    return true, unpackArgs(results)
  end

  return false, results[1]
end

local function wrapKeyboard()
  if config.router then
    local router = peripheral.find("peripheral_router")

    if router and type(router.wrap) == "function" then
      local ok, keyboard = pcall(router.wrap, config.routerX, config.routerY, config.routerZ)

      if ok and keyboard then
        return keyboard, "router(" .. config.routerX .. "," .. config.routerY .. "," .. config.routerZ .. ")"
      end
    end
  end

  if config.direct then
    local keyboard = peripheral.wrap(config.direct)

    if keyboard then
      return keyboard, config.direct
    end
  end

  local keyboard = peripheral.wrap("tm_keyboard_0")
  if keyboard then
    return keyboard, "tm_keyboard_0"
  end

  return nil, nil
end

local function valueToText(value)
  if type(value) == "string" then
    return string.format("%q", value)
  end

  return tostring(value)
end

local function printEvent(values)
  local parts = {}

  for i, value in ipairs(values) do
    parts[i] = valueToText(value)
  end

  print(table.concat(parts, " | "))
end

if not parseArgs() then
  return
end

local keyboard, source = wrapKeyboard()

print("Tom keyboard probe")
print("source: " .. tostring(source))
print("mode: " .. config.mode)
print("duration: " .. config.duration .. "s")

if keyboard then
  print("methods: " .. table.concat(sortedFunctionNames(keyboard), ", "))

  if config.mode == "prefixed" then
    local ok, result = callIfPresent(keyboard, "setFireNativeEvents", false)
    print("setFireNativeEvents(false): " .. tostring(ok) .. " " .. tostring(result or ""))
  elseif config.mode == "native" then
    local ok, result = callIfPresent(keyboard, "setFireNativeEvents", true)
    print("setFireNativeEvents(true): " .. tostring(ok) .. " " .. tostring(result or ""))
  end
else
  print("No keyboard object wrapped. Events may still show if another keyboard is linked.")
end

print("Open/activate Tom's keyboard now and type: abc ENTER")
print("Captured events:")

local timer = os.startTimer(config.duration)
local count = 0

while true do
  local values = { os.pullEventRaw() }
  local event = values[1]

  if event == "timer" and values[2] == timer then
    break
  end

  if event == "terminate" then
    printEvent(values)
    break
  end

  if event == "key"
    or event == "key_up"
    or event == "char"
    or event == "paste"
    or event == "tm_keyboard_key"
    or event == "tm_keyboard_key_up"
    or event == "tm_keyboard_char"
    or event == "tm_keyboard_paste"
    or event == "tm_keyboard_terminate"
    or event == "portable_connect"
    or event == "portable_disconnect"
    or event == "tm_keyboard_portable_connect"
    or event == "tm_keyboard_portable_disconnect" then
    count = count + 1
    printEvent(values)
  end
end

print("Event count: " .. count)
