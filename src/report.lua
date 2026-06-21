local diagnostics = require("lib.diagnostics")
local reporter = require("lib.reporter")

local args = { ... }

local report

if args[1] == "run" then
  table.remove(args, 1)
  report = diagnostics.commandReport(table.concat(args, " "))
elseif args[1] == "note" then
  table.remove(args, 1)
  report = diagnostics.noteReport(table.concat(args, " "))
else
  report = diagnostics.systemReport()
end

print(textutils.serialize(report))
reporter.saveLocal(report, "report.txt")
reporter.send(report)
