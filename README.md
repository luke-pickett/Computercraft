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
