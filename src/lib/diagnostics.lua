local diagnostics = {}

local function now()
  return os.date("%Y-%m-%d %H:%M:%S")
end

local function isTurtle()
  return type(turtle) == "table"
end

local function collectFiles(path, results)
  results = results or {}

  if not fs.exists(path) then
    return results
  end

  if not fs.isDir(path) then
    table.insert(results, path)
    return results
  end

  for _, name in ipairs(fs.list(path)) do
    collectFiles(fs.combine(path, name), results)
  end

  return results
end

local function collectInventory()
  local items = {}

  if not isTurtle() then
    return items
  end

  for slot = 1, 16 do
    local item = turtle.getItemDetail(slot)
    if item then
      table.insert(items, {
        slot = slot,
        name = item.name,
        count = item.count,
        damage = item.damage,
      })
    end
  end

  return items
end

local function baseReport(kind)
  return {
    kind = kind,
    createdAt = now(),
    computerId = os.getComputerID(),
    label = os.getComputerLabel(),
    isTurtle = isTurtle(),
    fuelLevel = isTurtle() and turtle.getFuelLevel() or nil,
    fuelLimit = isTurtle() and turtle.getFuelLimit() or nil,
    files = collectFiles("/"),
    inventory = collectInventory(),
  }
end

local function makeCaptureTerm(parent)
  local lines = { "" }
  local cursorX = 1
  local cursorY = 1
  local width, height = parent.getSize()

  local function ensureLine(y)
    while #lines < y do
      table.insert(lines, "")
    end
  end

  local capture = {}

  function capture.write(text)
    text = tostring(text)
    ensureLine(cursorY)

    local line = lines[cursorY]
    lines[cursorY] = line .. text
    cursorX = cursorX + #text
  end

  function capture.blit(text)
    capture.write(text)
  end

  function capture.clear()
    lines = { "" }
    cursorX = 1
    cursorY = 1
  end

  function capture.clearLine()
    ensureLine(cursorY)
    lines[cursorY] = ""
    cursorX = 1
  end

  function capture.getCursorPos()
    return cursorX, cursorY
  end

  function capture.setCursorPos(x, y)
    cursorX = x
    cursorY = y
    ensureLine(cursorY)
  end

  function capture.getSize()
    return width, height
  end

  function capture.scroll(amount)
    for _ = 1, amount do
      table.remove(lines, 1)
      table.insert(lines, "")
    end
  end

  function capture.setTextColor() end
  function capture.setTextColour() end
  function capture.setBackgroundColor() end
  function capture.setBackgroundColour() end
  function capture.getTextColor()
    return colors.white
  end
  function capture.getTextColour()
    return colors.white
  end
  function capture.getBackgroundColor()
    return colors.black
  end
  function capture.getBackgroundColour()
    return colors.black
  end
  function capture.isColor()
    return parent.isColor()
  end
  function capture.isColour()
    return parent.isColour()
  end

  return capture, lines
end

function diagnostics.systemReport()
  return baseReport("system")
end

function diagnostics.noteReport(message)
  local report = baseReport("note")
  report.message = message
  return report
end

function diagnostics.commandReport(command)
  local report = baseReport("command")
  report.command = command

  if command == "" then
    report.ok = false
    report.error = "No command given"
    return report
  end

  local parent = term.current()
  local capture, lines = makeCaptureTerm(parent)
  term.redirect(capture)

  local ok, result = pcall(shell.run, command)

  term.redirect(parent)

  report.ok = ok and result
  report.output = table.concat(lines, "\n")

  if not ok then
    report.error = tostring(result)
  end

  return report
end

return diagnostics
