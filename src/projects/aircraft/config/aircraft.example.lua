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
    maxCorrection = 1.5,
    -- Desaturation shifts all rotor powers together when one corner would
    -- approach 0 or max, preserving pitch/roll authority while leaving
    -- a little room for redstone rounding.
    desaturate = true,
    desaturateHeadroom = 0.75,
    -- Tilt compensation adds bounded collective power for the requested
    -- pitch/roll target, roughly offsetting vertical lift lost to steering.
    tiltCompensation = true,
    tiltCompensationGain = 1,
    tiltCompensationMaxPower = 2,
    signalDither = true,
    brakeOnExit = true,
    reportFrameLimit = 600,
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
    -- source="side" reads a local computer redstone side.
    -- source="router" reads binding through a redstone_router coordinate.
    source = "side",
    side = "front",
    activeHigh = true,
    keyEnabled = true,
    key = "k",
    binding = nil,
  },
  controller = {
    enabled = false,
    -- redstone_router reads the existing Create controller link layout.
    -- keyboard consumes normal CraftOS key/key_up events from an onboard
    -- keyboard or Create: Avionics Linked Typewriter.
    type = "redstone_router",
    threshold = 1,
    -- hold: space/shift adjust a retained throttle offset.
    -- momentary: space/shift only add power while held.
    throttleMode = "hold",
    throttlePower = 1,
    axis1TargetDeg = 5,
    axis2TargetDeg = 5,
    axis1Power = 0,
    axis2Power = 0,
    targetSlewDegPerSecond = 8,
    throttleSlewPowerPerSecond = 4,
    -- Default Create controller link layout from the bottom-left shift key:
    -- keyboard view is W over shift A S D space.
    -- Each coord points at the block under the Redstone Link; read its up face.
    bindings = {
      shift = { x = 3, y = -1, z = -5, side = "up" },
      a = { x = 2, y = -1, z = -5, side = "up" },
      s = { x = 1, y = -1, z = -5, side = "up" },
      d = { x = 0, y = -1, z = -5, side = "up" },
      space = { x = -1, y = -1, z = -5, side = "up" },
      w = { x = 1, y = -1, z = -4, side = "up" },
    },
  },

  reportPath = "/aircraft_scan.txt",
  sendWebhook = true,
}
