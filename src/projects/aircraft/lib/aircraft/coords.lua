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

function coords.add(left, right)
  return {
    x = left.x + right.x,
    y = left.y + right.y,
    z = left.z + right.z,
  }
end

function coords.sub(left, right)
  return {
    x = left.x - right.x,
    y = left.y - right.y,
    z = left.z - right.z,
  }
end

function coords.neg(value)
  return {
    x = -value.x,
    y = -value.y,
    z = -value.z,
  }
end

function coords.dot(left, right)
  return left.x * right.x + left.y * right.y + left.z * right.z
end

function coords.cross(left, right)
  return {
    x = left.y * right.z - left.z * right.y,
    y = left.z * right.x - left.x * right.z,
    z = left.x * right.y - left.y * right.x,
  }
end

function coords.manhattan(left, right)
  return math.abs(left.x - right.x) + math.abs(left.y - right.y) + math.abs(left.z - right.z)
end

function coords.isCardinal(value)
  if not value then
    return false
  end

  local nonZero = 0

  if math.abs(value.x) == 1 and value.y == 0 and value.z == 0 then
    nonZero = nonZero + 1
  end

  if math.abs(value.y) == 1 and value.x == 0 and value.z == 0 then
    nonZero = nonZero + 1
  end

  if math.abs(value.z) == 1 and value.x == 0 and value.y == 0 then
    nonZero = nonZero + 1
  end

  return nonZero == 1
end

function coords.axisLabel(value)
  if not value then
    return "unknown"
  end

  if value.x == 1 and value.y == 0 and value.z == 0 then
    return "+X"
  elseif value.x == -1 and value.y == 0 and value.z == 0 then
    return "-X"
  elseif value.y == 1 and value.x == 0 and value.z == 0 then
    return "+Y"
  elseif value.y == -1 and value.x == 0 and value.z == 0 then
    return "-Y"
  elseif value.z == 1 and value.x == 0 and value.y == 0 then
    return "+Z"
  elseif value.z == -1 and value.x == 0 and value.y == 0 then
    return "-Z"
  end

  return coords.label(value)
end

function coords.parseAxis(value)
  if coords.isCardinal(value) then
    return {
      x = value.x,
      y = value.y,
      z = value.z,
    }
  end

  if type(value) ~= "string" then
    return nil
  end

  local normalized = string.upper(value)
  normalized = string.gsub(normalized, "%s+", "")

  if normalized == "X" or normalized == "+X" then
    return { x = 1, y = 0, z = 0 }
  elseif normalized == "-X" then
    return { x = -1, y = 0, z = 0 }
  elseif normalized == "Y" or normalized == "+Y" then
    return { x = 0, y = 1, z = 0 }
  elseif normalized == "-Y" then
    return { x = 0, y = -1, z = 0 }
  elseif normalized == "Z" or normalized == "+Z" then
    return { x = 0, y = 0, z = 1 }
  elseif normalized == "-Z" then
    return { x = 0, y = 0, z = -1 }
  end

  return nil
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
