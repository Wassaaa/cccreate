local baseReporter = require("lib.reporter")
local classify = require("lib.aircraft.classify")

local reporting = {}

reporting.CATEGORY_ORDER = classify.CATEGORY_ORDER

function reporting.save(report, path)
  return baseReporter.saveLocal(report, path)
end

function reporting.send(report)
  return baseReporter.send(report)
end

return reporting
