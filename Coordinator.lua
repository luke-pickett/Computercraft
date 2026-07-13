local Vector = require("Vector")

local Coordinator = {}

Coordinator.North = "North"
Coordinator.East = "East"
Coordinator.South = "South"
Coordinator.West = "West"
Coordinator.Up = "Up"
Coordinator.Down = "Down"

local ORDER = {
    Coordinator.North,
    Coordinator.East,
    Coordinator.South,
    Coordinator.West,
}

local INDEX = {}
for i, dir in ipairs(ORDER) do
    INDEX[dir] = i
end

local STEP = {
    [Coordinator.North] = Vector.new(0, 0, -1),
    [Coordinator.East] = Vector.new(1, 0, 0),
    [Coordinator.South] = Vector.new(0, 0, 1),
    [Coordinator.West] = Vector.new(-1, 0, 0),
    [Coordinator.Up] = Vector.new(0, 1, 0),
    [Coordinator.Down] = Vector.new(0, -1, 0),
}

Coordinator.Pos = Vector.new(0, 0, 0)
Coordinator.LookDirection = Coordinator.North

local function turnRight()
    if not turtle.turnRight() then
        return false
    end
    Coordinator.LookDirection = ORDER[INDEX[Coordinator.LookDirection] % 4 + 1]
    return true
end

local function turnLeft()
    if not turtle.turnLeft() then
        return false
    end
    Coordinator.LookDirection = ORDER[(INDEX[Coordinator.LookDirection] + 2) % 4 + 1]
    return true
end

function Coordinator.face(dir)
    if INDEX[dir] == nil then
        return false
    end

    local turns = (INDEX[dir] - INDEX[Coordinator.LookDirection]) % 4
    if turns == 3 then
        return turnLeft()
    end

    for _ = 1, turns do
        if not turnRight() then
            return false
        end
    end
    return true
end

function Coordinator.moveDir(dir)
    local step = STEP[dir]
    if step == nil then
        return false
    end

    local moved
    if dir == Coordinator.Up then
        moved = turtle.up()
    elseif dir == Coordinator.Down then
        moved = turtle.down()
    else
        if not Coordinator.face(dir) then
            return false
        end
        moved = turtle.forward()
    end

    if not moved then
        return false
    end

    Coordinator.Pos = Coordinator.Pos + step
    return true
end

return Coordinator
