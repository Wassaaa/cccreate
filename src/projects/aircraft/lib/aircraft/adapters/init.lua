local adapters = {}

adapters.kinds = {
  "attitudeSensor",
  "scalarActuator",
  "vectorActuator",
  "rotorBearing",
  "statusSource",
}

function adapters.describe()
  return {
    version = 1,
    readOnly = true,
    note = "V1 only classifies capabilities. Active actuator adapters are added after live scans prove method names.",
    kinds = adapters.kinds,
  }
end

return adapters
