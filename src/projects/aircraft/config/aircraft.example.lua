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

  -- Control defaults. Commands still require --apply and dryRun=false before
  -- they write actuator outputs.
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
    axis1Kp = 4,
    axis2Kp = 4,
    axis1Kd = 0.12,
    axis2Kd = 0.2,
    axis1Sign = -1,
    axis2Sign = 1,
    maxCorrection = 1.5,
    brakeOnExit = true,
  },
  display = {
    enabled = true,
    stabilizeEnabled = false,
    stabilizeInterval = 0.5,
  },
  hud = {
    enabled = true,
    interval = 0.5,
    monitorScale = 0.5,
    monitorName = nil,
  },

  reportPath = "/aircraft_scan.txt",
  statusReportPath = "/aircraft_status.txt",
  actuatorReportPath = "/aircraft_actuator_test.txt",
  stabilizeReportPath = "/aircraft_stabilize.txt",
  displayReportPath = "/aircraft_displays.txt",
  sendWebhook = true,
}
