local reporter = require("lib.reporter")

local unpackArgs = table.unpack or unpack
local args = { ... }

local command = table.remove(args, 1)

if not command then
  print("Usage: ccwrap <program-path> [args...]")
  return
end

local function makeMirrorTerm(parent)
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
    parent.write(text)
  end

  function mirror.blit(text, textColors, backgroundColors)
    ensureLine(cursorY)
    lines[cursorY] = lines[cursorY] .. tostring(text)
    cursorX = cursorX + #tostring(text)

    if parent.blit then
      parent.blit(text, textColors, backgroundColors)
    else
      parent.write(text)
    end
  end

  function mirror.clear()
    lines = { "" }
    cursorX = 1
    cursorY = 1
    parent.clear()
  end

  function mirror.clearLine()
    ensureLine(cursorY)
    lines[cursorY] = ""
    cursorX = 1
    parent.clearLine()
  end

  function mirror.getCursorPos()
    return cursorX, cursorY
  end

  function mirror.setCursorPos(x, y)
    cursorX = x
    cursorY = y
    ensureLine(cursorY)
    parent.setCursorPos(x, y)
  end

  function mirror.getSize()
    return parent.getSize()
  end

  function mirror.scroll(amount)
    for _ = 1, amount do
      table.remove(lines, 1)
      table.insert(lines, "")
    end
    parent.scroll(amount)
  end

  function mirror.setTextColor(color)
    parent.setTextColor(color)
  end

  function mirror.setTextColour(color)
    parent.setTextColour(color)
  end

  function mirror.setBackgroundColor(color)
    parent.setBackgroundColor(color)
  end

  function mirror.setBackgroundColour(color)
    parent.setBackgroundColour(color)
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
local mirror, lines = makeMirrorTerm(parent)
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
  output = table.concat(lines, "\n"),
}

if not ok then
  report.error = tostring(result)
  print("Wrapped command failed: " .. report.error)
end

reporter.send(report)
