local reporter = require("lib.reporter")

local unpackArgs = table.unpack or unpack
local args = { ... }
local quiet = false

if args[1] == "--quiet" then
  quiet = true
  table.remove(args, 1)
end

local command = table.remove(args, 1)

if not command then
  print("Usage: ccwrap [--quiet] <program-path> [args...]")
  return
end

local function makeCaptureTerm(parent, echo)
  local lines = { "" }
  local cursorX = 1
  local cursorY = 1

  local function ensureLine(y)
    while #lines < y do
      table.insert(lines, "")
    end
  end

  local mirror = {}

  function mirror.write(text)
    text = tostring(text)
    ensureLine(cursorY)
    lines[cursorY] = lines[cursorY] .. text
    cursorX = cursorX + #text
    if echo then
      parent.write(text)
    end
  end

  function mirror.blit(text, textColors, backgroundColors)
    ensureLine(cursorY)
    lines[cursorY] = lines[cursorY] .. tostring(text)
    cursorX = cursorX + #tostring(text)

    if echo then
      if parent.blit then
        parent.blit(text, textColors, backgroundColors)
      else
        parent.write(text)
      end
    end
  end

  function mirror.clear()
    lines = { "" }
    cursorX = 1
    cursorY = 1
    if echo then
      parent.clear()
    end
  end

  function mirror.clearLine()
    ensureLine(cursorY)
    lines[cursorY] = ""
    cursorX = 1
    if echo then
      parent.clearLine()
    end
  end

  function mirror.getCursorPos()
    return cursorX, cursorY
  end

  function mirror.setCursorPos(x, y)
    cursorX = x
    cursorY = y
    ensureLine(cursorY)
    if echo then
      parent.setCursorPos(x, y)
    end
  end

  function mirror.getSize()
    return parent.getSize()
  end

  function mirror.scroll(amount)
    for _ = 1, amount do
      table.remove(lines, 1)
      table.insert(lines, "")
    end
    if echo then
      parent.scroll(amount)
    end
  end

  function mirror.setTextColor(color)
    if echo then
      parent.setTextColor(color)
    end
  end

  function mirror.setTextColour(color)
    if echo then
      parent.setTextColour(color)
    end
  end

  function mirror.setBackgroundColor(color)
    if echo then
      parent.setBackgroundColor(color)
    end
  end

  function mirror.setBackgroundColour(color)
    if echo then
      parent.setBackgroundColour(color)
    end
  end

  function mirror.getTextColor()
    return parent.getTextColor()
  end

  function mirror.getTextColour()
    return parent.getTextColour()
  end

  function mirror.getBackgroundColor()
    return parent.getBackgroundColor()
  end

  function mirror.getBackgroundColour()
    return parent.getBackgroundColour()
  end

  function mirror.isColor()
    return parent.isColor()
  end

  function mirror.isColour()
    return parent.isColour()
  end

  return mirror, lines
end

local parent = term.current()
local mirror, lines = makeCaptureTerm(parent, not quiet)
local startedAt = os.date("%Y-%m-%d %H:%M:%S")

term.redirect(mirror)
local ok, result = pcall(shell.run, command, unpackArgs(args))
term.redirect(parent)
if not ok then
  term.redirect(parent)
end

local report = {
  kind = "wrapped-command",
  createdAt = os.date("%Y-%m-%d %H:%M:%S"),
  startedAt = startedAt,
  computerId = os.getComputerID(),
  label = os.getComputerLabel(),
  command = command,
  args = args,
  ok = ok and result,
  quiet = quiet,
  output = table.concat(lines, "\n"),
}

if not ok then
  report.error = tostring(result)
  print("Wrapped command failed: " .. report.error)
end

reporter.send(report)
