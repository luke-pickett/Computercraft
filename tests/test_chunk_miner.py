import sys
import unittest
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / ".test-tools"))
from lupa.lua52 import LuaRuntime


SOURCE = (Path(__file__).resolve().parents[1] / "ChunkMiner.lua").read_text()
OFFSETS = [(0, 0, 1), (-1, 0, 0), (0, 0, -1), (1, 0, 0), (0, 1, 0), (0, -1, 0)]
SERIALIZER = """
textutils = {}
function textutils.serialize(value)
    if type(value) == "table" then
        local entries = {}
        for k, v in pairs(value) do
            entries[#entries + 1] = "[" .. textutils.serialize(k) .. "]=" .. textutils.serialize(v)
        end
        table.sort(entries)
        return "{" .. table.concat(entries, ",") .. "}"
    elseif type(value) == "string" then
        return string.format("%q", value)
    end
    return tostring(value)
end
function textutils.unserialize(value)
    local fn = load("return " .. value, "state", "t", {})
    if not fn then return nil end
    local ok, result = pcall(fn)
    return ok and result or nil
end
"""


class Interrupted(Exception):
    pass


class World:
    def __init__(self, height=1, fuel=0, stack_limit=64):
        self.height = height
        self.blocks = {(x, y, z): "minecraft:deepslate" for x in range(16)
                       for y in range(height) for z in range(1, 17)}
        self.blocks[(0, 0, -1)] = "minecraft:chest"
        self.blocks[(0, 1, 0)] = "minecraft:chest"
        self.pos = (0, 0, 0)
        self.heading = 0
        self.selected = 0
        self.fuel = fuel
        self.stack_limit = stack_limit
        self.items = [None] * 16
        self.files = {}
        self.logs = []
        self.digs = Counter()
        self.visits = Counter()
        self.drops = Counter()
        self.events = Counter()
        self.fuel_supply = 100000
        self.chest_full = False
        self.partial_drop = False
        self.falling = {}
        self.on_event = None
        self.waits = 0
        self.new_runtime()

    def new_runtime(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(SERIALIZER)
        api = {
            "getFuelLevel": lambda: self.fuel,
            "getFuelLimit": lambda: 20000,
            "select": self.select,
            "getItemCount": self.count,
            "refuel": self.refuel,
            "suckUp": self.suck,
            "drop": self.drop,
            "turnLeft": lambda: self.turn(-1),
            "turnRight": lambda: self.turn(1),
        }
        for suffix, direction in [("", None), ("Up", 4), ("Down", 5)]:
            api["inspect" + suffix] = lambda d=direction: self.inspect(d)
            api["dig" + suffix] = lambda d=direction: self.dig(d)
        for name, direction in [("forward", None), ("up", 4), ("down", 5)]:
            api[name] = lambda d=direction: self.move(d)
        self.lua.globals().turtle = self.lua.table_from(api)
        self.lua.globals().peripheral = self.lua.table_from({"hasType": lambda *_: False})
        self.lua.globals().print = self.logs.append
        self.lua.globals().sleep = self.sleep
        self.lua.globals().fs = self.lua.table_from({
            "exists": lambda path: path in self.files,
            "delete": self.delete,
            "move": self.rename,
            "open": self.open,
        })

    def event(self, name):
        self.events[name] += 1
        if self.on_event:
            self.on_event(name)

    def open(self, path, mode):
        if mode == "r":
            data = self.files[path]
            first, _, rest = data.partition("\n")
            return self.lua.table_from({"readLine": lambda: first, "readAll": lambda: rest, "close": lambda: None})
        self.event("before_open_write")
        self.files[path] = ""
        self.event("after_open_write")
        def write(data):
            self.event("before_write")
            self.files[path] += data
            self.event("after_write")
        return self.lua.table_from({"write": write, "flush": lambda: self.event("flush"), "close": lambda: self.event("close_write")})

    def delete(self, path):
        self.event("before_delete")
        del self.files[path]
        self.event("after_delete")

    def rename(self, source, dest):
        self.event("before_rename")
        assert dest not in self.files
        self.files[dest] = self.files.pop(source)
        self.event("after_rename")

    def select(self, slot):
        self.selected = slot - 1
        return True

    def count(self, slot):
        item = self.items[slot - 1]
        return item[1] if item else 0

    def collect(self, name, amount=1):
        for i in range(16):
            if self.items[i] and self.items[i][0] == name and self.items[i][1] + amount <= self.stack_limit:
                self.items[i][1] += amount
                return True
        for i in [self.selected] + list(range(16)):
            if self.items[i] is None:
                self.items[i] = [name, amount]
                return True
        return False

    def refuel(self, count):
        item = self.items[self.selected]
        if not item or item[0] != "minecraft:coal" or self.fuel == "unlimited":
            return False
        self.event("before_refuel")
        item[1] -= 1
        if item[1] == 0:
            self.items[self.selected] = None
        self.fuel += 80
        self.event("after_refuel")
        return True

    def suck(self, count):
        assert self.pos == (0, 0, 0)
        if self.fuel_supply == 0 or (0, 1, 0) not in self.blocks:
            return False
        if self.collect("minecraft:coal"):
            self.fuel_supply -= 1
            return True
        return False

    def target(self, direction):
        offset = OFFSETS[self.heading if direction is None else direction]
        return tuple(a + b for a, b in zip(self.pos, offset))

    def inspect(self, direction):
        name = self.blocks.get(self.target(direction))
        return (True, self.lua.table_from({"name": name})) if name else (False, None)

    def inside(self, pos):
        x, y, z = pos
        return 0 <= x < 16 and 0 <= y < self.height and 1 <= z <= 16

    def dig(self, direction):
        target = self.target(direction)
        assert self.inside(target), f"Dig outside chunk: {target}"
        name = self.blocks.get(target)
        if not name or name == "minecraft:bedrock":
            return False
        assert name != "minecraft:chest"
        self.event("before_dig")
        assert self.collect(name), "Lost a drop to full inventory"
        self.digs[name] += 1
        self.blocks.pop(target)
        queue = self.falling.get(target, [])
        if queue:
            self.blocks[target] = queue.pop(0)
        self.event("after_dig")
        return True

    def move(self, direction):
        self.event("before_move")
        target = self.target(direction)
        assert self.inside(target) or target == (0, 0, 0), f"Moved outside chunk: {target}"
        if target in self.blocks or self.fuel == 0:
            self.event("failed_move")
            return False
        if self.fuel != "unlimited":
            self.fuel -= 1
        self.pos = target
        self.visits[target] += 1
        self.event("after_move")
        return True

    def turn(self, delta):
        self.event("before_turn")
        self.heading = (self.heading + delta) % 4
        self.event("after_turn")
        return True

    def drop(self):
        assert self.pos == (0, 0, 0) and self.heading == 2
        assert self.blocks.get((0, 0, -1)) == "minecraft:chest"
        self.event("before_drop")
        if self.chest_full:
            return False
        item = self.items[self.selected]
        if item:
            amount = 1 if self.partial_drop else item[1]
            self.drops[item[0]] += amount
            item[1] -= amount
            if item[1] == 0:
                self.items[self.selected] = None
        self.event("after_drop")
        return True

    def sleep(self, _):
        self.waits += 1
        assert self.waits < 20000, "Program stalled"
        self.event("sleep")

    def run(self, *args):
        self.lua.execute(SOURCE, *args)

    def restart(self, *args):
        self.new_runtime()
        self.run(*(args or ("resume",)))

    def state(self):
        states = []
        for path in ["/chunk_miner.state", "/chunk_miner.state.bak", "/chunk_miner.state.tmp"]:
            if path in self.files and "\n" in self.files[path]:
                data = self.files[path].partition("\n")[2]
                parsed = self.lua.globals().textutils.unserialize(data)
                if parsed:
                    states.append(parsed)
        return max(states, key=lambda value: value["sequence"])

    def assert_complete(self):
        assert self.pos == (0, 0, 0) and self.heading == 0
        assert all(item is None for item in self.items)
        assert not any(self.inside(pos) for pos in self.blocks)
        assert self.state()["phase"] == "done"
        assert self.state()["cleared"].count("1") == 256 * self.height
        assert self.drops["minecraft:deepslate"] == self.digs["minecraft:deepslate"]


class ChunkMinerTests(unittest.TestCase):
    def test_full_default_chunk_and_height_range(self):
        world = World(height=11)
        world.run("start")
        world.assert_complete()
        self.assertEqual(world.digs["minecraft:deepslate"], 2816)
        self.assertGreater(world.visits[(0, 0, 0)], 1)

    def test_inventory_trips_and_falling_blocks(self):
        world = World(stack_limit=1)
        world.falling[(0, 0, 1)] = ["minecraft:gravel", "minecraft:sand"] * 10
        world.run("start", "-58", "-58")
        world.assert_complete()
        self.assertEqual(world.drops["minecraft:gravel"], 10)
        self.assertGreater(world.visits[(0, 0, 0)], 18)

    def test_wait_for_fuel_and_full_partial_deposit(self):
        world = World(stack_limit=8)
        world.fuel_supply = 0
        world.chest_full = True
        world.partial_drop = True
        def supply(name):
            if name == "sleep" and world.fuel_supply == 0 and "Waiting for fuel" in world.logs[-1]:
                self.assertEqual(world.pos, (0, 0, 0))
                world.fuel_supply = 10000
            if name == "sleep" and world.chest_full and "Waiting for room" in world.logs[-1]:
                self.assertEqual(world.pos, (0, 0, 0))
                world.chest_full = False
        world.on_event = supply
        world.run("start", "-58", "-58")
        world.assert_complete()
        self.assertTrue(any("Waiting for fuel" in line for line in world.logs))
        self.assertTrue(any("Waiting for room" in line for line in world.logs))

    def test_restart_before_and_after_movement(self):
        for event in ("before_move", "after_move"):
            with self.subTest(event=event):
                world = World()
                def interrupt(name):
                    if name == event and world.events[name] == 20:
                        raise Interrupted()
                world.on_event = interrupt
                with self.assertRaises(Interrupted):
                    world.run("start", "-58", "-58")
                world.on_event = None
                world.restart()
                world.assert_complete()

    def test_interrupted_turn_requires_explicit_recovery(self):
        for event, choice in (("before_turn", "before"), ("after_turn", "after")):
            with self.subTest(event=event):
                world = World()
                def interrupt(name):
                    if name == event and world.events[name] == 8:
                        raise Interrupted()
                world.on_event = interrupt
                with self.assertRaises(Interrupted):
                    world.run("start", "-58", "-58")
                world.on_event = None
                pos = world.pos
                with self.assertRaisesRegex(Exception, "Interrupted turn"):
                    world.restart()
                self.assertEqual(world.pos, pos)
                world.run("recover", choice)
                world.run("resume")
                world.assert_complete()

    def test_restart_during_saves(self):
        for event in ("before_open_write", "after_open_write", "before_write", "after_write",
                      "flush", "close_write", "before_delete", "after_delete", "before_rename", "after_rename"):
            with self.subTest(event=event):
                world = World()
                def interrupt(name):
                    if name == event and world.events["after_move"] >= 12 and not world.state()["pending"]:
                        raise Interrupted()
                world.on_event = interrupt
                with self.assertRaises(Interrupted):
                    world.run("start", "-58", "-58")
                world.on_event = None
                world.restart()
                world.assert_complete()

    def test_restart_during_dig_drop_and_refuel(self):
        for event in ("before_dig", "after_dig", "before_drop", "after_drop", "before_refuel", "after_refuel"):
            with self.subTest(event=event):
                world = World()
                def interrupt(name):
                    if name == event and world.events[name] == 1:
                        raise Interrupted()
                world.on_event = interrupt
                with self.assertRaises(Interrupted):
                    world.run("start", "-58", "-58")
                world.on_event = None
                world.restart()
                world.assert_complete()

    def test_unlimited_fuel_move_recovery(self):
        world = World(fuel="unlimited")
        def interrupt(name):
            if name == "after_move" and world.events[name] == 10:
                raise Interrupted()
        world.on_event = interrupt
        with self.assertRaises(Interrupted):
            world.run("start", "-58", "-58")
        world.on_event = None
        with self.assertRaisesRegex(Exception, "Interrupted move"):
            world.restart()
        world.run("recover", "after")
        world.run("resume")
        world.assert_complete()

    def test_corrupt_state_refuses_to_move(self):
        world = World()
        world.files["/chunk_miner.state"] = "invalid"
        with self.assertRaisesRegex(Exception, "Damaged state"):
            world.run("resume")
        self.assertEqual(world.events["before_move"], 0)

    def test_missing_chest_waits_without_dropping(self):
        world = World()
        del world.blocks[(0, 0, -1)]
        world.items[0] = ["minecraft:cobblestone", 3]
        def replace(name):
            if name == "sleep" and "Waiting for the deposit" in world.logs[-1]:
                self.assertEqual(world.events["before_drop"], 0)
                world.blocks[(0, 0, -1)] = "minecraft:chest"
        world.on_event = replace
        world.run("start", "-58", "-58")
        world.assert_complete()

    def test_resume_finished_job_and_reset(self):
        world = World()
        world.run("start", "-58", "-58")
        moves = world.events["before_move"]
        world.restart()
        self.assertEqual(world.events["before_move"], moves)
        with self.assertRaisesRegex(Exception, "saved job exists"):
            world.run("start")
        world.run("reset")
        self.assertFalse(world.files)

    def test_restart_while_waiting_for_supplies(self):
        for message in ("Waiting for room", "Waiting for fuel"):
            with self.subTest(message=message):
                world = World(stack_limit=4)
                def interrupt(name):
                    if name == "after_move" and world.events[name] == 1:
                        if message == "Waiting for room":
                            world.chest_full = True
                        else:
                            world.fuel_supply = 0
                    if name == "sleep" and message in world.logs[-1]:
                        raise Interrupted()
                world.on_event = interrupt
                with self.assertRaises(Interrupted):
                    world.run("start", "-58", "-58")
                self.assertEqual(world.pos, (0, 0, 0))
                world.on_event = None
                world.chest_full = False
                world.fuel_supply = 10000
                world.restart()
                world.assert_complete()

    def test_falling_blocks_on_return_exhaust_reserve(self):
        world = World(stack_limit=1)
        injected = False
        freed = False
        def obstruct(name):
            nonlocal injected, freed
            if name == "before_move" and not injected and world.state()["phase"] == "home":
                target = world.target(None)
                if world.inside(target):
                    world.blocks[target] = "minecraft:gravel"
                    world.falling[target] = ["minecraft:gravel"] * 2
                    injected = True
            if name == "sleep" and "Free an inventory slot" in world.logs[-1] and not freed:
                item = world.items[0]
                world.drops[item[0]] += item[1]
                world.items[0] = None
                freed = True
        world.on_event = obstruct
        world.run("start", "-58", "-58")
        world.assert_complete()
        self.assertTrue(injected and freed)
        self.assertEqual(world.drops["minecraft:gravel"], 3)

    def test_protected_block_waits(self):
        world = World()
        world.blocks[(0, 0, 1)] = "minecraft:bedrock"
        def clear(name):
            if name == "sleep" and "Protected block" in world.logs[-1]:
                world.blocks.pop((0, 0, 1), None)
        world.on_event = clear
        world.run("start", "-58", "-58")
        world.assert_complete()
        self.assertEqual(world.digs["minecraft:deepslate"], 255)


if __name__ == "__main__":
    unittest.main()
