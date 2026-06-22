local termEmu = require("lib.tom_term_emu")
local termFont = require("lib.tom_cc_term_font")

local unpackArgs = table.unpack or unpack
local rawArgs = { ... }

local config = {
  mode = "shell",
  router = true,
  routerX = -1,
  routerY = 1,
  routerZ = 0,
  direct = nil,
  gpuEvent = nil,
  keyboard = nil,
  keyboardRouter = true,
  keyboardRouterX = -3,
  keyboardRouterY = 0,
  keyboardRouterZ = -2,
  keyboardDirect = nil,
  keyboardMode = "native",
  resolution = 64,
  program = nil,
}

local function usage()
  print("tom_gpu_terminal [shell|multishell|demo]")
  print("tom_gpu_terminal run <program> [args...]")
  print("Options:")
  print("  --router <x> <y> <z>   default: -1 1 0")
  print("  --direct <name>        wrap GPU directly instead of router")
  print("  --gpu-event <name>     only map monitor events from this id")
  print("  --keyboard <name>      only map keyboard events from this source")
  print("  --keyboard-router <x> <y> <z>  default: -3 0 -2")
  print("  --keyboard-direct <name>")
  print("  --keyboard-native      use Tom native key/char events, default")
  print("  --keyboard-prefixed    map tm_keyboard_* events into key/char")
  print("  --keyboard-none        do not configure or map keyboard events")
  print("  --size <pixels>        per-block monitor size, default 64")
end

local function readNumber(value, name)
  local n = tonumber(value)

  if not n then
    error("Expected number for " .. name .. ", got " .. tostring(value), 0)
  end

  return n
end

local function copyRest(args, startIndex)
  local out = {}

  for i = startIndex, #args do
    table.insert(out, args[i])
  end

  return out
end

local function parseArgs(args)
  local i = 1

  while i <= #args do
    local arg = args[i]

    if arg == "help" or arg == "--help" or arg == "-h" then
      usage()
      return false
    elseif arg == "demo" then
      config.mode = "demo"
      i = i + 1
    elseif arg == "shell" then
      config.mode = "shell"
      config.program = { "shell" }
      i = i + 1
    elseif arg == "multishell" then
      config.mode = "shell"
      config.program = { "multishell" }
      i = i + 1
    elseif arg == "run" then
      config.mode = "run"
      config.program = copyRest(args, i + 1)

      if #config.program == 0 then
        error("run needs a program name", 0)
      end

      break
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
    elseif arg == "--gpu-event" then
      config.gpuEvent = args[i + 1]

      if not config.gpuEvent then
        error("--gpu-event needs a peripheral name", 0)
      end

      i = i + 2
    elseif arg == "--keyboard" then
      config.keyboard = args[i + 1]

      if not config.keyboard then
        error("--keyboard needs a peripheral name", 0)
      end

      i = i + 2
    elseif arg == "--keyboard-router" then
      config.keyboardRouter = true
      config.keyboardDirect = nil
      config.keyboardRouterX = readNumber(args[i + 1], "--keyboard-router x")
      config.keyboardRouterY = readNumber(args[i + 2], "--keyboard-router y")
      config.keyboardRouterZ = readNumber(args[i + 3], "--keyboard-router z")
      i = i + 4
    elseif arg == "--keyboard-direct" then
      config.keyboardRouter = false
      config.keyboardDirect = args[i + 1]

      if not config.keyboardDirect then
        error("--keyboard-direct needs a peripheral name", 0)
      end

      config.keyboard = config.keyboardDirect
      i = i + 2
    elseif arg == "--keyboard-native" then
      config.keyboardMode = "native"
      i = i + 1
    elseif arg == "--keyboard-prefixed" then
      config.keyboardMode = "prefixed"
      i = i + 1
    elseif arg == "--keyboard-none" then
      config.keyboardMode = "none"
      i = i + 1
    elseif arg == "--keyboard-mode" then
      local mode = args[i + 1]

      if mode ~= "native" and mode ~= "prefixed" and mode ~= "none" then
        error("--keyboard-mode must be native, prefixed, or none", 0)
      end

      config.keyboardMode = mode
      i = i + 2
    elseif arg == "--size" then
      config.resolution = readNumber(args[i + 1], "--size")
      i = i + 2
    else
      config.mode = "run"
      config.program = copyRest(args, i)
      break
    end
  end

  return true
end

local function wrapGpu()
  if config.router then
    local router = peripheral.find("peripheral_router")

    if router and type(router.wrap) == "function" then
      local ok, gpu = pcall(router.wrap, config.routerX, config.routerY, config.routerZ)

      if ok and gpu then
        return gpu, "router(" .. config.routerX .. "," .. config.routerY .. "," .. config.routerZ .. ")"
      end
    end
  end

  if config.direct then
    local gpu = peripheral.wrap(config.direct)

    if gpu then
      return gpu, config.direct
    end
  end

  local gpu = peripheral.wrap("tm_gpu_0")
  if gpu then
    return gpu, "tm_gpu_0"
  end

  error("No Tom's GPU found. Try --direct <name> or --router <x> <y> <z>.", 0)
end

local function callIfPresent(object, method, ...)
  if type(object[method]) ~= "function" then
    return nil
  end

  local ok, a, b, c = pcall(object[method], ...)

  if ok then
    return a, b, c
  end

  return nil
end

local function wrapKeyboard()
  if config.keyboardRouter then
    local router, routerName = peripheral.find("peripheral_router")

    if router and type(router.wrap) == "function" then
      local ok, keyboard = pcall(router.wrap, config.keyboardRouterX, config.keyboardRouterY, config.keyboardRouterZ)

      if ok and keyboard then
        if config.keyboardMode == "native" then
          callIfPresent(keyboard, "setFireNativeEvents", true)
        elseif config.keyboardMode == "prefixed" then
          callIfPresent(keyboard, "setFireNativeEvents", false)
        end

        if config.keyboardMode == "prefixed" and config.keyboard == nil and routerName then
          config.keyboard = routerName
        end

        return keyboard,
          "router(" .. config.keyboardRouterX .. "," .. config.keyboardRouterY .. "," .. config.keyboardRouterZ .. ")"
      end
    end
  end

  if config.keyboardDirect then
    local keyboard = peripheral.wrap(config.keyboardDirect)

    if keyboard then
      if config.keyboardMode == "native" then
        callIfPresent(keyboard, "setFireNativeEvents", true)
      elseif config.keyboardMode == "prefixed" then
        callIfPresent(keyboard, "setFireNativeEvents", false)
      end

      return keyboard, config.keyboardDirect
    end
  end

  return nil, nil
end

local function prepareGpu(gpu)
  callIfPresent(gpu, "refreshSize")
  callIfPresent(gpu, "setSize", config.resolution)
  sleep(0.25)
  callIfPresent(gpu, "refreshSize")
  callIfPresent(gpu, "fill", 0)

  local width, height = callIfPresent(gpu, "getSize")

  if not width or not height then
    error("GPU did not report a usable size", 0)
  end

  return width, height
end

local function charSize()
  return 6, 9
end

local function matchesPeripheral(filter, peripheralName)
  return filter == nil or filter == "any" or filter == peripheralName
end

local function queueMouse(eventName, button, x, y)
  os.queueEvent(eventName, button or 1, x, y)
end

local function pipeEvents(terminal)
  while true do
    local event, peripheralName, x, y, extra = os.pullEvent()

    if event == "tm_monitor_mouse_click" and matchesPeripheral(config.gpuEvent, peripheralName) then
      queueMouse("mouse_click", extra, terminal.mapPixel(x, y))
    elseif event == "tm_monitor_touch" and matchesPeripheral(config.gpuEvent, peripheralName) then
      queueMouse("mouse_click", 1, terminal.mapPixel(x, y))
      queueMouse("mouse_up", 1, terminal.mapPixel(x, y))
    elseif event == "tm_monitor_mouse_up" and matchesPeripheral(config.gpuEvent, peripheralName) then
      queueMouse("mouse_up", extra, terminal.mapPixel(x, y))
    elseif event == "tm_monitor_mouse_drag" and matchesPeripheral(config.gpuEvent, peripheralName) then
      queueMouse("mouse_drag", extra, terminal.mapPixel(x, y))
    elseif event == "tm_monitor_mouse_scroll" and matchesPeripheral(config.gpuEvent, peripheralName) then
      queueMouse("mouse_scroll", extra, terminal.mapPixel(x, y))
    elseif config.keyboardMode == "prefixed" and event == "tm_keyboard_key" and matchesPeripheral(config.keyboard, peripheralName) then
      os.queueEvent("key", x, y)
    elseif config.keyboardMode == "prefixed" and event == "tm_keyboard_key_up" and matchesPeripheral(config.keyboard, peripheralName) then
      os.queueEvent("key_up", x)
    elseif config.keyboardMode == "prefixed" and event == "tm_keyboard_char" and matchesPeripheral(config.keyboard, peripheralName) then
      os.queueEvent("char", x)
    elseif config.keyboardMode == "prefixed" and event == "tm_keyboard_paste" and matchesPeripheral(config.keyboard, peripheralName) then
      os.queueEvent("paste", x)
    elseif config.keyboardMode == "prefixed" and event == "tm_keyboard_terminate" and matchesPeripheral(config.keyboard, peripheralName) then
      os.queueEvent("terminate")
    end
  end
end

local function cursorLoop(terminal)
  local tick = 0

  while true do
    tick = tick + 1
    terminal.tick(tick % 8 == 0)
    sleep(0.1)
  end
end

local function runDemo(source, keyboardSource, pixelWidth, pixelHeight, termWidth, termHeight)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  print("Tom GPU terminal")
  print("source: " .. source)
  print("keyboard: " .. (keyboardSource or "computer"))
  print("key mode: " .. config.keyboardMode)
  print("key events: " .. (config.keyboard or "any"))
  print("font: bitmap")
  print("pixels: " .. pixelWidth .. "x" .. pixelHeight)
  print("chars: " .. termWidth .. "x" .. termHeight)
  print("")
  term.setTextColor(colors.lime)
  print("Bitmap font loaded.")
  term.setTextColor(colors.yellow)
  print("Ctrl+T exits.")
  term.setTextColor(colors.white)
  print("")
  print("Try:")
  print("tom_gpu_terminal run ls")
  print("tom_gpu_terminal multishell")

  while true do
    sleep(1)
  end
end

local function runConfiguredProgram(source, keyboardSource, pixelWidth, pixelHeight, termWidth, termHeight)
  if config.mode == "demo" then
    runDemo(source, keyboardSource, pixelWidth, pixelHeight, termWidth, termHeight)
    return
  end

  if config.program and #config.program > 0 then
    shell.run(unpackArgs(config.program))
    return
  end

  if not shell.run("multishell") then
    shell.run("shell")
  end
end

if not parseArgs(rawArgs) then
  return
end

local gpu, source = wrapGpu()
local keyboard, keyboardSource = wrapKeyboard()
local pixelWidth, pixelHeight = prepareGpu(gpu)
local charWidth, charHeight = charSize()
local termWidth = math.floor(pixelWidth / charWidth)
local termHeight = math.floor(pixelHeight / charHeight)

if termWidth < 5 or termHeight < 3 then
  error("Monitor is too small: " .. termWidth .. "x" .. termHeight, 0)
end

termFont.upload(gpu)

local terminal = termEmu.create(
  gpu,
  function()
    callIfPresent(gpu, "sync")
  end,
  termWidth,
  termHeight,
  true,
  1,
  "unicode_page_e0"
)

terminal.auto_update()

local oldTerm = term.redirect(terminal.term)
local ok, err = pcall(function()
  parallel.waitForAny(
    function()
      cursorLoop(terminal)
    end,
    function()
      pipeEvents(terminal)
    end,
    function()
      runConfiguredProgram(source, keyboardSource, pixelWidth, pixelHeight, termWidth, termHeight)
    end
  )
end)

term.redirect(oldTerm)
callIfPresent(gpu, "fill", 0)
callIfPresent(gpu, "sync")

if not ok then
  error(err, 0)
end
