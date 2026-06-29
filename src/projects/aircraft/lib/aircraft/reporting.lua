local baseReporter = require("lib.reporter")
local classify = require("lib.aircraft.classify")
local reportTabs = require("lib.aircraft.report_tabs")

local reporting = {}

reporting.CATEGORY_ORDER = classify.CATEGORY_ORDER

function reporting.decorate(report, config, options)
  return reportTabs.attach(report, config, options)
end

function reporting.save(report, path, config, options)
  options = options or {}

  if config then
    reporting.decorate(report, config, options)
  end

  if options.localReport == false then
    if path and fs.exists(path) then
      local ok, deleteError = pcall(fs.delete, path)
      if not ok then
        print("Could not delete old local report " .. path .. ": " .. tostring(deleteError))
      end
    end

    print("Local report save skipped; webhook only.")
    return true
  end

  return baseReporter.saveLocal(report, path)
end

function reporting.send(report)
  return baseReporter.send(report)
end

return reporting
