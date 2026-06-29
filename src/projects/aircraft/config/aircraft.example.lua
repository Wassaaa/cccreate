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
  stabilize = {
    interval = 0.1,
    seconds = 1,
    basePower = 0,
    axis1Kp = 4,
    axis2Kp = 4,
    axis1Kd = 0.12,
    axis2Kd = 0.2,
    axis1Trim = 0,
    axis2Trim = 0,
    yawKd = 0.2,
    yawTrim = 0,
    yawSign = 1,
    maxCorrection = 1.5,
    maxYawCorrection = 1.5,
    signalDither = true,
    brakeOnExit = true,
    reportFrameLimit = 600,
  },
  rotors = {
    -- Empty handedness means "use the values discovered by aircraft scan".
    -- Set a role here only when you want to override the scanned baseline.
    applyHandednessOnStabilize = true,
    handedness = {},
  },
  display = {
    enabled = true,
    stabilizeEnabled = true,
    stabilizeInterval = 1,
  },
  hud = {
    enabled = true,
    interval = 0.5,
    monitorScale = 0.5,
    monitorName = nil,
  },
  killSwitch = {
    enabled = false,
    side = "front",
    activeHigh = true,
  },
  controller = {
    enabled = false,
    threshold = 1,
    throttlePower = 1,
    axis1TargetDeg = 5,
    axis2TargetDeg = 5,
    axis1Power = 0,
    axis2Power = 0,
    yawPower = 1,
    targetSlewDegPerSecond = 8,
    throttleSlewPowerPerSecond = 4,
    -- Default Create controller link layout from the first lower-row block:
    -- keyboard view is Q W E over A S D, with space and shift on the lower row.
    -- Each coord points at the block under the Redstone Link; read its up face.
    bindings = {
      space = { x = -1, y = -1, z = -5, side = "up" },
      d = { x = 0, y = -1, z = -5, side = "up" },
      s = { x = 1, y = -1, z = -5, side = "up" },
      a = { x = 2, y = -1, z = -5, side = "up" },
      shift = { x = 3, y = -1, z = -5, side = "up" },
      q = { x = 2, y = -1, z = -4, side = "up" },
      w = { x = 1, y = -1, z = -4, side = "up" },
      e = { x = 0, y = -1, z = -4, side = "up" },
    },
  },

  reportPath = "/aircraft_scan.txt",
  sendWebhook = true,
}
