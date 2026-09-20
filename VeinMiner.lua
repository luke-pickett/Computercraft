local args = {...}
local RESERVE = 4
local EMPTY_RESERVE = 4
local heading = 1
local selected = turtle.getSelectedSlot()
local offsets = {{0, 0, -1}, {1, 0, 0}, {0, 0, 1}, {-1, 0, 0}, {0, 1, 0}, {0, -1, 0}}
local opposite = {3, 4, 1, 2, 6, 5}
local targets = {}
local visited = {["0,0,0"] = true, ["0,0,1"] = true, ["0,1,0"] = true}
local path = {{x = 0, y = 0, z = 0, next = 1}}

local function face(dir)
    local turns = (dir - heading) % 4
    if turns == 3 then
        assert(turtle.turnLeft(), "Unable to turn left")
        heading = (heading + 2) % 4 + 1
    else
        for _ = 1, turns do
            assert(turtle.turnRight(), "Unable to turn right")
            heading = heading % 4 + 1
        end
    end
end

local function actions(dir)
    if dir == 5 then
        return turtle.inspectUp, turtle.digUp, turtle.up
    elseif dir == 6 then
        return turtle.inspectDown, turtle.digDown, turtle.down
    end
    face(dir)
    return turtle.inspect, turtle.dig, turtle.forward
end

local function storage()
    local empty = 0
    for slot = 2, 16 do
        if turtle.getItemCount(slot) == 0 then
            empty = empty + 1
            turtle.select(slot)
        end
    end
    return empty
end

local function fuelFor(required)
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then
        return true
    end
    turtle.select(1)
    while fuel < required and turtle.refuel(1) do
        fuel = turtle.getFuelLevel()
    end
    storage()
    return fuel >= required
end

local function inventoryBlock(block, side)
    return block.name == "minecraft:chest"
        or block.name == "minecraft:trapped_chest"
        or block.name == "minecraft:barrel"
        or peripheral.hasType(side, "inventory")
end

local function depositPresent()
    local found, block = turtle.inspect()
    return found and inventoryBlock(block, "front")
end

local function enter(dir, returning)
    local inspect, dig, move = actions(dir)
    local failures = 0
    local digs = 0
    while true do
        if not returning then
            if storage() <= EMPTY_RESERVE then
                return false, "Inventory reserve reached"
            end
            if not fuelFor(#path + 1 + RESERVE) then
                return false, "Fuel reserve reached"
            end
        elseif not fuelFor(#path - 1) then
            print("Add fuel to slot 1 to continue home")
            sleep(2)
        end
        local found, block = inspect()
        if found then
            if block.name == "minecraft:bedrock" or block.name:find("turtle", 1, true)
                or inventoryBlock(block, dir == 5 and "top" or dir == 6 and "bottom" or "front") then
                return false, "Protected block obstructs the route"
            end
            if storage() == 0 then
                if not returning then
                    return false, "Inventory full"
                end
                print("Free an inventory slot to clear the route home")
                sleep(2)
            elseif dig() then
                digs = digs + 1
                failures = 0
                sleep(0.5)
            else
                failures = failures + 1
                sleep(0.5)
            end
        elseif move() then
            return true
        else
            failures = failures + 1
            sleep(0.5)
        end
        if failures >= 8 or (not returning and digs >= 128) then
            return false, "Route remains obstructed"
        end
    end
end

local function backtrack()
    local node = path[#path]
    local moved, reason = enter(opposite[node.from], true)
    while not moved do
        print(reason .. "; clear the route home, then wait")
        sleep(2)
        moved, reason = enter(opposite[node.from], true)
    end
    table.remove(path)
end

if args[1] == "--help" then
    print("VeinMiner [block_id ...]")
    print("Face the vein; put a chest behind and fuel in slot 1.")
    return
end

for _, name in ipairs(args) do
    if not name:match("^[%w_%-]+:[%w_/%-%.]+$") then
        error("Expected block IDs such as minecraft:iron_ore")
    end
    targets[name] = true
end

if #args == 0 then
    local found, block = turtle.inspect()
    if not found then
        error("Face a vein or provide explicit block IDs")
    end
    targets[block.name] = true
    print("Following " .. block.name)
end

face(3)
local hasDeposit = depositPresent()
face(1)
if not hasDeposit then
    error("Place a chest or inventory directly behind the start")
end

local reason = "Vein complete"
while #path > 0 do
    local node = path[#path]
    if storage() <= EMPTY_RESERVE then
        reason = "Inventory reserve reached"
        break
    end
    if not fuelFor(#path + 1 + RESERVE) then
        reason = "Fuel reserve reached"
        break
    end
    if node.next > 6 then
        if #path == 1 then
            break
        end
        backtrack()
    else
        local dir = node.next
        node.next = dir + 1
        local offset = offsets[dir]
        local x, y, z = node.x + offset[1], node.y + offset[2], node.z + offset[3]
        local key = x .. "," .. y .. "," .. z
        if not visited[key] then
            local inspect = actions(dir)
            local found, block = inspect()
            if found and targets[block.name] then
                local moved, failure = enter(dir, false)
                if not moved then
                    reason = failure
                    break
                end
                visited[key] = true
                path[#path + 1] = {x = x, y = y, z = z, next = 1, from = dir}
            end
        end
    end
end

while #path > 1 do
    backtrack()
end
face(3)
for slot = 1, 16 do
    turtle.select(slot)
    while turtle.getItemCount(slot) > 0 do
        if not depositPresent() then
            print("Replace the deposit chest behind the start")
            sleep(2)
        elseif not turtle.drop() or turtle.getItemCount(slot) > 0 then
            print("Waiting for space in the deposit chest")
            sleep(2)
        end
    end
end
face(1)
turtle.select(selected)
print(reason .. ". Returned home and unloaded.")
