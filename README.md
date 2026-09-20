# Computercraft

Lua programs for [CC: Tweaked](https://tweaked.cc/) / ComputerCraft.

## Usage

Copy a program onto a computer or turtle in-game, or clone this repo into the
world's `computercraft/computer/<id>` directory.

### Tree Chopper

Copy `TreeChopper.lua` onto a chopping or mining turtle. Start at sapling height,
immediately behind the bottom-right sapling, facing into the plot. The 8x8 plot
extends eight blocks forward and eight blocks left, counting that first sapling.

```text
        front
SSSSSSSS
SSSSSSSS
SSSSSSSS
SSSSSSSS
SSSSSSSS
SSSSSSSS
SSSSSSSS
SSSSSSSS
.......T  T faces up in this diagram
.......C  optional deposit chest
```

Put coal or other turtle fuel in slot 1 and matching saplings in slot 2. Keep
slots 3-16 empty for cargo. Supply up to 64 saplings for a fully grown plot.
Use one species throughout; the default is oak. Keep the row between the plot
and chest clear, including the space one block above it, for the return route.

```text
TreeChopper once
TreeChopper loop 60
TreeChopper loop 60 minecraft:birch_sapling
```

With no arguments it runs once. `loop` repeats with the specified delay in
seconds after each pass. The turtle travels one block above saplings, cuts
straight trunks from bottom to top, replants empty cells, and returns to its
original position and heading. Ungrown saplings are left in place. Leaves in its
path are cleared. A chest or other inventory directly behind home receives
cargo after each pass; fuel and the configured sapling species are retained.

This handles ordinary single-column trees, not branching large oaks or giant
2x2 trees. It does not clear the whole canopy or collect every dropped sapling.
Dense planting may prevent some saplings from growing. Provide suitable soil,
light, and clearance. For predictable straight trunks, use birch.

Fuel is consumed only from slot 1. If fuel, saplings, or cargo space run out,
the program waits for you to refill or empty the turtle where it is. A full
deposit chest also pauses unloading. Supply enough fuel and saplings for long
runs; there is no automatic supply-chest refill or mid-pass unloading.
Unexpected solid obstacles stop the program. Progress is not saved: after a
restart or interruption, manually return the turtle to the original starting
position and heading before running it again.

### Quarry

Run `Quarry <x> [y] [z]`, where `x` is the width, `y` is the optional length,
and `z` is the optional depth. Omitting `y` makes the footprint square.
Omitting `z` mines until bedrock.

Start the turtle at the top of the shaft facing North. Keep that origin block
clear, put a fuel chest directly above it, and put the deposit chest directly
behind it to the South. The turtle moves two blocks forward (North) before it
starts digging, leaving one clear block between the origin and the quarry. From
there, the quarry grows East and North, away from the origin.

### Chunk Miner

Copy `ChunkMiner.lua` onto a mining turtle. Stand the turtle at **Y=-58**, one
block outside the chunk, facing its bottom-right corner. The first block in
front must be inside the chunk; the footprint extends **16 blocks forward and
16 blocks to the turtle's left**, counting that first block. Use the chunk
border display to align the footprint. The program uses relative coordinates
and cannot detect a misplaced starting position.

Put the deposit inventory directly behind the starting position and a fuel
chest directly above it. Keep the home cell clear. Force-load **both the mining
chunk and the adjacent chunk containing the home setup** if it should run while
you are away. The turtle does not load chunks itself.

```text
ChunkMiner start
```

This mines all **2,816 blocks from Y=-58 through Y=-48, inclusive**. It first
clears a vertical access column inside the chunk, then mines serpentine layers
from the top down. It moves through each cell and uses turns to change direction.
You can supply another inclusive range with `ChunkMiner start <bottomY> <topY>`;
the turtle must start at that bottom Y. It never intentionally moves or digs
outside the footprint and height range, except for moving into its home cell.
Falling material from above the range may fall into the excavation and be mined.

The turtle returns through recorded cleared cells before its fuel or cargo
reserve is exhausted. Two empty inventory slots are kept for return-route
obstructions. At home it empties **every slot**, waiting indefinitely if the
deposit inventory is missing, full, or accepts only part of a stack. It then
draws fuel from above, waiting until there is enough to resume safely. Fuel can
also be inserted directly into the turtle while it is waiting for fuel. Only
refueling stages consume inventory items; mined coal is normally deposited.
Remove non-fuel items if they clog the fuel supply. After refueling, remaining
items and fuel-container leftovers are deposited before departure.

Gravel and other falling blocks are re-inspected and cleared before moving.
An unbreakable block or protected inventory pauses progress until you clear
the obstruction. If return-route debris exhausts even the reserved cargo space,
it waits for you to free a slot rather than discard drops. Water and lava do
not trigger repeated digging; the turtle attempts to move through them. The
program does not seal liquids or support the excavation ceiling.

Progress, cleared cells, position, heading, and the current servicing phase are
saved to `/chunk_miner.state`, with a backup and temporary file. Keep all three
files with the turtle. To resume a saved job or inspect it:

```text
ChunkMiner resume
ChunkMiner status
```

For automatic restart, copy the supplied `ChunkMinerStartup.lua` to the turtle's
`startup.lua`, keeping `ChunkMiner.lua` at the filesystem root. If you already
have a startup program, integrate its `shell.run("/ChunkMiner.lua", "resume")`
call into that program instead of overwriting it. A completed job remains saved
and will not start mining again. Run `ChunkMiner reset` after completion to clear
that job, then reposition for the next chunk and start again.

Movement and turns are journaled before execution. After an interrupted move,
fuel consumption normally identifies whether the move finished. **An unload
during a turn can require manual recovery**, since the turtle API cannot read
its actual heading. It stops and prints the before/after headings; check the
turtle's real orientation, then run exactly one of these:

```text
ChunkMiner recover before
ChunkMiner recover after
```

Then run `ChunkMiner resume`. Interrupted movement with unlimited fuel, or fuel
changed externally during the interruption, likewise requires checking the
printed before/after positions. Position coordinates are blocks left, blocks
above the starting Y, and blocks forward. Do not move, rotate, pick up, or refuel
the turtle externally while resolving an interrupted action. Damaged committed
state files stop the program rather than silently using an older position.
The journal supports ordinary unloads/reboots; it cannot guarantee consistency
after a server crash that rolls world data and computer files back differently.

Simulated tests: install `lupa` with `python -m pip install lupa`, then run
`python tests/test_chunk_miner.py`.

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
