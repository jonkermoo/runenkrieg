--!strict
local Cfg = require("../src/shared/Config/Collision")
local U = require("../src/shared/Config/Uniforms")
local R = require("../src/shared/Rules/Collision")

return {
	["groupOf: a team's group, the shared one in FFA or with no kit"] = function()
		assert(R.groupOf("uniform1", false, U.Kits, Cfg) == Cfg.TeamPrefix .. "uniform1")
		assert(R.groupOf("uniform1", true, U.Kits, Cfg) == Cfg.Soldiers, "FFA: everyone collides")
		assert(R.groupOf(nil, false, U.Kits, Cfg) == Cfg.Soldiers, "no kit yet")
		assert(R.groupOf("nonsense", false, U.Kits, Cfg) == Cfg.Soldiers, "unknown kit")
	end,
	["groups: the shared one and one per kit, all soldiers"] = function()
		local gs = R.groups(U.Kits, Cfg)
		local n = 0
		for _ in U.Kits do
			n += 1
		end
		assert(#gs == n + 1 and gs[1] == Cfg.Soldiers)
		for _, g in gs do
			assert(R.isSoldier(g, Cfg), g)
		end
		assert(not R.isSoldier("Default", Cfg) and not R.isSoldier("Debris", Cfg))
		assert(not R.isSoldier(Cfg.Camera, Cfg))
	end,
	["collides: teammates pass through, enemies and FFA soldiers don't"] = function()
		local a, b = Cfg.TeamPrefix .. "uniform1", Cfg.TeamPrefix .. "uniform2"
		assert(not R.collides(a, a, Cfg), "teammates")
		assert(R.collides(a, b, Cfg) and R.collides(b, a, Cfg), "enemies")
		assert(R.collides(Cfg.Soldiers, Cfg.Soldiers, Cfg), "free-for-all")
		assert(R.collides(a, Cfg.Soldiers, Cfg))
	end,
	["cameraHits: never soldiers or debris, otherwise as Default"] = function()
		assert(not R.cameraHits(Cfg.Soldiers, true, Cfg))
		assert(not R.cameraHits(Cfg.TeamPrefix .. "uniform3", true, Cfg))
		assert(not R.cameraHits("Debris", true, Cfg))
		assert(R.cameraHits("Default", true, Cfg))
		assert(not R.cameraHits("Boundary", false, Cfg), "the walls stop characters only")
	end,
}
