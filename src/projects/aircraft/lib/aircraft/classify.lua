local classify = {}

local CATEGORY_ORDER = {
  "attitudeSensor",
  "scalarActuator",
  "vectorActuator",
  "rotorBearing",
  "kineticScada",
  "displaySink",
  "statusSource",
}

classify.CATEGORY_ORDER = CATEGORY_ORDER

local KINETIC_SCADA_METHODS = {
  "getSelfId",
  "getSourceId",
  "getSubnetworkAnchorId",
  "getNetworkId",
  "getKind",
  "getSpeed",
  "hasSource",
  "isOverstressed",
  "getStressImpact",
  "getStressContribution",
}

classify.KINETIC_SCADA_METHODS = KINETIC_SCADA_METHODS

local SAMPLE_METHODS = {
  "getSignal",
  "getShiftLevel",
  "getTransmissionMode",
  "getPower",
  "getThrust",
  "getThrustHandedness",
  "getTargetThrust",
  "getCurrentThrustPN",
  "getCurrentThrustKN",
  "getDisplayedThrustPN",
  "getDisplayedThrustKN",
  "getAirflowMs",
  "getObstruction",
  "getRpm",
  "getRPM",
  "getSpeed",
  "getTargetSpeed",
  "getGeneratedSpeed",
  "getOutputSpeed",
  "getStress",
  "getStressCapacity",
  "getSelfId",
  "getSourceId",
  "getSubnetworkAnchorId",
  "getNetworkId",
  "getKind",
  "hasSource",
  "isOverstressed",
  "getStressImpact",
  "getStressContribution",
  "getPitch",
  "getRoll",
  "getPitchRate",
  "getRollRate",
  "getAngularVelocityX",
  "getAngularVelocityY",
  "getAngularVelocityZ",
  "getGravityX",
  "getGravityY",
  "getGravityZ",
  "getAccelerationX",
  "getAccelerationY",
  "getAccelerationZ",
  "getVelocityX",
  "getVelocityY",
  "getVelocityZ",
  "getAltitude",
  "getAngle",
  "getTargetAngle",
  "getVectorX",
  "getVectorY",
  "getTargetVectorX",
  "getTargetVectorY",
  "getSize",
  "getCursorPos",
  "isColor",
  "isColour",
  "getSailCount",
  "getSailPower",
  "getEnergyAmountFe",
  "getEnergyCapacityFe",
  "getFuelAmount",
  "getFuelCapacity",
  "getFuelAmountMb",
  "getFuelCapacityMb",
  "getBurnTimeRemaining",
  "isBurning",
  "isActive",
  "isCustomThrustOutputActive",
}

classify.SAMPLE_METHODS = SAMPLE_METHODS

local function lower(value)
  return string.lower(tostring(value or ""))
end

local function containsName(methodSet, name)
  return methodSet[name] == true
end

local function containsAny(methodSet, names)
  for _, name in ipairs(names) do
    if containsName(methodSet, name) then
      return true
    end
  end

  return false
end

local function methodNameContains(methods, fragments)
  for _, method in ipairs(methods or {}) do
    local name = lower(method)

    for _, fragment in ipairs(fragments) do
      if string.find(name, fragment, 1, true) then
        return true
      end
    end
  end

  return false
end

local function toSet(values)
  local set = {}

  for _, value in ipairs(values or {}) do
    set[value] = true
  end

  return set
end

function classify.classifyMethods(methods)
  local methodSet = toSet(methods)
  local categories = {}
  local reasons = {}

  local function add(category, reason)
    categories[category] = true
    table.insert(reasons, category .. ": " .. reason)
  end

  if containsAny(methodSet, {
        "getPitch",
        "getRoll",
        "getPitchRate",
        "getRollRate",
        "getGravityX",
        "getAccelerationX",
      })
      or methodNameContains(methods, { "gimbal", "attitude", "gravity", "acceleration", "angular" }) then
    add("attitudeSensor", "attitude/gravity/rate getter methods")
  end

  if containsAny(methodSet, {
        "setSignal",
        "setPower",
        "setPowerNormalized",
        "setThrust",
        "setThrustNormalized",
        "setSpeed",
        "setShiftLevel",
        "setTargetSpeed",
      }) then
    add("scalarActuator", "scalar set method is present")
  elseif containsAny(methodSet, {
        "getSignal",
        "getPower",
        "getThrust",
        "getShiftLevel",
        "getTransmissionMode",
      }) then
    add("scalarActuator", "scalar readout method is present")
  end

  if containsAny(methodSet, {
        "setVector",
        "setVectorX",
        "setVectorY",
        "getVectorX",
        "getVectorY",
        "getTargetVectorX",
        "getTargetVectorY",
      }) then
    add("vectorActuator", "vector target/readout methods")
  end

  if methodNameContains(methods, { "propeller", "bearing", "sail", "airflow", "handedness" })
      or containsAny(methodSet, {
        "getAirflowMs",
        "getSailCount",
        "getSailPower",
        "getThrustHandedness",
        "setTargetAngle",
        "getTargetAngle",
        "getAngle",
      }) then
    add("rotorBearing", "propeller/bearing/airflow/angle methods")
  end

  if containsAny(methodSet, KINETIC_SCADA_METHODS) then
    add("kineticScada", "Create Avionics kinetic SCADA methods")
  end

  if containsAny(methodSet, {
        "setText",
        "setTextColor",
        "setTextColour",
      })
      or containsName(methodSet, "write")
      or (
        containsName(methodSet, "setCursorPos")
        and containsAny(methodSet, {
          "clear",
          "update",
          "getSize",
        })
      )
      or methodNameContains(methods, { "display", "monitor", "nixie", "textcolour", "textcolor" }) then
    add("displaySink", "display/text/terminal methods")
  end

  if containsAny(methodSet, {
        "getSpeed",
        "getRpm",
        "getRPM",
        "getStress",
        "getStressCapacity",
        "getFuelAmount",
        "getFuelCapacity",
        "getFuelAmountMb",
        "getFuelCapacityMb",
        "getEnergyAmountFe",
        "getEnergyCapacityFe",
        "getObstruction",
        "isBurning",
      }) then
    add("statusSource", "status/fuel/energy/stress/readout methods")
  end

  return categories, reasons
end

function classify.categoryList(categories)
  local list = {}

  for _, category in ipairs(CATEGORY_ORDER) do
    if categories and categories[category] then
      table.insert(list, category)
    end
  end

  return list
end

function classify.sampleMethodList(methods, limit)
  local methodSet = toSet(methods)
  local results = {}
  limit = tonumber(limit) or 12

  if limit <= 0 then
    return results
  end

  for _, method in ipairs(SAMPLE_METHODS) do
    if methodSet[method] then
      table.insert(results, method)
      if #results >= limit then
        break
      end
    end
  end

  return results
end

return classify
