local args = {...}
local repeatPasses = args[1] == "loop"
local delay = tonumber(args[2]) or 60
local sapling = args[3] or "minecraft:oak_sapling"
local heading = 0
local height = 0
local harvested = 0

if args[1] and args[1] ~= "once" and args[1] ~= "loop" then
    print("Usage: TreeChopper [once|loop] [seconds] [sapling ID]")
    return
end
assert(delay >= 1, "The delay must be at least one second")
assert(turtle, "Run this program on a chopping or mining turtle")

local function isLog(block)
    return block and ((block.tags and block.tags["minecraft:logs"])
        or block.name:match("_log$") ~= nil)
end

local function isLeaves(block)
    return block and ((block.tags and block.tags["minecraft:leaves"])
        or block.name:match("_leaves$") ~= nil)
end

local function fuel()
    while turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < 1 do
        turtle.select(1)
        if not turtle.refuel(1) then
            print("Add fuel to slot 1. Retrying in 5 seconds.")
            sleep(5)
        end
    end
    turtle.select(3)
end

local function cargoSpace()
    while true do
        for slot = 3, 16 do
            if turtle.getItemCount(slot) == 0 then
                turtle.select(3)
                return
            end
        end
        print("Cargo full. Empty a slot from 3-16 to continue.")
        sleep(5)
    end
end

local function clear(inspect, dig)
    while true do
        local found, block = inspect()
        if not found then
            return
        end
        assert(isLog(block) or isLeaves(block), "Unexpected obstacle: " .. block.name)
        cargoSpace()
        local ok, reason = dig()
        assert(ok, reason or "Unable to clear tree block")
    end
end

local function move(action, inspect, dig)
    fuel()
    clear(inspect, dig)
    for _ = 1, 10 do
        if action() then
            return
        end
        clear(inspect, dig)
        sleep(0.5)
    end
    error("Movement blocked. Clear the turtle's path before restarting from home.")
end

local function forward()
    move(turtle.forward, turtle.inspect, turtle.dig)
end

local function up()
    move(turtle.up, turtle.inspectUp, turtle.digUp)
    height = height + 1
end

local function down()
    move(turtle.down, turtle.inspectDown, turtle.digDown)
    height = height - 1
end

local function face(direction)
    while heading ~= direction do
        assert(turtle.turnRight(), "Unable to turn")
        heading = (heading + 1) % 4
    end
end

local function plant()
    local found, block = turtle.inspectDown()
    if found and isLeaves(block) then
        clear(turtle.inspectDown, turtle.digDown)
        found = turtle.inspectDown()
    end
    if found then
        return
    end
    while true do
        for slot = 2, 16 do
            local item = turtle.getItemDetail(slot)
            if item and item.name == sapling then
                turtle.select(slot)
                local ok, reason = turtle.placeDown()
                assert(ok, reason or "Cannot plant: check soil below the plot")
                return
            end
        end
        print("Add " .. sapling .. " to slot 2. Retrying in 5 seconds.")
        sleep(5)
    end
end

local function harvest()
    local found, block = turtle.inspectDown()
    if found and isLog(block) then
        cargoSpace()
        assert(turtle.digDown(), "Unable to cut the trunk base")
        while true do
            local above, upper = turtle.inspectUp()
            if not above or not isLog(upper) then
                break
            end
            assert(height < 64, "Trunk exceeds the 64-block height limit")
            up()
        end
        while height > 1 do
            down()
        end
        harvested = harvested + 1
    end
    plant()
end

local function unload()
    face(2)
    if peripheral.hasType("front", "inventory") then
        for slot = 2, 16 do
            local item = turtle.getItemDetail(slot)
            if item and item.name ~= sapling then
                turtle.select(slot)
                while turtle.getItemCount(slot) > 0 do
                    if peripheral.hasType("front", "inventory") then
                        turtle.drop()
                    end
                    if turtle.getItemCount(slot) > 0 then
                        print("Empty or replace the deposit inventory behind home.")
                        sleep(5)
                    end
                end
            end
        end
    end
    face(0)
end

print("8x8 tree farm: plot extends forward and left.")
print("Slot 1: fuel. Slot 2: " .. sapling .. ". Slots 3-16: cargo.")
repeat
    harvested = 0
    up()
    forward()
    for column = 1, 8 do
        for row = 1, 8 do
            harvest()
            if row < 8 then
                forward()
            end
        end
        if column < 8 then
            face(3)
            forward()
            face(column % 2 == 1 and 2 or 0)
        end
    end
    face(2)
    forward()
    face(1)
    for _ = 1, 7 do
        forward()
    end
    face(0)
    down()
    unload()
    print("Pass complete. Harvested " .. harvested .. " trunks. Back at home.")
    if repeatPasses then
        sleep(delay)
    end
until not repeatPasses
