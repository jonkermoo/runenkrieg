--!strict
local Cfg = require("../src/shared/Config/DevTools")
local Map1 = require("../src/shared/Config/Maps/Map1")
local T = require("../src/shared/Rules/DevTeleports")
local A = require("../src/shared/Rules/DevActions")
local Uniforms = require("../src/shared/Config/Uniforms")
local RagdollCfg = require("../src/shared/Config/Ragdoll")
local DamageCfg = require("../src/shared/Config/Damage")

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
	["dev actions: values come only from the Config lists"] = function()
		assert(A.valid(Cfg, "Health", Cfg.Admin.Health[1]) and not A.valid(Cfg, "Health", 1000))
		assert(not A.valid(Cfg, "Health", "100") and not A.valid(Cfg, "Health", nil))
		assert(A.valid(Cfg, "BlastKg", Cfg.Blasts.Kg[1]) and not A.valid(Cfg, "BlastKg", 1e9))
		assert(A.valid(Cfg, "BlastStage", 3) and not A.valid(Cfg, "BlastStage", 0))
		assert(A.valid(Cfg, "Kill", nil) and not A.valid(Cfg, "Kill", true))
		assert(A.valid(Cfg, "Grenade", Cfg.Admin.Grenades[1]) and not A.valid(Cfg, "Grenade", "rifle_g98"))
		assert(not A.valid(Cfg, "Grenade", nil))
		assert(A.valid(Cfg, "God", false) and not A.valid(Cfg, "God", nil) and not A.valid(Cfg, "God", 1))
		assert(not A.valid(Cfg, "Nope", nil) and not A.valid(Cfg, 5, nil) and not A.valid(Cfg, nil, nil))
		local d = { kit = Cfg.Dummies.Kits[1].kit, helmet = true, move = "Walk" }
		assert(A.valid(Cfg, "Dummy", d))
		assert(not A.valid(Cfg, "Dummy", { kit = "nope", helmet = true, move = "Walk" }))
		assert(not A.valid(Cfg, "Dummy", { kit = d.kit, helmet = "yes", move = "Walk" }))
		assert(not A.valid(Cfg, "Dummy", { kit = d.kit, helmet = true, move = "Fly" }))
		assert(not A.valid(Cfg, "Dummy", "uniform1"))
		assert(A.valid(Cfg, "Clock", Cfg.Admin.Times[1].hours) and not A.valid(Cfg, "Clock", 13.5))
		assert(not A.valid(Cfg, "Clock", nil) and not A.valid(Cfg, "Clock", "12"))
		assert(A.valid(Cfg, "ClockPaused", true) and not A.valid(Cfg, "ClockPaused", nil))
		assert(
			A.valid(Cfg, "Weather", "Fog") and A.valid(Cfg, "Weather", "Clear") and not A.valid(Cfg, "Weather", "Snow")
		)
		assert(not A.valid(Cfg, "Weather", nil) and A.valid(Cfg, "WeatherCalm", false))
	end,
	["admin weather: the kinds Config/Environment knows, for a positive time"] = function()
		local Env = require("../src/shared/Config/Environment")
		for _, kind in Cfg.Admin.Weather do
			assert(kind == "Clear" or Env.Weather[kind], `unknown weather {kind}`)
		end
		assert(Cfg.Admin.WeatherSeconds > 0)
	end,
	["admin times: named hours on the clock"] = function()
		for _, t in Cfg.Admin.Times do
			assert(type(t.name) == "string" and t.hours >= 0 and t.hours < 24, `bad time {t.name}`)
		end
	end,
	["dev actions: the aim point must be a real point within reach"] = function()
		assert(A.inReach(Cfg, 0, 0, 0) and A.inReach(Cfg, Cfg.AimReach, 0, 0))
		assert(not A.inReach(Cfg, Cfg.AimReach + 1, 0, 0))
		assert(
			not A.inReach(Cfg, 0 / 0, 0, 0) and not A.inReach(Cfg, math.huge, 0, 0) and not A.inReach(Cfg, "1", 0, 0)
		)
	end,
	["dummies: kits, moves and knocks exist; patrol legs go the right way"] = function()
		local D = Cfg.Dummies
		assert(#D.Kits > 0 and D.Max > 0 and D.Patrol > 0 and D.WalkSpeed > 0)
		for _, k in D.Kits do
			assert(Uniforms.Kits[k.kit], `dummy kit {k.kit} is not in Config/Uniforms.Kits`)
			assert(A.kitName(Cfg, k.kit) == k.name)
		end
		assert(table.find(D.Moves, "Stand") and table.find(D.Moves, "Walk") and table.find(D.Moves, "Strafe"))
		assert(RagdollCfg.Knocks[Cfg.Admin.SelfKnock], "the self knock must be a Config/Ragdoll.Knocks entry")
		assert(RagdollCfg.Knocks[DamageCfg.Knocks.Other], "a dummy's other death uses Config/Damage.Knocks.Other")
		local r, f = A.leg("Walk", 1, 10)
		assert(r == 0 and f == 10)
		r, f = A.leg("Strafe", -1, 10)
		assert(r == -10 and f == 0)
		r, f = A.leg("Stand", 1, 10)
		assert(r == 0 and f == 0)
	end,
	["dummies: the readout shows damage, knock and what is left"] = function()
		assert(A.readout(70, "Torso", 30) == "-70 Torso -> 30")
		assert(A.readout(200.4, "HeadDrop", 0) == "-200 HeadDrop -> dead")
		assert(A.readout(0, "Limb", 100) == "0 Limb -> 100")
		assert(A.readout(35.6, nil, 64.4) == "-36 -> 64")
	end,
	["blasts and health steps are sensible"] = function()
		for _, kg in Cfg.Blasts.Kg do
			assert(kg > 0, "a charge must weigh something")
		end
		for _, s in Cfg.Blasts.Stages do
			assert(DamageCfg.Staff.Charge[s] ~= nil, `staff stage {s} has no Config/Damage.Staff.Charge`)
		end
		for _, h in Cfg.Admin.Health do
			assert(h > 0 and h <= DamageCfg.Health, `health step {h} out of range`)
		end
		local W = Cfg.World.Terrain
		for i = 1, 3 do
			assert(W.min[i] < W.max[i], "the terrain box needs min < max")
		end
	end,
}
