import unittest
from pathlib import Path

from lupa import LuaRuntime


SOURCE = (Path(__file__).resolve().parents[1] / "TreeChopper.lua").read_text()
SAPLING = "minecraft:oak_sapling"
LOG = "minecraft:oak_log"
OFFSETS = [(0, 0, 1), (-1, 0, 0), (0, 0, -1), (1, 0, 0)]


class World:
    def __init__(self, grown=True, chest=True):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.pos = (0, 0, 0)
        self.heading = 0
        self.selected = 3
        self.fuel = 0
        self.items = {1: ["minecraft:coal", 64], 2: [SAPLING, 64]}
        self.blocks = {}
        self.dug = []
        self.planted = []
        self.deposited = 0
        self.waits = 0
        self.chest = chest
        self.after_sleep = None
        for x in range(8):
            for z in range(1, 9):
                self.blocks[x, 0, z] = LOG if grown else SAPLING
                if grown:
                    for y in range(1, 5):
                        self.blocks[x, y, z] = LOG
                    self.blocks[x, 5, z] = "minecraft:oak_leaves"
        api = {
            "select": self.select,
            "getFuelLevel": lambda: self.fuel,
            "refuel": self.refuel,
            "getItemCount": lambda slot=None: self.items.get(slot or self.selected, [None, 0])[1],
            "getItemDetail": self.detail,
            "turnRight": self.turn,
            "placeDown": self.plant,
            "drop": self.drop,
        }
        for suffix, dy in [("", 0), ("Up", 1), ("Down", -1)]:
            api["inspect" + suffix] = lambda dy=dy: self.inspect(dy)
            api["dig" + suffix] = lambda dy=dy: self.dig(dy)
        for name, dy in [("forward", 0), ("up", 1), ("down", -1)]:
            api[name] = lambda dy=dy: self.move(dy)
        self.lua.globals().turtle = self.lua.table_from(api)
        self.lua.globals().peripheral = self.lua.table_from({
            "hasType": lambda *_: self.chest and self.pos == (0, 0, 0) and self.heading == 2,
        })
        self.lua.globals().print = lambda *_: None
        self.lua.globals().sleep = self.sleep

    def select(self, slot):
        self.selected = slot
        return True

    def target(self, dy):
        delta = (0, dy, 0) if dy else OFFSETS[self.heading]
        return tuple(a + b for a, b in zip(self.pos, delta))

    def turn(self):
        self.heading = (self.heading + 1) % 4
        return True

    def inspect(self, dy):
        name = self.blocks.get(self.target(dy))
        return (True, self.lua.table_from({"name": name})) if name else (False, None)

    def dig(self, dy):
        target = self.target(dy)
        name = self.blocks.get(target)
        if not name:
            return False
        assert name in (LOG, "minecraft:oak_leaves")
        for slot in list(range(self.selected, 17)) + list(range(1, self.selected)):
            item = self.items.get(slot)
            if not item or (item[0] == name and item[1] < 64):
                self.items[slot] = [name, (item[1] if item else 0) + 1]
                break
        else:
            raise AssertionError("Lost drops")
        self.dug.append((target, name))
        del self.blocks[target]
        return True

    def move(self, dy):
        target = self.target(dy)
        assert target not in self.blocks
        assert self.fuel > 0
        self.fuel -= 1
        self.pos = target
        return True

    def refuel(self, count):
        assert self.selected == 1
        item = self.items.get(1)
        if not item or item[1] == 0:
            return False
        item[1] -= count
        self.fuel += 80 * count
        return True

    def detail(self, slot):
        item = self.items.get(slot)
        return self.lua.table_from({"name": item[0]}) if item and item[1] else None

    def plant(self):
        target = self.target(-1)
        assert target not in self.blocks
        assert target[1] == 0
        item = self.items[self.selected]
        assert item[0] == SAPLING and item[1] > 0
        item[1] -= 1
        if not item[1]:
            del self.items[self.selected]
        self.blocks[target] = SAPLING
        self.planted.append(target)
        return True

    def drop(self):
        assert self.chest and self.pos == (0, 0, 0) and self.heading == 2
        self.deposited += self.items.pop(self.selected)[1]
        return True

    def sleep(self, delay):
        self.waits += 1
        if self.after_sleep:
            self.after_sleep(self, delay)
        else:
            raise AssertionError("Unexpected pause")

    def run(self, *args):
        self.lua.execute(SOURCE, *args)


class TreeChopperTests(unittest.TestCase):
    def test_full_plot_harvest_replant_and_return(self):
        world = World()
        world.run()
        self.assertEqual(world.pos, (0, 0, 0))
        self.assertEqual(world.heading, 0)
        self.assertEqual(len(set(world.planted)), 64)
        self.assertEqual(len(world.dug), 320)
        self.assertEqual(world.deposited, 320)
        self.assertFalse(any(name == LOG for name in world.blocks.values()))

    def test_ungrown_saplings_untouched(self):
        world = World(grown=False)
        world.run("once")
        self.assertEqual(world.dug, [])
        self.assertEqual(world.planted, [])
        self.assertEqual(world.pos, (0, 0, 0))

    def test_no_chest_retains_cargo(self):
        world = World(chest=False)
        world.run()
        self.assertEqual(world.deposited, 0)
        self.assertEqual(sum(item[1] for item in world.items.values() if item[0] == LOG), 320)

    def test_obstacle_is_not_dug(self):
        world = World()
        world.blocks[0, 1, 1] = "minecraft:chest"
        with self.assertRaisesRegex(Exception, "Unexpected obstacle"):
            world.run()
        self.assertEqual(world.blocks[0, 1, 1], "minecraft:chest")

    def test_missing_fuel_waits_and_continues(self):
        world = World(grown=False)
        world.items.pop(1)
        world.after_sleep = lambda w, _: w.items.update({1: ["minecraft:coal", 64]})
        world.run()
        self.assertEqual(world.waits, 1)
        self.assertEqual(world.pos, (0, 0, 0))

    def test_missing_saplings_waits_and_continues(self):
        world = World()
        world.items.pop(2)
        world.after_sleep = lambda w, _: w.items.update({2: [SAPLING, 64]})
        world.run()
        self.assertEqual(world.waits, 1)
        self.assertEqual(len(world.planted), 64)

    def test_loop_returns_home_between_passes(self):
        world = World(grown=False)

        def stop(w, delay):
            self.assertEqual(w.pos, (0, 0, 0))
            self.assertEqual(w.heading, 0)
            self.assertEqual(delay, 60)
            if w.waits == 2:
                raise RuntimeError("Two passes completed")

        world.after_sleep = stop
        with self.assertRaisesRegex(RuntimeError, "Two passes completed"):
            world.run("loop", "60")


if __name__ == "__main__":
    unittest.main()
