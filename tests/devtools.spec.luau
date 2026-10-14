--!strict
local Cfg = require("../src/shared/Config/DevTools")
local Map1 = require("../src/shared/Config/Maps/Map1")
local T = require("../src/shared/Rules/DevTeleports")

return {
	["every sector is a destination, ids are unique"] = function()
		local list = T.list(Map1, Cfg)
		local seen = {}
		for _, d in list do
			assert(not seen[d.id], `duplicate destination {d.id}`)
			seen[d.id] = true
		end
		for _, s in Map1.sectors do
			assert(seen[s.id], `sector {s.id} missing`)
		end
	end,
	["on-map destinations are inside the playable bounds"] = function()
		local b = Map1.bounds
		for _, d in T.list(Map1, Cfg) do
			if not d.offMap then
				assert(d.x > b.minX and d.x < b.maxX and d.z > b.minZ and d.z < b.maxZ, `{d.id} outside bounds`)
			end
		end
	end,
	["off-map destinations give an explicit height"] = function()
		for _, d in T.list(Map1, Cfg) do
			if d.offMap then
				assert(d.y ~= nil, `{d.id} needs y`)
			end
		end
	end,
	["access: creator always, anyone in Studio, nobody else live"] = function()
		assert(T.allowed(Cfg, 180563380, false))
		assert(T.allowed(Cfg, 1, true))
		assert(not T.allowed(Cfg, 1, false))
		assert(T.find(Map1, Cfg, "Gallery") ~= nil and T.find(Map1, Cfg, "nope") == nil)
	end,
	["admin speeds: positive steps including x1, a flying speed and fly keys"] = function()
		local A = Cfg.Admin
		assert(table.find(A.SpeedSteps, 1), "x1 (normal speed) must be a step")
		for i, m in A.SpeedSteps do
			assert(m > 0, `speed step {m} must be positive`)
			assert(i == 1 or m > A.SpeedSteps[i - 1], "speed steps must increase")
		end
		assert(A.FlySpeed > 0 and #A.FlyUpKeys > 0 and #A.FlyDownKeys > 0, "flying needs a speed and keys")
		assert(A.Attribute ~= Cfg.Attribute and A.FlyAttribute ~= Cfg.Attribute, "attribute names must differ")
	end,
}
