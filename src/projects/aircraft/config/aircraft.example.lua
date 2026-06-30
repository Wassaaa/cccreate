-- Copy to /config/aircraft.lua on the ComputerCraft computer when you want
-- persistent aircraft scan settings.
return {
  scan = {
    xRadius = 8,
    yRadius = 2,
    zRadius = 8,
    sampleLimit = 12,
    errorLimit = 12,
    -- Worker count for routed scan calls. 1 keeps legacy sequential scans.
    parallelism = 32,
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
  actuator = {
    -- redstone_signal keeps the current analog-transmission path.
    -- rotation_speed uses native RPM mixer gains and writes setTargetSpeed on
    -- speedActuator role devices discovered by scan.
    type = "redstone_signal",
    redstoneSignal = {
      roleFamily = "scalarActuator",
      setter = "setSignal",
      getter = "getSignal",
    },
    rotationSpeed = {
      roleFamily = "speedActuator",
      setter = "setTargetSpeed",
      getter = "getTargetSpeed",
      idleRpm = 0,
      powerRpm = 256,
      brakeRpm = 0,
      minRpm = -256,
      maxRpm = 256,
      sign = 1,
      -- Auto role signs infer per-corner RPM polarity from speed-controller
      -- and rotor-bearing geometry in the scan. Override with roleSigns if a
      -- drivetrain has an extra gear reversal.
      autoRoleSigns = true,
      roleSigns = nil,
      -- Keep false for fine Create Rotation Speed Controller targets. Set
      -- true only for a future block that rejects fractional RPM values.
      round = false,
      -- Native RPM control. These are independent from stabilize.basePower,
      -- stabilize.axis*Kp, stabilize.axis*Kd, and stabilize.maxCorrection,
      -- which are retained for the redstone_signal backend.
      baseRpm = 0,
      throttleRpmPerPower = 16,
      axis1KpRpm = 0,
      axis1KdRpm = 0,
      axis2KpRpm = 0,
      axis2KdRpm = 0,
      axis1TrimRpm = 0,
      axis2TrimRpm = 0,
      -- 0 means no correction cap; use a positive value while tuning.
      maxCorrectionRpm = 0,
      -- Local unsigned target range before sign/roleSign polarity is applied.
      minTargetRpm = 0,
      maxTargetRpm = 256,
      -- Optional RPM headroom override for stabilize.desaturate in
      -- rotation_speed mode. nil derives it from desaturateHeadroom and
      -- throttleRpmPerPower.
      desaturateHeadroomRpm = nil,
      -- setTargetSpeed yields until the next server tick, so avoid rewriting
      -- identical targets every control frame.
      writeInterval = 0.1,
      writeDeadbandRpm = 0.5,
    },
  },
  maxAttitudeDelta = 2,
  statusReadLimit = 8,
  stabilize = {
    interval = 0.05,
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
    reportFrameLimit = 120,
  },
  yaw = {
    -- Damps spin around the craft up axis by tilting gyroscopic propeller
    -- bearings with setManualTarget. Requires a navigation table in the scan
    -- for body-frame to world-frame target conversion.
    enabled = true,
    rateKd = 0.15,
    maxTiltDeg = 8,
    deadbandDegPerSecond = 0.5,
    sign = 1,
    commandLateral = 0.08,
    clearOnExit = true,
    -- setManualTarget yields until the next server tick. Keep these high enough
    -- that yaw damping remains responsive but near-identical targets are not
    -- rewritten every pitch/roll frame.
    writeInterval = 0.1,
    writeDeadband = 0.01,
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
    -- source="key" checks only the configured keyboard/controller key.
    -- source="side" also reads a local computer redstone side.
    -- source="router" also reads binding through a redstone_router coordinate.
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
      q = { x = 2, y = -1, z = -4, side = "up" },
      w = { x = 1, y = -1, z = -4, side = "up" },
      e = { x = 0, y = -1, z = -4, side = "up" },
    },
  },

  reportPath = "/aircraft_scan.txt",
  sendWebhook = true,
}
