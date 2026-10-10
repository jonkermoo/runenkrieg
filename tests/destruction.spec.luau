--!strict
local B = require("../src/shared/Config/Buildings")
local D = require("../src/shared/Config/Destruction")
local M = require("../src/shared/Config/Metrics")
local P = require("../src/shared/Config/Palette")
local R = require("../src/shared/Rules/Destruction")

return {
	["blast damage: full at center, zero at the edge, monotonic"] = function()
		assert(R.blastDamage(0, 20, 500) == 500)
		assert(R.blastDamage(20, 20, 500) == 0 and R.blastDamage(30, 20, 500) == 0)
		assert(R.blastDamage(5, 20, 500) > R.blastDamage(10, 20, 500))
	end,
	["collapse picks the lowest failing story"] = function()
		local f = D.CollapseSupportFraction
		assert(
			R.collapseFrom({ [0] = { initial = 20, standing = 20 }, [1] = { initial = 20, standing = 19 } }, f) == nil
		)
		assert(R.collapseFrom({ [0] = { initial = 20, standing = 6 }, [1] = { initial = 20, standing = 2 } }, f) == 0)
		assert(R.collapseFrom({ [0] = { initial = 20, standing = 15 }, [1] = { initial = 20, standing = 5 } }, f) == 1)
	end,
	["every template's colors exist in the palette, and copies vary"] = function()
		for name, t in B.Templates do
			for _, w in t.walls do
				assert(P.Buildings.Walls[w], `{name}: unknown wall color {w}`)
			end
			for _, r in t.roofs do
				assert(P.Buildings.Roofs[r], `{name}: unknown roof color {r}`)
			end
			assert(D.Materials[t.class], `{name}: unknown class {t.class}`)
		end
		local seen = {}
		for seed = 1, 40 do
			local s = R.scheme(B.Templates.ThatchCottage, P, seed)
			seen[s.wall .. s.roof .. s.door] = true
		end
		local n = 0
		for _ in seen do
			n += 1
		end
		assert(n >= 8, `only {n} distinct ThatchCottage color schemes`)
	end,
	["templates fit their features at the new scale"] = function()
		local Bm = M.Building
		local steps = math.ceil(Bm.StoryHeight / Bm.StairRise)
		local run = steps * Bm.StairRun
		for name, t in B.Templates do
			if t.stories >= 2 then
				-- stairs run along the back wall from the left; a back door must fit past their end
				local need = run + (if t.backDoor then D.SectionWidth else 0)
				assert(t.width - 2 * B.WallThickness >= need, `{name}: no room for a {run}-stud stair (+ back door)`)
				assert(t.depth - 2 * B.WallThickness >= Bm.StairWidthMin + 6, `{name}: too shallow for stairs + room`)
			end
			do
				local h = t.storyHeight or Bm.StoryHeight
				assert(h >= Bm.DoorHeight + 1.5, `{name}: story too low for the door`)
				assert(h >= Bm.WindowTop + 1, `{name}: story too low for windows`)
			end
		end
	end,
	["section width leaves room for a door or window in each section"] = function()
		assert(D.SectionWidth >= M.Building.DoorWidth + 0.5, "door does not fit in a section")
	end,
}
