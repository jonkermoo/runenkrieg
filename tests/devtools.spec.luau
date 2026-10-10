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
}
