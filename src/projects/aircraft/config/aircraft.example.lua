-- Copy to /config/aircraft.lua on the ComputerCraft computer when you want
-- persistent aircraft scan settings.
return {
  scan = {
    xRadius = 8,
    yRadius = 2,
    zRadius = 8,
    sampleLimit = 12,
    errorLimit = 12,
  },

  -- Leave unset until the first scan shows the real relative coordinates.
  frontAxis = nil,
  leftAxis = nil,

  -- Future control safety defaults. V1 scan mode does not actuate anything.
  dryRun = true,
  absoluteSignalMax = 10,
  maxAttitudeDelta = 2,
  statusReadLimit = 8,

  reportPath = "/aircraft_scan.txt",
  sendWebhook = true,
}
