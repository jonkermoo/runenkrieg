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
			if not d.offMap and not d.map then
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
	["access: creator always, anyone in Studio or the DEV place, nobody else live"] = function()
		assert(T.allowed(Cfg, 180563380, false))
		assert(T.allowed(Cfg, 1, true))
		assert(not T.allowed(Cfg, 1, false))
		assert(T.allowed(Cfg, 1, false, Cfg.DevPlaceId), "every playtester in the DEV place")
		assert(not T.allowed(Cfg, 1, false, 71611711100478), "nobody else in the live place")
		assert(not T.allowed(Cfg, 1, true, Cfg.DevPlaceId, false), "a closed mode: no playtester")
		assert(T.allowed(Cfg, 180563380, false, Cfg.DevPlaceId, false), "the creator always")
		assert(T.allowed(Cfg, -1, true, nil, false), "a Studio Clients and Servers test player, even in a closed mode")
		assert(not T.allowed(Cfg, -1, false, 71611711100478, false), "never outside Studio")
		assert(T.allowed(Cfg, 1, true, nil, true))
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
		assert(A.valid(Cfg, "Shells", Cfg.Blasts.Guns[1]) and not A.valid(Cfg, "Shells", "nope") and A.Aimed.Shells)
		assert(Cfg.Blasts.Shells.count >= 1 and Cfg.Blasts.Shells.every > 0)
		assert(A.valid(Cfg, "BeamStage", 1) and not A.valid(Cfg, "BeamStage", 4) and A.Aimed.BeamStage)
		assert(A.valid(Cfg, "PlacePiece", Cfg.Blasts.Pieces[1]) and A.Aimed.PlacePiece)
		assert(not A.valid(Cfg, "PlacePiece", "Trench") and not A.valid(Cfg, "PlacePiece", nil))
		assert(A.valid(Cfg, "GunHp", 49) and A.Aimed.GunHp and not A.valid(Cfg, "GunHp", 10))
		assert(A.valid(Cfg, "DugoutHp", 50) and A.Aimed.DugoutHp and not A.valid(Cfg, "DugoutHp", 60))
		assert(A.valid(Cfg, "Kill", nil) and not A.valid(Cfg, "Kill", true))
		assert(A.valid(Cfg, "Grenade", Cfg.Admin.Grenades[1]) and not A.valid(Cfg, "Grenade", "rifle_g98"))
		assert(not A.valid(Cfg, "Grenade", nil))
		assert(A.valid(Cfg, "Team", Cfg.Dummies.Kits[1].kit) and A.valid(Cfg, "Team", Cfg.Admin.Random))
		assert(not A.valid(Cfg, "Team", "uniform9") and not A.valid(Cfg, "Team", nil))
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
		for _, W in Cfg.World.Terrain do
			for i = 1, 3 do
				assert(W.min[i] < W.max[i], "the terrain box needs min < max")
			end
		end
	end,
	["admin dig steps: a normal one, shares up to the whole, each a valid DigStep and nothing else"] = function()
		local seen0 = false
		for _, st in Cfg.Admin.Dig.steps do
			assert(st.share >= 0 and st.share <= 1, st.name)
			seen0 = seen0 or st.share == 0
			assert(A.valid(Cfg, "DigStep", st.share), st.name)
		end
		assert(seen0, "a normal step")
		assert(not A.valid(Cfg, "DigStep", 0.33) and not A.valid(Cfg, "DigStep", "Full"))
	end,
	["the admin server, match, loadout and cheat actions take only their Config values"] = function()
		local ModeCfg = require("../src/shared/Config/Modes")
		local ClassCfg = require("../src/shared/Config/Classes")
		local defs = { modes = ModeCfg.Defs, classes = ClassCfg.Defs }
		assert(A.valid(Cfg, "Mode", "FFA", defs) and A.valid(Cfg, "Mode", "Admin", defs))
		assert(not A.valid(Cfg, "Mode", "Nope", defs) and not A.valid(Cfg, "Mode", "FFA"), "no defs: refused")
		assert(A.valid(Cfg, "Class", "Engineer", defs), "a locked class can be pinned")
		assert(A.valid(Cfg, "Class", Cfg.Admin.Normal, defs) and not A.valid(Cfg, "Class", "Nope", defs))
		assert(A.valid(Cfg, "Points", Cfg.Admin.Points[1]) and not A.valid(Cfg, "Points", 1e9))
		assert(A.valid(Cfg, "ZoneScore", Cfg.Admin.ZoneScore[1]) and not A.valid(Cfg, "ZoneScore", -5))
		assert(A.valid(Cfg, "MatchTime", Cfg.Admin.MatchSeconds[1]) and not A.valid(Cfg, "MatchTime", 7))
		assert(
			A.valid(Cfg, "Bots", Cfg.Admin.BotCounts[1])
				and not A.valid(Cfg, "Bots", 7)
				and not A.valid(Cfg, "Bots", "5")
		)
		assert(A.valid(Cfg, "BotsAuto", nil) and not A.valid(Cfg, "BotsAuto", 3))
		assert(A.valid(Cfg, "BotDifficulty", "Hard") and not A.valid(Cfg, "BotDifficulty", "Nightmare"))
		for _, plain in { "MatchEnd", "MatchRestart", "ZoneSkip", "RespawnAll", "HitchReport" } do
			assert(A.valid(Cfg, plain, nil) and not A.valid(Cfg, plain, true), plain)
		end
		for _, sw in { "BuildAll", "Ammo", "KeptTeams", "HitchLog" } do
			assert(A.valid(Cfg, sw, true) and A.valid(Cfg, sw, false) and not A.valid(Cfg, sw, nil), sw)
		end
		assert(ClassCfg.Defs[Cfg.Admin.Normal] == nil, "the Normal value isn't a class")
	end,
	["the bot test actions take only their Config values, the aimed ones an aim point"] = function()
		for _, sw in { "BotState", "FreeEngineer", "FreeGrenadier" } do
			assert(A.valid(Cfg, sw, true) and A.valid(Cfg, sw, false) and not A.valid(Cfg, sw, nil), sw)
		end
		for _, aimed in { "BotPush", "BotStrike", "BotGun", "BotWork", "BotDown", "BotShellHere" } do
			assert(A.valid(Cfg, aimed, nil) and not A.valid(Cfg, aimed, 1) and A.Aimed[aimed], aimed)
		end
		assert(A.valid(Cfg, "BotDig", Cfg.Admin.BotDig.steps[2]) and not A.valid(Cfg, "BotDig", 1e6))
		assert(Cfg.Admin.BotDig.steps[1] == 1, "the first dig step is the normal one")
		assert(A.valid(Cfg, "BotPlan", { side = "West", plan = "trench" }), "a plan forced")
		assert(A.valid(Cfg, "BotPlan", { side = "East", plan = "auto" }), "let go")
		assert(not A.valid(Cfg, "BotPlan", { side = "East", plan = "retreat" }) and not A.valid(Cfg, "BotPlan", "West"))
		for _, a in { "BotShell", "FrontPush" } do
			assert(A.valid(Cfg, a, "West") and A.valid(Cfg, a, "East") and not A.valid(Cfg, a, "North"), a)
		end
		assert(A.valid(Cfg, "FrontCapture", { side = "East", index = 2 }))
		assert(not A.valid(Cfg, "FrontCapture", { side = "East", index = 1.5 }))
		assert(not A.valid(Cfg, "FrontCapture", { side = "East", index = 0 }))
		assert(not A.valid(Cfg, "FrontCapture", { side = "East", index = Cfg.Admin.MaxSectors + 1 }))
		assert(
			not A.valid(Cfg, "FrontCapture", { side = "Neutral", index = 2 }) and not A.valid(Cfg, "FrontCapture", 2)
		)
		assert(not A.Aimed.BotShell and not A.Aimed.FrontPush)
		assert(A.valid(Cfg, "FrontLatch", { side = "West", on = true }))
		assert(not A.valid(Cfg, "FrontLatch", { side = "West", on = 1 }) and not A.valid(Cfg, "FrontLatch", true))
		assert(not A.valid(Cfg, "FrontLatch", { side = "Neutral", on = false }))
		assert(Map1.sectors and #Map1.sectors <= Cfg.Admin.MaxSectors, "every Map1 sector can be captured")
	end,
	["a bot's state label leaves out what it hasn't got"] = function()
		local full = A.botLabel({
			order = "Attack",
			sector = 3,
			phase = "Bound",
			role = "Assault",
			post = "step",
			act = "Throw",
			gun = "artillery_qf18",
			danger = true,
		})
		assert(full == "Attack S3 · Bound/Assault\nstep · Throw · gun artillery_qf18 · DANGER", full)
		assert(A.botLabel({}) == "-")
		assert(A.botLabel({ order = "Defend" }) == "Defend")
		assert(A.botLabel({ role = "Hold", post = "dugout" }) == "?/Hold\ndugout")
		assert(A.botLabel({ order = "Attack", sight = "calm" }) == "Attack\ncalm")
	end,
	["Lantern Meadows: its sectors and landmarks as teleports, on its own map, inside its bounds"] = function()
		local LM = require("../src/shared/Config/Maps/LanternMeadows")
		local list = T.list(Map1, Cfg, { { key = "LanternMeadows", map = LM } })
		local ids = {}
		for _, d in list do
			ids[d.id] = d
		end
		for _, s in LM.sectors do
			local d = ids[`LanternMeadows_{s.id}`]
			assert(d and d.map == "LanternMeadows", `no teleport to Lantern Meadows' {s.id}`)
		end
		for _, id in { "LM_Watchtower", "LM_Cascina", "LM_FordFestival", "LM_FordUpstream", "LM_FordStones" } do
			local d = ids[id]
			assert(d and d.map == "LanternMeadows", `no {id}`)
			local b = LM.bounds
			assert(d.x > b.minX and d.x < b.maxX and d.z > b.minZ and d.z < b.maxZ, `{id} outside Lantern Meadows`)
		end
		assert(T.find(Map1, Cfg, "LanternMeadows_S3", { { key = "LanternMeadows", map = LM } }) ~= nil)
		assert(T.find(Map1, Cfg, "S3") ~= nil and T.find(Map1, Cfg, "S3").map == nil, "Map 1's own sectors unchanged")
	end,
	["admin: switch to a frontline map by key, rebuild the maps"] = function()
		local A = require("../src/shared/Rules/DevActions")
		local defs = { modes = {}, classes = {}, maps = { "LanternMeadows", "Map1" } }
		assert(A.valid(Cfg, "Map", "LanternMeadows", defs))
		assert(not A.valid(Cfg, "Map", "Nowhere", defs) and not A.valid(Cfg, "Map", 3, defs))
		assert(A.valid(Cfg, "RebuildMaps", nil, defs) and not A.valid(Cfg, "RebuildMaps", true, defs))
		for _, r in Cfg.Admin.EndResults do
			assert(A.valid(Cfg, "EndInto", { result = r, map = "Map1" }, defs), `ends with {r} into a map`)
			assert(Cfg.Admin.EndLabels[r], `{r} has a label`)
		end
		assert(not A.valid(Cfg, "EndInto", { result = "Win", map = "Nowhere" }, defs), "a built frontline map only")
		assert(not A.valid(Cfg, "EndInto", { result = "Draw", map = "Map1" }, defs), "a listed result only")
		assert(
			not A.valid(Cfg, "EndInto", "Map1", defs) and not A.valid(Cfg, "EndInto", { result = "Win", map = "Map1" })
		)
	end,
	["the shell shock rows take a listed source at a listed distance, the helmet shot nothing"] = function()
		local S = Cfg.Admin.Shock
		local src, d = S.Sources[1].key, S.Distances[1]
		assert(A.valid(Cfg, "ShockAt", { source = src, distance = d }), "listed")
		assert(not A.valid(Cfg, "ShockAt", { source = "nuke", distance = d }), "unknown source")
		assert(not A.valid(Cfg, "ShockAt", { source = src, distance = 7.5 }), "unlisted distance")
		assert(not A.valid(Cfg, "ShockAt", src), "not a table")
		assert(A.valid(Cfg, "HelmetShot", nil) and not A.valid(Cfg, "HelmetShot", 1), "plain")
		assert(DamageCfg.Weapons[S.HelmetWeapon] ~= nil, "a real weapon")
		for _, g in S.Sources do
			assert(g.label ~= nil, `{g.key} labelled`)
		end
	end,
}
