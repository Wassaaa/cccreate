local baseReporter = require("lib.reporter")
local classify = require("lib.aircraft.classify")
local reportTabs = require("lib.aircraft.report_tabs")

local reporting = {}

reporting.CATEGORY_ORDER = classify.CATEGORY_ORDER

function reporting.decorate(report, config, options)
  return reportTabs.attach(report, config, options)
end

function reporting.save(report, path, config, options)
  if config then
    reporting.decorate(report, config, options)
  end

  return baseReporter.saveLocal(report, path)
end

function reporting.send(report)
  return baseReporter.send(report)
end

return reporting
