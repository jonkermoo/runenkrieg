--!strict
local R = require("../src/shared/Config/Range")
local M = require("../src/shared/Config/Metrics")
local D = require("../src/shared/Config/DevTools")
local Map1 = require("../src/shared/Config/Maps/Map1")
local T = require("../src/shared/Rules/DevTeleports")

return {
	["targets reach the rifle's effective range and stay inside the fog"] = function()
		local farthest = 0
		for _, t in R.Firing.Targets do
			assert(math.abs(t.x) < R.Firing.Width / 2, `target at {t.distance} is off the floor`)
			farthest = math.max(farthest, t.distance)
		end
		assert(farthest == M.Combat.RifleEffectiveRange, "the farthest target must sit at the effective range")
		assert(farthest + R.Firing.Beyond < M.Combat.FogEnd, "targets must stay inside the fog")
	end,
	["the range is off the map and the teleport lands behind its firing line"] = function()
		local b = Map1.bounds
		local ox, oz = R.Origin[1], R.Origin[3]
		assert(not (ox > b.minX and ox < b.maxX and oz > b.minZ and oz < b.maxZ), "range overlaps the map")
		local d = T.find(Map1, D, "Range")
		assert(d and d.offMap and d.y, "Range teleport missing")
		assert(d.x == ox and d.z > oz and d.z <= oz + R.Firing.Behind, "teleport not behind the firing line")
	end,
}
