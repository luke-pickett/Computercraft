# Computercraft

Lua programs for [CC: Tweaked](https://tweaked.cc/) / ComputerCraft.

## Usage

Copy a program onto a computer or turtle in-game, or clone this repo into the
world's `computercraft/computer/<id>` directory.

### Quarry

Run `Quarry <x> [y] [z]`, where `x` is the width, `y` is the optional length,
and `z` is the optional depth. Omitting `y` makes the footprint square.
Omitting `z` mines until bedrock.

Start the turtle at the top of the shaft facing North. Keep that origin block
clear, put a fuel chest directly above it, and put the deposit chest directly
behind it to the South. The turtle moves two blocks forward (North) before it
starts digging, leaving one clear block between the origin and the quarry. From
there, the quarry grows East and North, away from the origin.

### Vein Miner

Run `VeinMiner` on a mining turtle facing the first block of the vein. Place a
deposit chest directly behind the turtle and put fuel in slot 1 (or refuel it
beforehand). Any starting compass direction works. No building blocks are needed.

By default it follows the exact block ID in front. To include multiple variants,
run `VeinMiner minecraft:iron_ore minecraft:deepslate_iron_ore`. It follows matching
blocks connected through faces, checking all six sides with free turns. It does
not search through stone for new veins or follow diagonal-only connections.
The starting cell, the deposit cell behind it, and the cell above the start are
excluded to protect the home setup.

The miner records its route, reserves fuel for retracing that route plus four
extra moves, and uses only slot 1 for automatic refueling. It returns early with
four empty cargo slots reserved for obstructions on the return trip. Falling
gravel, sand, and other blocks replacing a mined block are repeatedly cleared;
storage is checked before every dig. Blocks obstructing the recorded return
route are cleared as well. It stops at home and empties all slots, including
unused fuel, into the chest, then restores its starting heading. It waits if the
chest is full or missing. An early return ends the run; it does not automatically
resume the unfinished vein.

Keep the turtle loaded and the home route accessible. If an unbreakable block
blocks the return route, or falling blocks exhaust the remaining inventory,
the program waits for you to clear the obstruction or free a slot. Position and
progress are kept in memory only; shutdowns and termination do not auto-recover.

Simulated tests: install `lupa` with `python -m pip install lupa`, then run
`python tests/test_vein_miner.py`.

### Modular Inventory Manager

Attach a wired modem to a computer and connect it with networking cable and
wired modems to each chest, barrel, or drawer. Right-click every remote modem so
its inventory appears on the wired network, then use the name printed in chat
when registering it.

Run `MIM attach <name> 1` to register the input inventory beside the computer.
Register outputs with `MIM attach <name> [priority]`; omitting the priority puts
the inventory after all existing entries. Priorities are unique, and lower
numbers are filled first.

- `MIM list` shows registered inventories, capacity, filters, and offline status.
- `MIM detach <name>` removes an inventory from the registry.
- `MIM deposit` moves the input into outputs, topping up partial stacks before
  using empty slots.

The registry is stored in `mim_index.tbl`. Optional `allow` and `deny` Lua
pattern lists can be added to output entries in that file. Deny patterns take
precedence; when an allow list exists, an item must match at least one pattern.

## License

MIT
