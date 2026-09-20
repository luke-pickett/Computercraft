local args = {...}
local FILE = "/chunk_miner.state"
local WIDTH = 16
local RESERVE = 8
local EMPTY_RESERVE = 2
local offsets = {{0, 0, 1}, {-1, 0, 0}, {0, 0, -1}, {1, 0, 0}, {0, 1, 0}, {0, -1, 0}}
local names = {"into the chunk", "right of the starting heading", "toward home", "left of the starting heading"}
local state
local plan

local function integer(value)
    return type(value) == "number" and value % 1 == 0
end

local function copy(pos)
    return {x = pos.x, y = pos.y, z = pos.z}
end

local function same(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z
end

local function key(pos)
    return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function home(pos)
    return pos.x == 0 and pos.y == 0 and pos.z == 0
end

local function index(pos)
    if pos.x < 0 or pos.x >= WIDTH or pos.z < 1 or pos.z > WIDTH
        or pos.y < 0 or pos.y > state.top - state.bottom then
        return nil
    end
    return pos.y * WIDTH * WIDTH + pos.x * WIDTH + pos.z
end

local function validPosition(pos)
    return type(pos) == "table" and integer(pos.x) and integer(pos.y)
        and integer(pos.z) and (home(pos) or index(pos) ~= nil)
end

local function cleared(pos)
    local cell = index(pos)
    return home(pos) or (cell and state.cleared:sub(cell, cell) == "1")
end

local function markCleared(pos)
    local cell = index(pos)
    if cell then
        state.cleared = state.cleared:sub(1, cell - 1) .. "1" .. state.cleared:sub(cell + 1)
    end
end

local function checksum(text)
    local a, b = 1, 0
    for i = 1, #text do
        a = (a + text:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local function save()
    state.sequence = state.sequence + 1
    local data = textutils.serialize(state, {compact = true})
    local handle = assert(fs.open(FILE .. ".tmp", "w"))
    handle.write(tostring(checksum(data)) .. "\n" .. data)
    handle.flush()
    handle.close()
    if fs.exists(FILE .. ".bak") then
        fs.delete(FILE .. ".bak")
    end
    if fs.exists(FILE) then
        fs.move(FILE, FILE .. ".bak")
    end
    fs.move(FILE .. ".tmp", FILE)
end

local function loadState()
    local best
    local found = false
    for _, suffix in ipairs({"", ".bak", ".tmp"}) do
        local file = FILE .. suffix
        if fs.exists(file) then
            found = true
            local handle = assert(fs.open(file, "r"))
            local expected = tonumber(handle.readLine())
            local data = handle.readAll()
            handle.close()
            local value = expected == checksum(data) and textutils.unserialize(data)
            if type(value) == "table" and integer(value.sequence) then
                if not best or value.sequence > best.sequence then
                    best = value
                end
            elseif suffix ~= ".tmp" then
                error("Damaged state file: " .. file .. ". Restore a verified backup; do not guess position.")
            end
        end
    end
    if found and not best then
        error("No complete state file. Check the turtle position before removing the damaged state.")
    end
    return best
end

local function makePlan()
    local result = {}
    for y = 0, state.top - state.bottom do
        result[#result + 1] = {x = 0, y = y, z = 1}
    end
    for y = state.top - state.bottom, 0, -1 do
        local layer = {}
        for x = 0, WIDTH - 1 do
            for row = 1, WIDTH do
                layer[#layer + 1] = {x = x, y = y, z = x % 2 == 0 and row or WIDTH + 1 - row}
            end
        end
        if (state.top - state.bottom - y) % 2 == 0 then
            for i = 1, #layer do result[#result + 1] = layer[i] end
        else
            for i = #layer, 1, -1 do result[#result + 1] = layer[i] end
        end
    end
    return result
end

local function validate()
    assert(state.version == 1 and integer(state.sequence), "Unsupported state format")
    assert(integer(state.bottom) and integer(state.top) and state.bottom >= -64
        and state.top <= 319 and state.bottom <= state.top, "Invalid saved heights")
    assert(type(state.cleared) == "string" and #state.cleared == WIDTH * WIDTH * (state.top - state.bottom + 1)
        and not state.cleared:find("[^01]"), "Invalid saved chunk map")
    assert(validPosition(state.pos) and cleared(state.pos), "Invalid saved position")
    assert(integer(state.heading) and state.heading >= 1 and state.heading <= 4, "Invalid saved heading")
    assert(({mine = true, home = true, unload = true, fuel = true, done = true})[state.phase], "Invalid saved phase")
    plan = makePlan()
    assert(integer(state.cursor) and state.cursor >= 1 and state.cursor <= #plan + 1, "Invalid saved progress")
    if state.pending then
        local pending = state.pending
        assert(pending.kind == "move" or pending.kind == "turn", "Invalid pending action")
        if pending.kind == "move" then
            assert(validPosition(pending.to) and (pending.fuel == "unlimited" or integer(pending.fuel)), "Invalid pending move")
            assert(math.abs(state.pos.x - pending.to.x) + math.abs(state.pos.y - pending.to.y)
                + math.abs(state.pos.z - pending.to.z) == 1, "Invalid pending destination")
        else
            assert(integer(pending.to) and pending.to >= 1 and pending.to <= 4, "Invalid pending turn")
        end
    end
end

local function finishPending(success)
    if success then
        if state.pending.kind == "move" then
            state.pos = copy(state.pending.to)
            markCleared(state.pos)
        else
            state.heading = state.pending.to
        end
    end
    state.pending = nil
    save()
end

local function recover(choice)
    if not state.pending then
        assert(not choice, "There is no interrupted action to recover")
        return
    end
    if choice then
        assert(choice == "before" or choice == "after", "Use recover before or recover after")
        finishPending(choice == "after")
        return
    end
    local pending = state.pending
    if pending.kind == "move" and type(pending.fuel) == "number" then
        local fuel = turtle.getFuelLevel()
        if fuel == pending.fuel or fuel == pending.fuel - 1 then
            finishPending(fuel == pending.fuel - 1)
            return
        end
    end
    if pending.kind == "turn" then
        print("Before: facing " .. names[state.heading])
        print("After: facing " .. names[pending.to])
    else
        print("Before: " .. key(state.pos) .. "; after: " .. key(pending.to))
    end
    error("Interrupted " .. pending.kind .. ". Check the turtle, then run ChunkMiner recover before OR after, followed by ChunkMiner resume.")
end

local function turn(right)
    local nextHeading = right and state.heading % 4 + 1 or (state.heading + 2) % 4 + 1
    state.pending = {kind = "turn", to = nextHeading}
    save()
    local success = right and turtle.turnRight() or (not right and turtle.turnLeft())
    finishPending(success)
    assert(success, "Unable to turn; resume when the obstruction is resolved")
end

local function face(dir)
    local delta = (dir - state.heading) % 4
    if delta == 3 then
        turn(false)
    else
        for _ = 1, delta do turn(true) end
    end
end

local function neighbor(pos, dir)
    local offset = offsets[dir]
    return {x = pos.x + offset[1], y = pos.y + offset[2], z = pos.z + offset[3]}
end

local function route(from, target)
    if same(from, target) then return {} end
    local queue = {copy(from)}
    local seen = {[key(from)] = true}
    local previous = {}
    local head = 1
    while head <= #queue do
        local pos = queue[head]
        head = head + 1
        for dir = 1, 6 do
            local nextPos = neighbor(pos, dir)
            local id = key(nextPos)
            if not seen[id] and (cleared(nextPos) or same(nextPos, target)) then
                seen[id] = true
                previous[id] = {pos = pos, dir = dir}
                if same(nextPos, target) then
                    local reversed = {}
                    local current = nextPos
                    while not same(current, from) do
                        local entry = previous[key(current)]
                        reversed[#reversed + 1] = entry.dir
                        current = entry.pos
                    end
                    local result = {}
                    for i = #reversed, 1, -1 do result[#result + 1] = reversed[i] end
                    return result
                end
                queue[#queue + 1] = nextPos
            end
        end
    end
    error("No recorded cleared route. Stop and inspect the saved state.")
end

local function emptySlots()
    local count = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            count = count + 1
            turtle.select(slot)
        end
    end
    return count
end

local function inventoryPresent(inspect, side)
    local found, block = inspect()
    return found and (block.name == "minecraft:chest" or block.name == "minecraft:trapped_chest"
        or block.name == "minecraft:barrel" or peripheral.hasType(side, "inventory"))
end

local function refuelItems(required)
    if turtle.getFuelLevel() == "unlimited" then return true end
    for slot = 1, 16 do
        turtle.select(slot)
        while turtle.getFuelLevel() < required and turtle.refuel(1) do end
    end
    return turtle.getFuelLevel() >= required
end

local function actions(dir)
    if dir == 5 then return turtle.inspectUp, turtle.digUp, turtle.up, "top" end
    if dir == 6 then return turtle.inspectDown, turtle.digDown, turtle.down, "bottom" end
    face(dir)
    return turtle.inspect, turtle.dig, turtle.forward, "front"
end

local function step(dir, returning)
    local target = neighbor(state.pos, dir)
    assert(validPosition(target), "Refusing to leave the chunk or home cell")
    local inspect, dig, move, side = actions(dir)
    while true do
        local distance = #route(state.pos, {x = 0, y = 0, z = 0})
        local fuel = turtle.getFuelLevel()
        if not returning and (emptySlots() <= EMPTY_RESERVE or (fuel ~= "unlimited" and fuel < distance + RESERVE + 2)) then
            return false
        end
        if fuel ~= "unlimited" and fuel < 1 then
            print("Out of fuel: insert fuel into the turtle to continue")
            while not refuelItems(math.max(1, distance)) do sleep(2) end
        end
        local found, block = inspect()
        if found and block.name ~= "minecraft:water" and block.name ~= "minecraft:lava" then
            if inventoryPresent(inspect, side) or block.name:find("turtle", 1, true) or block.name == "minecraft:bedrock" then
                print("Protected block at " .. key(target) .. "; clear the route to continue")
                sleep(2)
            elseif emptySlots() == 0 then
                print("Free an inventory slot so the return route can be cleared")
                sleep(2)
            elseif dig() then
                sleep(0.5)
            else
                print("Cannot dig at " .. key(target) .. "; clear the obstruction to continue")
                sleep(2)
            end
        else
            state.pending = {kind = "move", to = target, fuel = turtle.getFuelLevel()}
            save()
            local success = move()
            finishPending(success)
            if success then return true end
            print("Movement blocked at " .. key(target) .. "; retrying")
            sleep(0.5)
        end
    end
end

local function phase(value)
    state.phase = value
    save()
end

local function unload()
    assert(home(state.pos), "Cannot unload away from home")
    face(3)
    for slot = 1, 16 do
        turtle.select(slot)
        while turtle.getItemCount(slot) > 0 do
            if not inventoryPresent(turtle.inspect, "front") then
                print("Waiting for the deposit inventory behind start")
                sleep(2)
            else
                turtle.drop()
                if turtle.getItemCount(slot) > 0 then
                    print("Waiting for room in the deposit inventory")
                    sleep(2)
                end
            end
        end
    end
    face(1)
end

local function refuelAtHome()
    local target = plan[state.cursor]
    local distance = target and #route(state.pos, target) or 0
    local minimum = 2 * distance + RESERVE + 2
    local fuel = turtle.getFuelLevel()
    if fuel ~= "unlimited" then
        local limit = turtle.getFuelLimit()
        assert(limit >= minimum, "Fuel capacity is too small for a safe round trip")
        local required = math.min(limit, math.max(256, minimum + 32))
        while not refuelItems(required) do
            if emptySlots() > 0 and inventoryPresent(turtle.inspectUp, "top") then
                turtle.suckUp(1)
            end
            if not refuelItems(required) then
                if emptySlots() == 0 then
                    print("Remove non-fuel items from the turtle and fuel chest")
                else
                    print("Waiting for fuel above start or inserted into the turtle")
                end
                sleep(2)
            end
        end
    end
    unload()
end

local function usage()
    print("ChunkMiner start [bottomY topY]  (defaults: -58 -48)")
    print("Start one block behind the chunk at bottomY, facing in; chunk extends left.")
    print("Deposit behind start; fuel above start.")
    print("ChunkMiner resume | status | recover before|after | reset")
end

local command = args[1] or "resume"
if command == "--help" or command == "help" then usage() return end
assert(({start = true, resume = true, status = true, recover = true, reset = true})[command], "Unknown command; use ChunkMiner --help")
state = loadState()
if command == "start" then
    assert(not state, "A saved job exists. Use resume, or reset a completed job first.")
    assert(#args == 1 or #args == 3, "Use ChunkMiner start [bottomY topY]")
    local bottom, top = tonumber(args[2] or -58), tonumber(args[3] or -48)
    assert(integer(bottom) and integer(top) and bottom >= -64 and top <= 319 and bottom <= top, "Invalid Y range")
    state = {version = 1, sequence = 0, bottom = bottom, top = top, pos = {x = 0, y = 0, z = 0},
        heading = 1, phase = "unload", cursor = 1, cleared = string.rep("0", WIDTH * WIDTH * (top - bottom + 1))}
    save()
else
    if not state then
        print("No saved chunk job. Place the turtle at home, then run ChunkMiner start.")
        return
    end
end
validate()
if command == "status" then
    local _, count = state.cleared:gsub("1", "")
    print("Phase: " .. state.phase .. "; cleared " .. count .. "/" .. #state.cleared)
    print("Position: left=" .. state.pos.x .. ", Y=" .. state.bottom + state.pos.y .. ", forward=" .. state.pos.z)
    print("Facing " .. names[state.heading])
    if state.pending then print("Unresolved " .. state.pending.kind .. "; resume will check recovery") end
    return
end
if command == "reset" then
    assert(state.phase == "done" and home(state.pos) and not state.pending, "Only a completed job at home may be reset")
    for _, suffix in ipairs({"", ".bak", ".tmp"}) do
        if fs.exists(FILE .. suffix) then fs.delete(FILE .. suffix) end
    end
    print("Completed job removed. Reposition the turtle before starting a new chunk.")
    return
end
if command == "recover" then
    assert(#args == 2, "Use recover before or recover after")
    recover(args[2])
    print("Recovery recorded. Run ChunkMiner resume.")
    return
end
recover()
local origin = {x = 0, y = 0, z = 0}
while state.phase ~= "done" do
    if state.phase == "mine" then
        while state.cursor <= #plan and cleared(plan[state.cursor]) do
            state.cursor = state.cursor + 1
        end
        save()
        if state.cursor > #plan then
            phase("home")
        else
            local path = route(state.pos, plan[state.cursor])
            for _, dir in ipairs(path) do
                if not step(dir, false) then
                    phase("home")
                    break
                end
            end
        end
    elseif state.phase == "home" then
        for _, dir in ipairs(route(state.pos, origin)) do step(dir, true) end
        phase("unload")
    elseif state.phase == "unload" then
        unload()
        phase(state.cursor > #plan and "done" or "fuel")
    elseif state.phase == "fuel" then
        assert(home(state.pos), "Cannot refuel away from home")
        refuelAtHome()
        phase("mine")
    end
end
print("Chunk complete. Home, facing into the chunk, and fully unloaded.")
