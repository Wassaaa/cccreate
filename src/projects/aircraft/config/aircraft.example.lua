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

  -- Leave unset for automatic side-based orientation, or set explicit aircraft
  -- axes with labels such as "+Z" and "+X". For the first test craft, the
  -- computer back side is aircraft front, so frontAxis="+Z", leftAxis="+X".
  frontAxis = nil,
  leftAxis = nil,

  -- Future control safety defaults. V1 scan mode does not actuate anything.
  dryRun = true,
  absoluteSignalMax = 15,
  brakeSignal = 15,
  maxAttitudeDelta = 2,
  statusReadLimit = 8,
  level = nil,
  stabilize = {
    interval = 0.1,
    seconds = 1,
    basePower = 0,
    axis1Kp = 0.08,
    axis2Kp = 0.08,
    axis1Kd = 0.08,
    axis2Kd = 0.08,
    axis1Sign = 1,
    axis2Sign = 1,
    brakeOnExit = true,
  },

  reportPath = "/aircraft_scan.txt",
  statusReportPath = "/aircraft_status.txt",
  actuatorReportPath = "/aircraft_actuator_test.txt",
  stabilizeReportPath = "/aircraft_stabilize.txt",
  sendWebhook = true,
}
