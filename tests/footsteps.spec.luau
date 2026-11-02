--!strict
local F = require("../src/shared/Config/Footsteps")
local A = require("../src/shared/Config/Audio")
local R = require("../src/shared/Rules/Footsteps")

return {
	["every surface a rule can pick has recordings in the sheet"] = function()
		local picks = { F.TerrainDefault, F.PartDefault }
		for _, s in F.Terrain do
			table.insert(picks, s)
		end
		for _, s in F.Class do
			table.insert(picks, s)
		end
		for _, rule in F.Names do
			table.insert(picks, rule[2])
		end
		for _, s in picks do
			assert(R.count(F, s) > 0, `surface {s} has no recordings`)
			assert(F.Surface[s], `surface {s} has no level`)
		end
	end,
	["the slots fit the sheet, one after another"] = function()
		local total = 0
		for _, s in F.Order do
			total += F.Count[s]
		end
		local start, len = R.slot(F, "grass", 1)
		assert(start == 0 and len == F.Length and len <= F.Slot, "the first step starts the sheet")
		local last = R.slot(F, F.Order[#F.Order], F.Count[F.Order[#F.Order]])
		assert(math.abs(last - (total - 1) * F.Slot) < 1e-9, "the last step sits in the last slot")
		assert(R.slot(F, "stone", 1) == R.slot(F, "grass", 1), "every surface plays the leather steps")
		assert(R.slot(F, "wood", R.count(F, "wood") + 1) == R.slot(F, "wood", 1), "recordings wrap")
	end,
	["the ground picks its surface"] = function()
		assert(R.surface(F, "Grass", nil, nil) == "grass")
		assert(R.surface(F, "Mud", nil, nil) == "mud")
		assert(R.surface(F, "Ground", nil, nil) == "mud", "the village's dirt streets")
		assert(R.surface(F, "CrackedLava", nil, nil) == F.TerrainDefault, "unlisted terrain")
		assert(R.surface(F, nil, "Wood", "Floor") == "wood", "a building's floor is boards")
		assert(R.surface(F, nil, nil, "Floor2Chunks") == "mud", "a trench's floor is dirt")
		assert(R.surface(F, nil, nil, "Wall6Planks") == "wood", "a trench's plank steps")
		assert(R.surface(F, nil, "Brick", "Foundation") == "stone")
		assert(R.surface(F, nil, nil, "Something") == F.PartDefault)
	end,
	["sprinting is loudest and carries furthest, crouching is hushed"] = function()
		local walk, sprint, crouch =
			R.volume(F, "walk", "grass", false),
			R.volume(F, "sprint", "grass", false),
			R.volume(F, "crouch", "grass", false)
		assert(sprint > walk and walk > crouch, "sprint > walk > crouch")
		assert(R.heard(F, "sprint", F.Range.walk + 10) and not R.heard(F, "walk", F.Range.walk + 10))
		assert(not R.heard(F, "crouch", F.Range.crouch + 1))
		assert(R.volume(F, "walk", "grass", true) < walk, "your own steps sit under others'")
	end,
	["footsteps stay background noise"] = function()
		for g in F.Gait do
			for s in F.Surface do
				assert(R.volume(F, g, s, false) <= 0.6, `{g} on {s} is too loud`)
			end
		end
	end,
	["the falloff reaches as far as the furthest step is played"] = function()
		for _, r in F.Range do
			assert(r <= A.Profiles.Footstep.max, "a step played past the falloff's end would be silent")
		end
	end,
}
