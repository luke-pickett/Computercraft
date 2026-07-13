local Vector = require("Vector")   -- module name, no ".lua", no path

local a = Vector.new(1, 2, 3)
local b = Vector.new(4, 6, 3)

print(a:GetMDist(b))   --> 3 + 4 + 0 = 7
