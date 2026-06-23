-- Copy this file to /config/processing_router.lua on the ComputerCraft computer.
-- Locations can be normal peripheral names/sides, such as "back", or relative
-- Peripheral Router coordinates, such as { x = 5, y = 1, z = 2 }.
-- You can also wrap objects yourself here and use those variables directly:
-- local r = peripheral.find("peripheral_router")
-- local storage = r.wrap(5, 1, 2)
-- Each job watches one input inventory, pushes required items into one or more
-- machine-facing inventories, and returns everything from output back to storage.

return {
  storage = { x = 5, y = 1, z = 2, label = "storage" },

  pollSeconds = 2,
  maxJobsPerScan = 1,

  jobs = {
    {
      name = "iron_press",
      input = { x = 0, y = 0, z = 1, label = "iron input" },
      output = { x = 0, y = 0, z = 2, label = "iron output" },
      items = {
        {
          name = "minecraft:iron_ingot",
          count = 1,
          to = { x = 1, y = 0, z = 0, label = "press input" },
        },
      },
    },

    {
      name = "two_item_machine",
      input = { x = 0, y = 0, z = 1, label = "shared input" },
      output = { x = 0, y = 0, z = 3, label = "machine output" },
      items = {
        {
          name = "minecraft:copper_ingot",
          count = 2,
          to = { x = 2, y = 0, z = 0, label = "machine input" },
          toSlot = 1,
        },
        {
          name = "minecraft:coal",
          count = 1,
          to = { x = 2, y = 0, z = 0, label = "machine input" },
          toSlot = 2,
        },
      },
    },

    -- Side/peripheral names still work when useful:
    -- {
    --   name = "side_based_job",
    --   input = "bottom",
    --   output = "top",
    --   storage = "back",
    --   items = {
    --     { name = "minecraft:gold_ingot", count = 1, to = "left" },
    --   },
    -- },
  },
}
