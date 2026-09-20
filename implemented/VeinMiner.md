# Vein miner

Implement a standalone `VeinMiner` turtle program that follows face-connected
matching blocks, defaulting to the block in front, with optional explicit block
IDs. Inspect all six sides using free turns and traverse with an iterative depth
first search. Track the actual return path and reserve fuel before every outward
move. Retry falling block obstructions, check inventory before each dig, and
return early when fuel or storage is low. Unload only into an inventory behind
the starting position, wait if full, and restore the starting heading. Document
setup and limits and verify behavior with a simulated turtle.

Completed with `VeinMiner.lua`, README usage instructions, and 16 passing
simulated turtle tests covering six-sided traversal, winding-path fuel budgets,
falling and delayed falling blocks, return obstructions, inventory reserves,
refueling, unlimited fuel, protected blocks, and full or missing chests. No
in-game validation was available. Early returns unload and end the run.
