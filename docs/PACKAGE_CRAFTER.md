# Package Crafter

`package_crafter` is the report-enabled Create package crafting turtle runtime. `package_crafter_prod` runs the same crafter without webhook reports.

## Setup

- The turtle must be a crafting turtle.
- The Packager is directly in front of the turtle and exposed as `front`.
- The Packager's attached staging inventory must be on the same wired network as the turtle.
- A separate output inventory must also be on the same wired network.

The turtle does not break, throw, attack, or manually open packages. Create's Packager unpacks packages into the staging inventory; the turtle reads package order data, pulls loose ingredients from staging, crafts, and pushes the crafted output.

Install with `update package_crafter` so the launchers and shared `package_crafter_core.lua` are installed together.

## Commands

```text
package_crafter [output_inventory]
package_crafter [staging_inventory] [output_inventory]
```

```text
package_crafter_prod [output_inventory]
package_crafter_prod [staging_inventory] [output_inventory]
```

The program always watches for package events. With one inventory argument, the argument is treated as output and staging is picked or prompted. With two inventory arguments, the first is staging and the second is output. If names are omitted, the turtle picks from connected inventories when only one valid choice exists; otherwise it prompts.

Use `package_crafter` while tuning because it sends webhook reports after each package and on errors. Webhook failures print a warning but do not stop the crafter. Use `package_crafter_prod` for the final always-on runtime.

## Event Handling

`watch` runs as two coroutines. One coroutine only listens for `package_received`, snapshots the package order data, gives it a sequence number, and appends it to an in-memory queue. The worker coroutine processes that queue one package at a time and does the slower inventory movement and `turtle.craft()` calls.

This split is intentional: rapid package events can keep being recorded while the turtle is busy crafting, moving items, or sending webhook reports. Terminal output uses `Package #N: action` and adds `q=M` when more packages are waiting. Report-enabled runs include the received `sequence` and current `queued` count.

Create can deliver the final link for an order before the package link that carries the recipe. When that happens, the turtle holds the final package record in memory and requeues it after the recipe package arrives for the same order ID.

Before crafting a ready final package, the worker scans the already-queued records and combines matching single-recipe final packages with the exact same recipe layout. It does not delay to wait for future packages. Combined terminal output shows `+N`, where `N` is the number of additional package records merged into that craft job.

## Recipe Cache

Crafting is conservative until a recipe is known. `turtle.craft(limit)` reports only success or failure, not the number of items crafted. For each unknown recipe, the turtle crafts one item, reads the output slot, records whether any remainder items were left in the grid, and saves that recipe data to `/config/package_crafter_recipes.lua`.

Known recipes batch by learned output count and output stack size. For example, a recipe that returns four stackable items caps itself to `turtle.craft(16)` so the output slot cannot overflow. Recipes that return non-stackable output and have no cached remainders use a persistent-grid path: stackable inputs are loaded in stacks, `turtle.craft(1)` runs repeatedly, and only slots that empty are refilled.
