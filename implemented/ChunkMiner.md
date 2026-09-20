# Persistent chunk miner

Create a standalone miner for a 16 by 16 footprint extending forward and left
from the block immediately in front of the starting turtle. Make starting Y
and inclusive mining limits configurable, defaulting to -58 through -48.
Keep the deposit behind the start and fuel above it or inserted in the turtle.

Traverse layers in a serpentine pattern, using cleared cells for short return
routes. Reserve return fuel and cargo space before digging. Return home to
fully unload, wait for fuel or deposit capacity, and resume work automatically.
Retry falling blocks and pause safely for protected or unbreakable obstructions.

Persist job configuration, cleared cells, progress, phase, position, and heading.
Journal movements and turns before execution. Resolve interrupted movements
using fuel consumption when possible, and require explicit recovery for an
ambiguous turn rather than silently guessing. Supply an optional startup script.
Test coverage, boundaries, fuel and unloading waits, falling blocks, and injected
restarts at movement, turn, and save boundaries. Document loading both the mining
chunk and the adjacent home chunk.

Implemented as `ChunkMiner.lua` with optional `ChunkMinerStartup.lua`. Confirmed
setup: start at Y=-58, one block behind the chunk's bottom-right corner, facing
in with the footprint extending left, deposit behind, and fuel above. The miner
opens an internal access column and works top down through Y=-48 to Y=-58.

Validation: 14 Lua 5.2 simulation tests passed (11-test main suite plus three
additional targeted tests). Coverage includes the complete 2,816-cell default
volume, boundary checks, cargo and fuel servicing, partial deposits, falling
material on the outward and homeward routes, waits for supplies, and injected
interruptions before/after movement, turning, digging, dropping, refueling, and
state-file operations. No in-game validation was available. Pending turns and
unlimited-fuel moves deliberately require manual recovery when ambiguous.
