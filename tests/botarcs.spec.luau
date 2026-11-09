--!strict
local Arcs = require("../src/shared/Rules/BotArcs")
local Crew = require("../src/shared/Rules/BotCrew")

local CFG = { half = 10, maxHalf = 30, reach = 300, close = 30, extra = 2, margin = 5, steps = 10 }

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["feel: a round inside the arc leaves it, one outside widens it, never past maxHalf"] = function()
		local a = Arcs.new(0, 0, 0, 1, CFG)
		Arcs.feel(a, 5, 2, CFG)
		assert(near(a.yaw, 0) and near(a.half, 10) and a.at == 2)
		Arcs.feel(a, 30, 3, CFG)
		assert(near(a.yaw, 10) and near(a.half, 20))
		Arcs.feel(a, -80, 4, CFG)
		assert(a.half == 30)
	end,
	["inside: within its yaw and reach, across the wrap at 180 too"] = function()
		local a = Arcs.new(0, 0, 0, 0, CFG)
		assert(Arcs.inside(a, 0, 100, CFG))
		assert(not Arcs.inside(a, 100, 0, CFG))
		assert(not Arcs.inside(a, 0, 400, CFG))
		local back = Arcs.new(0, 0, 175, 0, CFG)
		assert(Arcs.inside(back, -5, -100, CFG))
	end,
	["detour: walking at a goal in the arc it goes by a point off the edge, reached outside the arc"] = function()
		local a = Arcs.new(0, 0, 0, 0, CFG)
		local x, z = Arcs.detour(a, 0, 400, 0, 100, CFG)
		assert(x and z)
		assert(not Arcs.inside(a, x :: number, z :: number, CFG))
		for t = 0, 1, 0.05 do
			assert(not Arcs.inside(a, (x :: number) * t, 400 + ((z :: number) - 400) * t, CFG))
		end
	end,
	["detour: from one side of the fan to the other there's no way round"] = function()
		local a = Arcs.new(0, 0, 0, 0, CFG)
		assert(Arcs.detour(a, -60, 150, 60, 150, CFG) == nil)
	end,
	["detour: none for a short walk, one that misses it, or one starting in it"] = function()
		local a = Arcs.new(0, 0, 0, 0, CFG)
		assert(Arcs.detour(a, -10, 150, 10, 150, CFG) == nil)
		assert(Arcs.detour(a, 100, 0, 200, 0, CFG) == nil)
		assert(Arcs.detour(a, 0, 150, 200, 150, CFG) == nil)
	end,
	["detour: none when going round is too long"] = function()
		local wide = Arcs.new(0, 0, 0, 0, CFG)
		wide.half = 30
		local tight = { reach = 300, close = 30, extra = 1.01, margin = 5, steps = 10 }
		assert(Arcs.detour(wide, 0, 400, 0, 100, tight) == nil)
	end,
	["offLine: the distance from the shot's line, only as far as it flew"] = function()
		assert(near(Arcs.offLine(0, 0, 100, 0, 50, 7), 7))
		assert(near(Arcs.offLine(0, 0, 100, 0, 110, 0), 10))
	end,
	["sweep: there and back within half each way"] = function()
		local c = { half = 8, period = 4 }
		assert(near(Crew.sweep(0, c), 0))
		assert(near(Crew.sweep(1, c), 8))
		assert(near(Crew.sweep(2, c), 0))
		assert(near(Crew.sweep(3, c), -8))
		assert(near(Crew.sweep(4, c), 0))
	end,
	["lineClear: an own soldier by the line or just past the target holds it, one to the side doesn't"] = function()
		assert(not Crew.lineClear(0, 0, 100, 0, { { x = 50, z = 3 } }, 6, 1.2))
		assert(not Crew.lineClear(0, 0, 100, 0, { { x = 115, z = 0 } }, 6, 1.2))
		assert(Crew.lineClear(0, 0, 100, 0, { { x = 50, z = 20 } }, 6, 1.2))
		assert(Crew.lineClear(0, 0, 100, 0, {}, 6, 1.2))
	end,
}
