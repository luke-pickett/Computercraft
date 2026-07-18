# MIM — Modular Inventory Manager

Plan for `MIM.lua`, a wired-modem inventory manager for CC: Tweaked.

## Overview

A computer with a wired modem on it joins a network of chests/barrels/drawers.
Each attached inventory is registered in a priority table stored on disk.
Priority `1` is the **input** (the chest beside the computer); every other
priority is an **output**. `MIM deposit` empties the input across the outputs,
topping up existing partial stacks everywhere before opening any new slot.

## Files

| File | Role |
| --- | --- |
| `MIM.lua` | Command-line entry point: `attach`, `detach`, `list`, `deposit` |
| `MIMIndex.lua` | Module owning the registry: load, save, validate, ordered iteration |
| `mim_index.tbl` | On-disk data, `textutils.serialize`d, written by `MIMIndex` only |

Splitting the module from the data file keeps `MIM.lua` free of any file I/O and
matches the existing `Vector` / `Coordinator` module layout.

## Index schema

```lua
{
    version = 1,
    entries = {
        { name = "minecraft:chest_0",  priority = 1 },
        { name = "minecraft:barrel_3", priority = 2, allow = { "minecraft:cobblestone", "minecraft:.*_ore" } },
        { name = "minecraft:chest_7",  priority = 3, deny = { "minecraft:dirt" } },
    },
}
```

- `name` — the network name from `peripheral.getNames()`.
- `priority` — unique positive integer. Exactly one entry has `priority == 1`.
- `allow` — optional list of Lua patterns; when present an item must match one.
- `deny` — optional list of Lua patterns; a match rejects the item outright.
- Missing `allow` means "accept anything not denied".

`MIMIndex` exposes:

- `MIMIndex.load()` → table (returns an empty index when the file is absent)
- `MIMIndex.save(index)`
- `MIMIndex.attach(index, name, priority, filters)`
- `MIMIndex.detach(index, name)`
- `MIMIndex.input(index)` → the priority-1 entry, or `nil`
- `MIMIndex.outputs(index)` → array sorted ascending by priority
- `MIMIndex.accepts(entry, itemName)` → boolean

## Commands

### `MIM attach <name> [priority]`

Verifies `peripheral.isPresent(name)` and `peripheral.hasType(name, "inventory")`,
then records it. With no priority, takes `maxPriority + 1`. Reassigning a taken
priority errors and lists the conflict rather than silently shuffling entries.
Attaching a name that already exists updates its priority in place.

### `MIM detach <name>`

Removes the entry. Detaching the input warns that `deposit` will fail until a new
priority-1 entry exists.

### `MIM list`

Prints priority, name, item count / capacity, and a filter summary. Flags entries
whose peripheral is no longer on the network as `OFFLINE`.

### `MIM deposit`

1. Load the index; error out if there is no priority-1 entry.
2. Wrap the input and every online output. Skip offline outputs with a warning
   instead of aborting the run.
3. Snapshot each output's contents once via `list()`, so the two passes below plan
   against in-memory state instead of re-scanning after every transfer.
4. **Pass one — top up.** For each input slot, walk the outputs in priority order
   and, for every slot already holding the same item below `maxCount`, push the
   smaller of (remaining input count, headroom) with
   `input.pushItems(outputName, fromSlot, amount, toSlot)`. Targeting `toSlot`
   explicitly is what guarantees a partial stack is finished before anything else
   is considered.
5. **Pass two — new stacks.** Whatever is left goes to the first output in
   priority order that accepts the item and has a free slot, again by explicit
   `toSlot`, splitting across outputs when one fills up.
6. Filters are checked before either pass; an item no output accepts stays in the
   input and is reported at the end.
7. Print a summary: items moved, items left behind and why (no room / rejected).

`maxCount` and item names come from `input.list()` plus one
`input.getItemDetail(slot)` per distinct item, cached per run — `list()` alone
does not carry stack limits on every CC version, and `getItemDetail` is the
expensive call to avoid repeating.

## Edge cases

- Empty input → print "nothing to deposit" and exit 0.
- No outputs registered → error naming the `attach` command.
- Input registered twice, or two entries sharing a priority → `MIMIndex.load`
  raises so a hand-edited file cannot cause a silent misdeposit.
- Peripheral removed mid-run → `pcall` each transfer, mark the output offline for
  the remainder of the run, continue.
- Non-stackable items (`maxCount == 1`) skip pass one entirely.
- Two items with the same name but different NBT will merge-attempt and simply
  transfer 0; the plan treats a 0-count push as "no headroom" and moves on.

## Out of scope

A content cache (item → location index for fast lookup / withdrawal) and a
`MIM withdraw` command. The registry file is deliberately small so a cache can be
added later as its own file without changing this schema.

## Steps

1. `MIMIndex.lua` — schema, load/save, validation, accessors.
2. `MIM.lua` — argument parsing and the `attach` / `detach` / `list` commands.
3. `MIM.lua` — the two-pass `deposit` routine.
4. README section covering wiring and the command set.
