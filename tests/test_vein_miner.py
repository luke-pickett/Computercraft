import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".test-tools"))
from lupa import LuaRuntime


SOURCE = (Path(__file__).resolve().parents[1] / "VeinMiner.lua").read_text()
ORE = "minecraft:iron_ore"
OFFSETS = [(0, 0, -1), (1, 0, 0), (0, 0, 1), (-1, 0, 0), (0, 1, 0), (0, -1, 0)]


class World:
    def __init__(self, blocks, fuel=1000):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.blocks = dict(blocks)
        self.blocks[(0, 0, 1)] = "minecraft:chest"
        self.pos = (0, 0, 0)
        self.heading = 0
        self.selected = 1
        self.fuel = fuel
        self.items = [0] * 16
        self.fuel_items = 0
        self.moves = 0
        self.dug = []
        self.logs = []
        self.falling = {}
        self.fail_moves = 0
        self.drop_failures = 0
        self.partial = False
        self.waits = 0
        self.on_sleep = None
        self.on_move = None
        api = {
            "getSelectedSlot": lambda: self.selected,
            "select": self.select,
            "getItemCount": lambda slot: self.items[slot - 1],
            "getFuelLevel": lambda: self.fuel,
            "refuel": self.refuel,
            "turnRight": lambda: self.turn(1),
            "turnLeft": lambda: self.turn(-1),
            "drop": self.drop,
        }
        for suffix, direction in [("", None), ("Up", 4), ("Down", 5)]:
            api["inspect" + suffix] = lambda d=direction: self.inspect(d)
            api["dig" + suffix] = lambda d=direction: self.dig(d)
        for name, direction in [("forward", None), ("up", 4), ("down", 5)]:
            api[name] = lambda d=direction: self.move(d)
        self.lua.globals().turtle = self.lua.table_from(api)
        self.lua.globals().peripheral = self.lua.table_from({"hasType": lambda *_: False})
        self.lua.globals().sleep = self.sleep
        self.lua.globals().print = self.logs.append

    def select(self, slot):
        self.selected = slot
        return True

    def turn(self, amount):
        self.heading = (self.heading + amount) % 4
        return True

    def target(self, direction):
        offset = OFFSETS[self.heading if direction is None else direction]
        return tuple(a + b for a, b in zip(self.pos, offset))

    def inspect(self, direction):
        name = self.blocks.get(self.target(direction))
        return (True, self.lua.table_from({"name": name})) if name else (False, None)

    def dig(self, direction):
        target = self.target(direction)
        name = self.blocks.get(target)
        if not name or name == "minecraft:bedrock":
            return False
        assert name != "minecraft:chest"
        assert self.items[self.selected - 1] == 0
        self.items[self.selected - 1] = 1
        self.dug.append((target, name))
        self.blocks.pop(target)
        queue = self.falling.get(target, [])
        if queue:
            self.blocks[target] = queue.pop(0)
        return True

    def move(self, direction):
        target = self.target(direction)
        if self.fail_moves:
            self.fail_moves -= 1
            return False
        if target in self.blocks or self.fuel == 0:
            return False
        if self.fuel != "unlimited":
            self.fuel -= 1
        self.pos = target
        self.moves += 1
        if self.on_move:
            self.on_move()
        return True

    def refuel(self, count):
        if self.selected != 1 or self.fuel_items == 0:
            return False
        self.fuel_items -= 1
        self.items[0] -= 1
        self.fuel += 80
        return True

    def drop(self):
        assert self.pos == (0, 0, 0) and self.heading == 2
        assert self.blocks.get((0, 0, 1)) == "minecraft:chest"
        if self.drop_failures:
            self.drop_failures -= 1
            return False
        if self.partial:
            self.items[self.selected - 1] -= 1
        else:
            self.items[self.selected - 1] = 0
        return True

    def sleep(self, _):
        self.waits += 1
        assert self.waits < 500
        if self.on_sleep:
            self.on_sleep()

    def run(self, *args):
        self.lua.execute(SOURCE, *args)
        assert self.pos == (0, 0, 0)
        assert self.heading == 0
        assert sum(self.items) == 0
        assert self.fuel == "unlimited" or self.fuel >= 0


class VeinMinerTests(unittest.TestCase):
    def test_six_sides_loop_and_non_target(self):
        ore = [(0, 0, -1), (1, 0, -1), (1, 1, -1), (0, 1, -1), (0, -1, -1), (-1, 0, -1)]
        world = World({**dict.fromkeys(ore, ORE), (0, 0, -2): "minecraft:stone"})
        world.run()
        self.assertEqual({p for p, _ in world.dug}, set(ore))
        self.assertEqual(world.moves, 2 * len(ore))

    def test_winding_route_fuel_reserve(self):
        ore = [(0, 0, -1), (1, 0, -1), (2, 0, -1), (2, 0, 0), (2, 0, 1), (1, 0, 1)]
        world = World(dict.fromkeys(ore, ORE), fuel=12)
        world.run()
        self.assertEqual(len(world.dug), 4)
        self.assertEqual(world.fuel, 4)
        self.assertIn("Fuel reserve", world.logs[-1])

    def test_falling_blocks(self):
        world = World({(0, 0, -1): ORE})
        world.falling[(0, 0, -1)] = ["minecraft:gravel", "minecraft:sand", "mod:falling_block"]
        world.run()
        self.assertEqual(len(world.dug), 4)

    def test_inventory_stops_during_falling_column(self):
        world = World({(0, 0, -1): ORE})
        world.falling[(0, 0, -1)] = ["minecraft:gravel"] * 30
        world.run()
        self.assertEqual(len(world.dug), 11)
        self.assertEqual(world.moves, 0)

    def test_falling_obstruction_on_return(self):
        world = World({(0, 0, -1): ORE, (0, 0, -2): ORE})
        def block_return():
            if world.moves == 2:
                world.blocks[(0, 0, -1)] = "minecraft:gravel"
        world.on_move = block_return
        world.run()
        self.assertEqual(len(world.dug), 3)

    def test_full_and_partial_chest(self):
        world = World({(0, 0, -1): ORE})
        world.items[2] = 3
        world.drop_failures = 2
        world.partial = True
        world.run()
        self.assertGreaterEqual(world.logs.count("Waiting for space in the deposit chest"), 2)

    def test_missing_chest_at_unload(self):
        world = World({(0, 0, -1): ORE})
        def remove_chest():
            world.blocks.pop((0, 0, 1), None)
        def restore_chest():
            if world.logs[-1] == "Replace the deposit chest behind the start":
                world.blocks[(0, 0, 1)] = "minecraft:chest"
        world.on_move = remove_chest
        world.on_sleep = restore_chest
        world.run()

    def test_zero_fuel_and_refuel(self):
        world = World({(0, 0, -1): ORE}, fuel=0)
        world.run()
        self.assertEqual(world.moves, 0)
        world = World({(0, 0, -1): ORE}, fuel=0)
        world.fuel_items = world.items[0] = 1
        world.run()
        self.assertEqual(world.moves, 2)

    def test_unlimited_and_multiple_targets(self):
        world = World({(0, 0, -1): ORE, (0, 0, -2): "minecraft:deepslate_iron_ore"}, fuel="unlimited")
        world.run(ORE, "minecraft:deepslate_iron_ore")
        self.assertEqual(len(world.dug), 2)

    def test_failed_moves_do_not_change_path(self):
        world = World({(0, 0, -1): ORE})
        world.fail_moves = 8
        world.run()
        self.assertEqual(world.moves, 0)
        self.assertIn("obstructed", world.logs[-1])

    def test_protected_target(self):
        world = World({(0, 0, -1): "minecraft:bedrock"})
        world.run()
        self.assertEqual(world.moves, 0)
        self.assertEqual(world.dug, [])

    def test_missing_chest_before_moving(self):
        world = World({(0, 0, -1): ORE})
        world.blocks.pop((0, 0, 1))
        with self.assertRaisesRegex(Exception, "Place a chest"):
            world.run()
        self.assertEqual(world.moves, 0)
        self.assertEqual(world.heading, 0)

    def test_delayed_falling_block(self):
        world = World({(0, 0, -1): ORE})
        def falling_after_wait():
            if len(world.dug) == 1:
                world.blocks[(0, 0, -1)] = "minecraft:gravel"
        world.on_sleep = falling_after_wait
        world.run()
        self.assertEqual(len(world.dug), 2)

    def test_inventory_full_on_return_waits(self):
        world = World({(0, 0, -1): ORE, (0, 0, -2): ORE})
        def fill_on_second_move():
            if world.moves == 2:
                world.items = [1] * 16
                world.blocks[(0, 0, -1)] = "minecraft:gravel"
        def free_slot():
            if world.logs[-1] == "Free an inventory slot to clear the route home":
                world.items[15] = 0
        world.on_move = fill_on_second_move
        world.on_sleep = free_slot
        world.run()
        self.assertIn("Free an inventory slot to clear the route home", world.logs)

    def test_blocked_return_waits_for_clearance(self):
        world = World({(0, 0, -1): ORE, (0, 0, -2): ORE})
        def block_on_second_move():
            if world.moves == 2:
                world.blocks[(0, 0, -1)] = "minecraft:bedrock"
        def clear_route():
            if "clear the route home" in world.logs[-1]:
                world.blocks.pop((0, 0, -1), None)
        world.on_move = block_on_second_move
        world.on_sleep = clear_route
        world.run()
        self.assertTrue(any("clear the route home" in line for line in world.logs))

    def test_vertical_inventory_is_protected(self):
        world = World({(0, 0, -1): ORE, (0, 1, -1): "minecraft:chest"})
        world.run(ORE, "minecraft:chest")
        self.assertEqual(len(world.dug), 1)


if __name__ == "__main__":
    unittest.main()
