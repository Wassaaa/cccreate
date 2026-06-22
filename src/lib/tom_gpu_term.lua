local gpuTerm = {}

local DEFAULT_PALETTE = {
  [colors.white] = 0xFFF0F0F0,
  [colors.orange] = 0xFFF2B233,
  [colors.magenta] = 0xFFE57FD8,
  [colors.lightBlue] = 0xFF99B2F2,
  [colors.yellow] = 0xFFDEDE6C,
  [colors.lime] = 0xFF7FCC19,
  [colors.pink] = 0xFFF2B2CC,
  [colors.gray] = 0xFF4C4C4C,
  [colors.lightGray] = 0xFF999999,
  [colors.cyan] = 0xFF4C99B2,
  [colors.purple] = 0xFFB266E5,
  [colors.blue] = 0xFF3366CC,
  [colors.brown] = 0xFF7F664C,
  [colors.green] = 0xFF57A64E,
  [colors.red] = 0xFFCC4C4C,
  [colors.black] = 0xFF111111,
}

local function copyPalette(source)
  local palette = {}

  for color, value in pairs(source) do
    palette[color] = value
  end

  return palette
end

local function blitToColor(hex)
  local index = tonumber(hex, 16)

  if not index then
    return colors.white
  end

  return 2 ^ index
end

local function packArgb(r, g, b)
  if g == nil and b == nil then
    if r <= 0xFFFFFF then
      return 0xFF000000 + r
    end

    return r
  end

  if r <= 1 and g <= 1 and b <= 1 then
    r = math.floor(r * 255 + 0.5)
    g = math.floor(g * 255 + 0.5)
    b = math.floor(b * 255 + 0.5)
  end

  return 0xFF000000 + r * 0x10000 + g * 0x100 + b
end

local function unpackArgb(value)
  if value >= 0x1000000 then
    value = value - 0xFF000000
  end

  local r = math.floor(value / 0x10000) % 0x100
  local g = math.floor(value / 0x100) % 0x100
  local b = value % 0x100

  return r / 255, g / 255, b / 255
end

local function normalizeOptions(options)
  options = options or {}

  local scale = tonumber(options.scale) or 1
  if scale <= 0 then
    error("scale must be greater than zero", 2)
  end

  return {
    width = math.floor(tonumber(options.width) or 32),
    height = math.floor(tonumber(options.height) or 16),
    scale = scale,
    palette = copyPalette(options.palette or DEFAULT_PALETTE),
    sync = options.sync or function() end,
  }
end

function gpuTerm.create(gpu, options)
  if type(gpu) ~= "table" then
    error("expected Tom's GPU object", 2)
  end

  local config = normalizeOptions(options)
  local charW = math.max(1, math.ceil(config.scale * 6))
  local charH = math.max(1, math.ceil(config.scale * 9))
  local cursorX = 1
  local cursorY = 1
  local cursorBlink = false
  local textColor = colors.white
  local backgroundColor = colors.black
  local buffer = {}
  local drawn = {}
  local autoUpdate = false
  local cursorDrawn = false
  local cursorDrawnX = 1
  local cursorDrawnY = 1

  local function blankCell()
    return {
      char = " ",
      fg = textColor,
      bg = backgroundColor,
    }
  end

  local function resetBuffer(target)
    for y = 1, config.height do
      target[y] = {}

      for x = 1, config.width do
        target[y][x] = blankCell()
      end
    end
  end

  resetBuffer(buffer)
  resetBuffer(drawn)

  local function onScreen(x, y)
    return x >= 1 and x <= config.width and y >= 1 and y <= config.height
  end

  local function cellEquals(a, b)
    return a.char == b.char and a.fg == b.fg and a.bg == b.bg
  end

  local function copyCell(cell)
    return {
      char = cell.char,
      fg = cell.fg,
      bg = cell.bg,
    }
  end

  local function drawCell(x, y, cell)
    local px = (x - 1) * charW + 1
    local py = (y - 1) * charH + 1
    local fg = config.palette[cell.fg] or config.palette[colors.white]
    local bg = config.palette[cell.bg] or config.palette[colors.black]

    gpu.filledRectangle(px, py, charW, charH, bg)

    if cell.char ~= " " then
      local textWidth = charW

      if type(gpu.getTextLength) == "function" then
        local ok, width = pcall(gpu.getTextLength, cell.char, config.scale)
        if ok and type(width) == "number" then
          textWidth = width
        end
      end

      local tx = px + math.max(0, math.floor((charW - textWidth) / 2))
      gpu.drawText(tx, py, cell.char, fg, -1, config.scale)
    end
  end

  local function redrawCell(x, y)
    if onScreen(x, y) then
      drawCell(x, y, buffer[y][x])
      drawn[y][x] = copyCell(buffer[y][x])
    end
  end

  local function eraseCursor()
    if cursorDrawn and onScreen(cursorDrawnX, cursorDrawnY) then
      redrawCell(cursorDrawnX, cursorDrawnY)
      cursorDrawn = false
    end
  end

  local function drawCursor()
    if not onScreen(cursorX, cursorY) then
      return
    end

    local px = (cursorX - 1) * charW + 1
    local py = (cursorY - 1) * charH + charH
    local fg = config.palette[textColor] or config.palette[colors.white]

    gpu.filledRectangle(px, py, math.max(1, charW - 1), math.max(1, math.ceil(config.scale)), fg)
    cursorDrawn = true
    cursorDrawnX = cursorX
    cursorDrawnY = cursorY
  end

  local function sync()
    config.sync()
  end

  local function drawAll()
    eraseCursor()

    for y = 1, config.height do
      for x = 1, config.width do
        redrawCell(x, y)
      end
    end

    sync()
  end

  local redirect = {}
  local instance = {
    term = redirect,
  }

  local function changedDraw(x, y)
    if not onScreen(x, y) then
      return
    end

    if not cellEquals(buffer[y][x], drawn[y][x]) then
      redrawCell(x, y)
    end
  end

  function redirect.write(value)
    value = tostring(value)
    eraseCursor()

    for i = 1, #value do
      local x = cursorX + i - 1

      if onScreen(x, cursorY) then
        buffer[cursorY][x] = {
          char = value:sub(i, i),
          fg = textColor,
          bg = backgroundColor,
        }

        if autoUpdate then
          changedDraw(x, cursorY)
        end
      end
    end

    cursorX = cursorX + #value

    if autoUpdate then
      sync()
    end
  end

  function redirect.blit(text, textColors, backgroundColors)
    text = tostring(text)
    textColors = tostring(textColors)
    backgroundColors = tostring(backgroundColors)

    if #textColors ~= #text or #backgroundColors ~= #text then
      error("Arguments must be the same length", 2)
    end

    eraseCursor()

    for i = 1, #text do
      local x = cursorX + i - 1

      if onScreen(x, cursorY) then
        buffer[cursorY][x] = {
          char = text:sub(i, i),
          fg = blitToColor(textColors:sub(i, i)),
          bg = blitToColor(backgroundColors:sub(i, i)),
        }

        if autoUpdate then
          changedDraw(x, cursorY)
        end
      end
    end

    cursorX = cursorX + #text

    if autoUpdate then
      sync()
    end
  end

  function redirect.clear()
    eraseCursor()

    for y = 1, config.height do
      for x = 1, config.width do
        buffer[y][x] = blankCell()
      end
    end

    if autoUpdate then
      gpu.fill(config.palette[backgroundColor] or config.palette[colors.black])
      resetBuffer(drawn)
      drawAll()
    end
  end

  function redirect.clearLine()
    eraseCursor()

    if not onScreen(1, cursorY) then
      return
    end

    for x = 1, config.width do
      buffer[cursorY][x] = blankCell()

      if autoUpdate then
        changedDraw(x, cursorY)
      end
    end

    if autoUpdate then
      sync()
    end
  end

  function redirect.scroll(lines)
    lines = math.floor(tonumber(lines) or 0)

    if lines == 0 then
      return
    end

    eraseCursor()

    local nextBuffer = {}

    for y = 1, config.height do
      nextBuffer[y] = {}

      for x = 1, config.width do
        local sourceY = y + lines

        if sourceY >= 1 and sourceY <= config.height then
          nextBuffer[y][x] = copyCell(buffer[sourceY][x])
        else
          nextBuffer[y][x] = blankCell()
        end
      end
    end

    buffer = nextBuffer

    if autoUpdate then
      drawAll()
    end
  end

  function redirect.getCursorPos()
    return cursorX, cursorY
  end

  function redirect.setCursorPos(x, y)
    eraseCursor()
    cursorX = math.floor(tonumber(x) or 1)
    cursorY = math.floor(tonumber(y) or 1)
  end

  function redirect.getCursorBlink()
    return cursorBlink
  end

  function redirect.setCursorBlink(blink)
    cursorBlink = not not blink

    if not cursorBlink then
      eraseCursor()
      sync()
    end
  end

  function redirect.getSize()
    return config.width, config.height
  end

  function redirect.getTextColor()
    return textColor
  end
  redirect.getTextColour = redirect.getTextColor

  function redirect.setTextColor(color)
    textColor = color
  end
  redirect.setTextColour = redirect.setTextColor

  function redirect.getBackgroundColor()
    return backgroundColor
  end
  redirect.getBackgroundColour = redirect.getBackgroundColor

  function redirect.setBackgroundColor(color)
    backgroundColor = color
  end
  redirect.setBackgroundColour = redirect.setBackgroundColor

  function redirect.isColor()
    return true
  end
  redirect.isColour = redirect.isColor

  function redirect.getPaletteColor(color)
    return unpackArgb(config.palette[color] or DEFAULT_PALETTE[color] or DEFAULT_PALETTE[colors.white])
  end
  redirect.getPaletteColour = redirect.getPaletteColor

  function redirect.setPaletteColor(color, r, g, b)
    config.palette[color] = packArgb(r, g, b)
  end
  redirect.setPaletteColour = redirect.setPaletteColor

  function redirect.nativePaletteColor(color)
    return unpackArgb(DEFAULT_PALETTE[color] or DEFAULT_PALETTE[colors.white])
  end
  redirect.nativePaletteColour = redirect.nativePaletteColor

  function redirect.restoreCursor()
    if cursorBlink then
      drawCursor()
      sync()
    end
  end

  function redirect.flush()
    for y = 1, config.height do
      for x = 1, config.width do
        changedDraw(x, y)
      end
    end

    sync()
  end

  function instance.autoUpdate()
    autoUpdate = true
  end

  function instance.manualUpdate()
    autoUpdate = false
  end

  function instance.sync()
    redirect.flush()
  end

  function instance.tick(switchVisible)
    if not cursorBlink then
      if cursorDrawn then
        eraseCursor()
        sync()
      end

      return
    end

    if switchVisible then
      if cursorDrawn then
        eraseCursor()
      else
        drawCursor()
      end

      sync()
    elseif cursorDrawn and (cursorDrawnX ~= cursorX or cursorDrawnY ~= cursorY) then
      eraseCursor()
      drawCursor()
      sync()
    end
  end

  function instance.mapPixel(x, y)
    return math.floor((x - 1) / charW + 1), math.floor((y - 1) / charH + 1)
  end

  function instance.getCharSize()
    return charW, charH
  end

  return instance
end

return gpuTerm
