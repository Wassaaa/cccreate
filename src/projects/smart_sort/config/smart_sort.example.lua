-- Copy this file to /config/smart_sort.lua on the ComputerCraft computer.
--
-- Runtime scan model:
-- - target inventory is indexed once at startup and then every targetRefreshSeconds
-- - source inventories are listed once per poll pass
-- - moves try a whole stack first and use the returned moved count
-- - scanTargetDetails is off by default because it touches every target slot

return {
  target = "top",
  sources = { "back" },

  pollSeconds = 1,
  targetRefreshSeconds = 60,

  -- Leave this false for huge inventories. Turn it on only when the target
  -- inventory hides useful item identities from list(), and accept the cost.
  scanTargetDetails = false,

  -- Reads getItemLimit only for known target slots during target refresh.
  -- This is much cheaper than checking limits before every move.
  readTargetSlotLimits = true,

  -- When true, full target slots are still tried. This supports drawers or
  -- storage blocks with void upgrades.
  allowVoidingFullTargets = true,

  -- Push with no item limit first so the peripheral moves as much of the stack
  -- as it can. If that nil-limit call is unsupported, fallbackLimitedMoves uses
  -- the snapshotted source count for that one attempt.
  wholeStackMoves = true,
  fallbackLimitedMoves = true,

  -- A target slot that returns zero moved is skipped until the next target
  -- refresh, avoiding repeated attempts against full/incompatible slots.
  blockFailedTargets = true,

  shortItemNames = true,
  logMoves = true,
  logIdle = false,

  -- Locked empty drawers or similar targets can be declared here when they do
  -- not appear in list(). Keys are item names, values are target slot numbers.
  extraTargets = {
    -- ["minecraft:iron_ingot"] = { 1 },
  },
}
