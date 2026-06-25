local packageCrafter = require("package_crafter_core")

packageCrafter.run({
  args = { ... },
  programName = "package_crafter_prod",
  reporting = false,
})
