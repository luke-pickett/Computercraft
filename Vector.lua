local Vector = {}

Vector.__index = Vector

function Vector.new(x, y, z)
    local self = setmetatable({}, Vector)
    self.x = x
    self.y = y
    self.z = z
    return self
end

function Vector.__add(a, b)
    return Vector.new(a.x + b.x, a.y + b.y, a.z + b.z)
end

function Vector.__sub(a, b)
    return Vector.new(a.x - b.x, a.y - b.y, a.z - b.z)
end

function Vector.__eq(a, b)
    return a.x == b.x and a.y == b.y and a.z == b.z
end

function Vector.__tostring(self)
    return "(" .. self.x .. ", " .. self.y .. ", " .. self.z .. ")"
end

function Vector:GetMDist(comparingVector)
    local xDist = math.abs(self.x - comparingVector.x)
    local yDist = math.abs(self.y - comparingVector.y)
    local zDist = math.abs(self.z - comparingVector.z)
    return xDist + yDist + zDist
end

return Vector
