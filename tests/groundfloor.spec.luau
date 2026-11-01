--!strict
local D = require("../src/shared/Config/Damage")
local Blast = require("../src/shared/Rules/Blast")
local GroundFloor = require("../src/shared/Rules/GroundFloor")

local F = D.Blast.Crater.Floor

-- a column of 4-stud voxels from `y0`, solid up to `top`
local function column(y0: number, n: number, top: number): { number }
	local out = table.create(n, 0)
	for i = 1, n do
		out[i] = math.clamp((top - (y0 + (i - 1) * 4)) / 4, 0, 1)
	end
	return out
end

local function topOf(occs: { number }, y0: number): number
	local s = GroundFloor.span(occs, y0, 4)
	return s or y0
end

return {
	["the agreed shape: a kept bottom and a kept core, read from a range round the map"] = function()
		assert(F.minKeep > 0)
		assert(F.coreShare > 0 and F.coreShare < 1, "some ground can be cut, never all")
		assert(F.scanLow < -28 and F.scanHigh > 96, "covers Map1's terrain slab")
	end,
	["a column's ground runs from its lowest solid voxel's base to its highest's top"] = function()
		local s, b = GroundFloor.span({ 0, 1, 1, 0.5, 0 }, -8, 4)
		assert(s == 6 and b == -4)
		local none = GroundFloor.span({ 0, 0 }, 0, 4)
		assert(none == nil)
	end,
	["the floor follows thickness, not height"] = function()
		local c = { minKeep = 12, coreShare = 0.75 }
		-- the same thickness keeps the same depth wherever it stands
		local low = GroundFloor.floor(-4, -28, c)
		local high = GroundFloor.floor(196, 172, c)
		assert(math.abs((-4 - low) - (196 - high)) < 1e-9)
		-- thin ground keeps its bottom
		assert(GroundFloor.floor(-16, -28, c) == -16, "12 thick: none of it can go")
		assert(GroundFloor.floor(-12, -28, c) == -16, "16 thick: 4 can go")
		-- a hill keeps its core: a share of its thickness
		assert(GroundFloor.floor(72, -28, c) == -28 + 75)
		assert(GroundFloor.floor(0, -28, c) > -28 + c.minKeep)
	end,
	["a hold never adds ground, only keeps what was under the floor"] = function()
		local before = { 1, 1, 0.5, 0 }
		local after = { 0, 0, 0, 0 }
		local out = GroundFloor.hold(before, after, 0, 4, 6)
		assert(out[1] == 1 and out[2] == 0.5 and out[3] == 0 and out[4] == 0)
		local deeper = GroundFloor.hold(before, after, 0, 4, 100)
		assert(deeper[3] == 0.5 and deeper[4] == 0, "a floor over the ground adds nothing")
		local cut = GroundFloor.hold(before, { 1, 1, 0.25, 0 }, 0, 4, 0)
		assert(cut[3] == 0.25, "a cut over the floor stands")
	end,
	["blast after blast stops at the floor: no hole through low ground, no hill levelled"] = function()
		for _, top in { -4, 0, 30, 72 } do
			local y0, n = -28, 40
			local occs = column(y0, n, top)
			local s, b = GroundFloor.span(occs, y0, 4)
			local floor = GroundFloor.floor(s :: number, b :: number, F)
			for _ = 1, 200 do
				occs = GroundFloor.hold(occs, Blast.lowerColumn(occs, y0, 4, 5), y0, 4, floor)
			end
			local now = topOf(occs, y0)
			assert(math.abs(now - floor) < 1e-6, `ground {top}: stops at its floor`)
			assert(now - y0 >= F.minKeep - 1e-6, "keeps a bottom")
			assert(now - y0 >= (top - y0) * F.coreShare - 1e-6, "keeps its core")
		end
	end,
}
