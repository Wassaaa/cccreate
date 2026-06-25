# Package Crafter

`package_crafter.lua` is a crafting turtle prototype for Create logistics craft packages.

## Current Setup

- The turtle is a crafting turtle.
- The Packager is directly in front of the turtle and is exposed as `front`.
- The Packager's attached staging barrel is on the wired network as `minecraft:barrel_4`.
- A separate output inventory must be on the same wired network before `once` or `watch` can craft.

The turtle does not try to break, throw, attack, or manually open packages. Create's Packager unpacks packages into the staging barrel; the turtle only reads package order data, pulls loose ingredients from staging, crafts, and pushes the crafted output.

Crafting is intentionally conservative. `turtle.craft(limit)` reports only success or failure, not the number of items crafted. The script crafts one step first to learn the output stack size, then batches only when the selected output slot and every recipe input slot can safely hold the batch. Leftover container items, such as empty buckets, are pushed to the output inventory after each batch.

## Commands

```text
package_crafter status
```

Reports the Packager, staging barrel, turtle inventory, and possible output inventories.

```text
package_crafter sniff
```

Waits briefly for one Create package event and reports the exact event shape. This is for probing; without an output inventory it only reports the craft plan.

```text
package_crafter once [output_inventory]
```

Waits for one `package_received` event, reads the package's craft order, waits briefly for ingredients to appear in staging, crafts, then pushes output to the output inventory.

```text
package_crafter watch [output_inventory]
```

Keeps handling package requests. If there is exactly one non-staging inventory on the wired network, it is used as output automatically. If there are several, the turtle prompts for one.

## Event Shape

In this modpack, `package_received` arrives as:

```text
package_received, "front", packageObject
```

The package object contains order data such as `isFinal`, `isFinalLink`, and `getCrafts()`. The script searches all event arguments for the package object instead of assuming a fixed position.
