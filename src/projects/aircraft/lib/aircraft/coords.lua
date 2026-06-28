local coords = {}

local function parseInteger(value, fallback)
  local number = tonumber(value)
  if not number or number ~= math.floor(number) then
    return fallback
  end

  return number
end

function coords.scanBounds(config)
  local scan = config.scan or config
  local xRadius = math.max(0, parseInteger(scan.xRadius, 8))
  local yRadius = math.max(0, parseInteger(scan.yRadius, 2))
  local zRadius = math.max(0, parseInteger(scan.zRadius, 8))

  return {
    xMin = -xRadius,
    xMax = xRadius,
    yMin = -yRadius,
    yMax = yRadius,
    zMin = -zRadius,
    zMax = zRadius,
    xRadius = xRadius,
    yRadius = yRadius,
    zRadius = zRadius,
  }
end

function coords.boundsLabel(bounds)
  if not bounds then
    return "unknown"
  end

  return "x "
    .. tostring(bounds.xMin)
    .. ".."
    .. tostring(bounds.xMax)
    .. ", y "
    .. tostring(bounds.yMin)
    .. ".."
    .. tostring(bounds.yMax)
    .. ", z "
    .. tostring(bounds.zMin)
    .. ".."
    .. tostring(bounds.zMax)
end

function coords.key(x, y, z)
  return tostring(x) .. "," .. tostring(y) .. "," .. tostring(z)
end

function coords.label(coord)
  if not coord then
    return "unknown"
  end

  return "(" .. tostring(coord.x) .. "," .. tostring(coord.y) .. "," .. tostring(coord.z) .. ")"
end

function coords.iterate(bounds, visit)
  for y = bounds.yMin, bounds.yMax do
    for z = bounds.zMin, bounds.zMax do
      for x = bounds.xMin, bounds.xMax do
        visit(x, y, z)
      end
    end
  end
end

return coords
