local Coordinator = require("Coordinator")

local FUEL_BUFFER = 8
local FUEL_WAIT_SECONDS = 5

local function opposite(direction)
    local directions = {
        [Coordinator.North] = Coordinator.South,
        [Coordinator.East] = Coordinator.West,
        [Coordinator.South] = Coordinator.North,
        [Coordinator.West] = Coordinator.East,
    }
    return directions[direction]
end

local function copyPosition(position)
    return {
        x = position.x,
        y = position.y,
        z = position.z,
    }
end

local function inventoryIsFull()
    for slot = 1, 16 do
        if turtle.getItemSpace(slot) > 0 then
            return false
        end
    end
    return true
end

local function checkFuel()
    local fuel = turtle.getFuelLevel()
    if fuel ~= "unlimited" and fuel < 1 then
        error("Out of fuel")
    end
end

local function firstEmptySlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then
            return slot
        end
    end
    return nil
end

local function needsRefuel()
    return not Coordinator.canReturnToOrigin(Coordinator.distanceToOrigin() + FUEL_BUFFER)
end

local function clearBlock(direction)
    local detect
    local dig
    local attack

    if direction == Coordinator.Up then
        detect = turtle.detectUp
        dig = turtle.digUp
        attack = turtle.attackUp
    elseif direction == Coordinator.Down then
        detect = turtle.detectDown
        dig = turtle.digDown
        attack = turtle.attackDown
    else
        if not Coordinator.face(direction) then
            error("Unable to turn")
        end
        detect = turtle.detect
        dig = turtle.dig
        attack = turtle.attack
    end

    while detect() do
        if not dig() then
            attack()
            if detect() then
                error("Unable to clear block")
            end
        end
    end
end

local moveTo
local unload
local refuel

local function move(direction, unloading)
    if not unloading then
        if inventoryIsFull() then
            unload()
        end
        if needsRefuel() then
            refuel()
        end
    end

    for _ = 1, 5 do
        checkFuel()
        clearBlock(direction)
        if Coordinator.moveDir(direction) then
            return
        end

        if direction == Coordinator.Up then
            turtle.attackUp()
        elseif direction == Coordinator.Down then
            turtle.attackDown()
        else
            turtle.attack()
        end
    end

    error("Unable to move")
end

moveTo = function(target, unloading)
    while Coordinator.Pos.x < target.x do
        move(Coordinator.East, unloading)
    end
    while Coordinator.Pos.x > target.x do
        move(Coordinator.West, unloading)
    end
    while Coordinator.Pos.z < target.z do
        move(Coordinator.South, unloading)
    end
    while Coordinator.Pos.z > target.z do
        move(Coordinator.North, unloading)
    end
    while Coordinator.Pos.y < target.y do
        move(Coordinator.Up, unloading)
    end
    while Coordinator.Pos.y > target.y do
        move(Coordinator.Down, unloading)
    end
end

local homePosition = copyPosition(Coordinator.Pos)
local homeDirection = Coordinator.LookDirection

unload = function()
    local resumePosition = copyPosition(Coordinator.Pos)
    local resumeDirection = Coordinator.LookDirection
    local selectedSlot = turtle.getSelectedSlot()

    moveTo(homePosition, true)
    if not Coordinator.face(opposite(homeDirection)) then
        error("Unable to turn toward inventory")
    end

    for slot = 1, 16 do
        turtle.select(slot)
        while turtle.getItemCount(slot) > 0 do
            if not turtle.drop() then
                error("Inventory behind turtle is full or missing")
            end
        end
    end

    turtle.select(selectedSlot)
    moveTo(resumePosition, true)
    if not Coordinator.face(resumeDirection) then
        error("Unable to restore direction")
    end
end

refuel = function()
    local resumePosition = copyPosition(Coordinator.Pos)
    local resumeDirection = Coordinator.LookDirection
    local selectedSlot = turtle.getSelectedSlot()

    moveTo(homePosition, true)

    local homeToResume = Coordinator.Origin:GetMDist(resumePosition)
    local targetFuel = homeToResume * 2 + FUEL_BUFFER

    while turtle.getFuelLevel() ~= "unlimited"
            and turtle.getFuelLevel() < targetFuel do
        local slot = firstEmptySlot()
        if slot then
            turtle.select(slot)
        end

        local refueled = false
        if turtle.suckUp() then
            refueled = turtle.refuel()
        end

        if not refueled then
            print("Waiting for fuel above the turtle...")
            sleep(FUEL_WAIT_SECONDS)
        end
    end

    turtle.select(selectedSlot)
    moveTo(resumePosition, true)
    if not Coordinator.face(resumeDirection) then
        error("Unable to restore direction")
    end
end

print("Quarry size:")
local size = tonumber(read())

if size == nil or size < 1 or size % 1 ~= 0 then
    error("Size must be a positive whole number")
end

print("Depth (number or x for bedrock):")
local depthInput = string.lower(read())
local depth = tonumber(depthInput)
local digToBedrock = depthInput == "x"

if not digToBedrock and (depth == nil or depth < 1 or depth % 1 ~= 0) then
    error("Depth must be a positive whole number or x")
end

local y = 0
while digToBedrock or y < depth do
    if y > 0 and digToBedrock then
        moveTo({
            x = homePosition.x,
            y = homePosition.y - y + 1,
            z = homePosition.z - 1,
        })

        local hasBlock, block = turtle.inspectDown()
        if hasBlock and block.name == "minecraft:bedrock" then
            break
        end
    end

    for x = 0, size - 1 do
        local zStart = 1
        local zEnd = size
        local zStep = 1

        if x % 2 == 1 then
            zStart = size
            zEnd = 1
            zStep = -1
        end

        for z = zStart, zEnd, zStep do
            moveTo({
                x = homePosition.x + x,
                y = homePosition.y - y,
                z = homePosition.z - z,
            })
        end
    end

    y = y + 1
end

if inventoryIsFull() then
    unload()
end
