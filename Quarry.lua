local Coordinator = require("Coordinator")
local Vector = require("Vector")

local FUEL_RESERVE = 4
local FUEL_WAIT_SECONDS = 5
local UNLOAD_WAIT_SECONDS = 2
local LAST_SLOT = 16
local MOVE_ATTEMPTS = 8
local QUARRY_START_DISTANCE = 2

local args = {...}

local function positiveInteger(value, name)
    if value < 1 or value % 1 ~= 0 then
        error(name .. " must be a positive integer")
    end
end

local function parseArgs()
    local width = tonumber(args[1])
    if width == nil then
        error("Quarry requires a width argument")
    end

    local length = tonumber(args[2]) or width
    local depth = tonumber(args[3])

    positiveInteger(width, "Width")
    if args[2] ~= nil and tonumber(args[2]) == nil then
        error("Length must be a positive integer")
    end
    positiveInteger(length, "Length")
    if args[3] ~= nil and depth == nil then
        error("Depth must be a positive integer")
    end
    if depth ~= nil then
        positiveInteger(depth, "Depth")
    end

    return width, length, depth, depth == nil
end

local function copyVector(value)
    return Vector.new(value.x, value.y, value.z)
end

local function actionsFor(dir)
    if dir == Coordinator.Up then
        return turtle.detectUp, turtle.digUp, turtle.attackUp
    elseif dir == Coordinator.Down then
        return turtle.detectDown, turtle.digDown, turtle.attackDown
    end

    if not Coordinator.face(dir) then
        error("Unable to face " .. tostring(dir))
    end
    return turtle.detect, turtle.dig, turtle.attack
end

local function digToward(dir)
    local detect, dig, attack = actionsFor(dir)
    local failures = 0

    while detect() do
        if dig() then
            failures = 0
        else
            attack()
            failures = failures + 1
            if failures >= MOVE_ATTEMPTS then
                return false
            end
            sleep(0.2)
        end
    end

    return true
end

local function step(dir)
    for _ = 1, MOVE_ATTEMPTS do
        digToward(dir)
        if Coordinator.moveDir(dir) then
            return
        end

        local _, _, attack = actionsFor(dir)
        attack()
        sleep(0.2)
    end

    error("Unable to move " .. tostring(dir))
end

local function moveTo(target)
    while Coordinator.Pos.x < target.x do
        step(Coordinator.East)
    end
    while Coordinator.Pos.x > target.x do
        step(Coordinator.West)
    end
    while Coordinator.Pos.z < target.z do
        step(Coordinator.South)
    end
    while Coordinator.Pos.z > target.z do
        step(Coordinator.North)
    end
    while Coordinator.Pos.y < target.y do
        step(Coordinator.Up)
    end
    while Coordinator.Pos.y > target.y do
        step(Coordinator.Down)
    end
end

local function bedrockBelow()
    local found, block = turtle.inspectDown()
    return found and block.name == "minecraft:bedrock"
end

local function lastSlotFull()
    return turtle.getItemCount(LAST_SLOT) > 0
end

local function lowFuel()
    local fuel = turtle.getFuelLevel()
    return fuel ~= "unlimited" and fuel <= Coordinator.distanceToOrigin() + FUEL_RESERVE
end

local function goHome()
    moveTo(Coordinator.Origin)
end

local function selectEmptySlot()
    for slot = 1, LAST_SLOT do
        if turtle.getItemCount(slot) == 0 then
            turtle.select(slot)
            return true
        end
    end
    return false
end

local function refuelAtHome(requiredFuel)
    if turtle.getFuelLevel() == "unlimited" then
        return
    end

    while turtle.getFuelLevel() < requiredFuel do
        if not selectEmptySlot() then
            error("No empty inventory slot available for fuel")
        end

        if turtle.suckUp() then
            if not turtle.refuel() then
                error("Fuel chest contains a non-fuel item")
            end
        else
            print("Waiting for fuel above the origin")
            sleep(FUEL_WAIT_SECONDS)
        end
    end
end

local function restoreResume(resumePos, resumeDir)
    moveTo(resumePos)
    if not Coordinator.face(resumeDir) then
        error("Unable to restore heading")
    end
end

local function refuel()
    local resumePos = copyVector(Coordinator.Pos)
    local resumeDir = Coordinator.LookDirection
    local resumeDistance = resumePos:GetMDist(Coordinator.Origin)
    local selectedSlot = turtle.getSelectedSlot()

    goHome()
    refuelAtHome(2 * resumeDistance + FUEL_RESERVE + 1)
    turtle.select(selectedSlot)
    restoreResume(resumePos, resumeDir)
end

local function dumpInventory()
    local selectedSlot = turtle.getSelectedSlot()

    if not Coordinator.face(Coordinator.South) then
        error("Unable to face the deposit chest")
    end

    for slot = 1, LAST_SLOT do
        turtle.select(slot)
        while turtle.getItemCount(slot) > 0 do
            if not turtle.drop() then
                print("Waiting for space in the deposit chest")
                sleep(UNLOAD_WAIT_SECONDS)
            end
        end
    end

    if not Coordinator.face(Coordinator.North) then
        error("Unable to face North")
    end
    turtle.select(selectedSlot)
end

local function unload()
    local resumePos = copyVector(Coordinator.Pos)
    local resumeDir = Coordinator.LookDirection
    local resumeDistance = resumePos:GetMDist(Coordinator.Origin)

    goHome()
    dumpInventory()
    refuelAtHome(2 * resumeDistance + FUEL_RESERVE + 1)
    restoreResume(resumePos, resumeDir)
end

local function handleIncidents()
    if lastSlotFull() then
        unload()
    end
    if lowFuel() then
        refuel()
    end
end

local function miningStep(dir)
    handleIncidents()
    step(dir)
end

local function finish(homePos)
    goHome()
    dumpInventory()
    Coordinator.Pos = copyVector(homePos)
end

local width, length, depth, digToBedrock = parseArgs()
local homePos = copyVector(Coordinator.Pos)
local homeDir = Coordinator.LookDirection
local layer = 1
local hitBedrock = false

for _ = 1, QUARRY_START_DISTANCE do
    miningStep(Coordinator.North)
end
miningStep(Coordinator.Down)

while true do
    local targets = {}
    for col = 0, width - 1 do
        if col % 2 == 0 then
            for row = 0, length - 1 do
                targets[#targets + 1] = Vector.new(col, -layer, -QUARRY_START_DISTANCE - row)
            end
        else
            for row = length - 1, 0, -1 do
                targets[#targets + 1] = Vector.new(col, -layer, -QUARRY_START_DISTANCE - row)
            end
        end
    end

    if layer % 2 == 0 then
        local reversed = {}
        for index = #targets, 1, -1 do
            reversed[#reversed + 1] = targets[index]
        end
        targets = reversed
    end

    for _, target in ipairs(targets) do
        if Coordinator.Pos ~= target then
            handleIncidents()
            moveTo(target)
        end
        if bedrockBelow() then
            hitBedrock = true
        end
    end

    local completedDepth = not digToBedrock and layer >= depth
    if hitBedrock or completedDepth then
        break
    end

    miningStep(Coordinator.Down)
    layer = layer + 1
end

finish(homePos)
