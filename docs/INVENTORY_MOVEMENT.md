# Inventory Movement Performance

Use this pattern for CC:Tweaked inventory movers unless a machine-specific API forces a different approach.

## Preferred Pattern

- Prefer generic inventory peripherals on a wired modem network, using `pushItems` or `pullItems`.
- Snapshot inventories with `list()` and loop the sparse result with `pairs`.
- Build lookup indexes from snapshots, such as `item name -> target slots`, and reuse them for a batch or short refresh window.
- Move a whole source stack in one transfer attempt when possible, then trust the returned moved count.
- Cache target slots that return zero moved or known-full results until the next target refresh.
- Use `getItemDetail`, `getItemLimit`, and full `size()` scans only where the extra data changes routing decisions.

## Avoid

- Re-listing the same huge target inventory before every slot move.
- Scanning all slots with `getItemDetail` by default.
- Moving one item or one requested count at a time when a whole stack transfer can do the same work.
- Re-trying a known-full or incompatible target slot every tick.

## Example Shape

```lua
local targetsByName = {}

for slot, item in pairs(target.list()) do
  targetsByName[item.name] = targetsByName[item.name] or {}
  table.insert(targetsByName[item.name], slot)
end

for sourceSlot, item in pairs(source.list()) do
  local targetSlots = targetsByName[item.name]

  if targetSlots then
    for _, targetSlot in ipairs(targetSlots) do
      local moved = source.pushItems(targetName, sourceSlot, item.count, targetSlot)

      if moved > 0 then
        break
      end
    end
  end
end
```

Some peripherals allow omitting the transfer limit, which lets `pushItems` attempt the whole stack directly. Keep a count-limited fallback when targeting mixed CC:Tweaked/modded inventories because method arity can vary:

```lua
local ok, moved = pcall(source.pushItems, targetName, sourceSlot, nil, targetSlot)

if not ok then
  moved = source.pushItems(targetName, sourceSlot, item.count, targetSlot)
end
```

`smart_sort` uses the full version of this pattern: target index refreshes are timed, source inventories are listed once per poll pass, and zero-move target slots are blocked until the next refresh.
