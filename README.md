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

## License

MIT
