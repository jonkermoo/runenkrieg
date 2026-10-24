--!strict
local B = require("../src/shared/Config/Buildings")
local D = require("../src/shared/Config/Destruction")
local M = require("../src/shared/Config/Metrics")
local P = require("../src/shared/Config/Palette")
local R = require("../src/shared/Rules/Destruction")

return {
	["a ragged hole in three bands: pulverised middle, crumpled ring, the rest kept"] = function()
		local bands = R.jagBands(6, 6, 1.5, function(u, v)
			local r = math.sqrt((u - 3) ^ 2 + (v - 3) ^ 2)
			return if r <= 1.2 then 2 elseif r <= 2.5 then 1 else 0
		end)
		local function area(runs: { any }?): number
			local a = 0
			for _, r in runs or {} do
				a += (r.u1 - r.u0) * (r.v1 - r.v0)
			end
			return a
		end
		assert(area(bands[2]) > 0 and area(bands[1]) > 0 and area(bands[0]) > 0, "all three bands")
		assert(math.abs(area(bands[0]) + area(bands[1]) + area(bands[2]) - 36) < 1e-6, "the face, all of it")
		assert(area(bands[1]) > area(bands[2]), "the ring is bigger than the middle")
	end,
	["debris freezes only once at rest, or after maxFly"] = function()
		local r = D.Debris.Rest
		local still, freeze = R.rested(20, 0, 0, 0.1, 0.1, r)
		assert(still == 0 and not freeze, "flying: not frozen")
		still, freeze = R.rested(0.2, 0.1, r.time - 0.1, 1, 0.1, r)
		assert(freeze, "still for long enough: frozen")
		still, freeze = R.rested(0.2, 0.1, 0, 1, 0.1, r)
		assert(not freeze, "only just stopped: not yet")
		still, freeze = R.rested(r.still + 1, 0, r.time, 1, 0.1, r)
		assert(still == 0 and not freeze, "moving again resets it")
		assert(R.rested(0, 0, 0, r.after / 2, 0.1, r) == 0, "not yet loose long enough to count")
		local _, frozen, letGo = R.rested(10, 10, 0, r.maxFly, 0.1, r)
		assert(not frozen and letGo, "still moving after maxFly: let go, never frozen in the air")
		assert(not select(3, R.rested(0, 0, 0, 1, 0.1, r)), "kept while it may still come to rest")
		assert(r.still < 1, "frozen only when all but stopped (a chunk frozen at 1.25 studs/s hung in the air)")
	end,
	["a chunk at rest high on a pile of chunks is knocked over, a few times at most"] = function()
		local P = D.Debris.Pillar
		assert(R.topples(P.height + 1, 0, P.height, P.tries), "a column: knocked over")
		assert(not R.topples(P.height - 1, 0, P.height, P.tries), "a low heap stays")
		assert(not R.topples(nil, 0, P.height, P.tries), "nothing under it within reach: leave it")
		assert(not R.topples(P.height + 1, P.tries, P.height, P.tries), "after `tries` it stays where it is")
	end,
	["a frozen chunk wakes when what is under or beside it goes, not what is above"] = function()
		assert(R.leanedOn(0, 2, 0, 1, 1.5), "on top of it")
		assert(R.leanedOn(2, 0, 0, 1, 1.5), "beside it")
		assert(not R.leanedOn(0, -3, 0, 1, 1.5), "below it")
		assert(not R.leanedOn(6, 0, 0, 1, 1.5), "far from it")
	end,
	["unsupported: pieces with no chain to the ground"] = function()
		-- 1 ground, 2 on 1, 3 on 2, 4 alone, 5 on 4
		local links = { { 2 }, { 1, 3 }, { 2 }, { 5 }, { 4 } }
		local out = R.unsupported(5, links, { [1] = true })
		table.sort(out)
		assert(#out == 2 and out[1] == 4 and out[2] == 5, "the hanging pair drops")
		assert(#R.unsupported(3, { { 2 }, { 3 }, {} }, { [1] = true }) == 0, "a chain of three holds")
		assert(#R.unsupported(2, {}, {}) == 2, "nothing on the ground: all drop")
	end,
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
		assert(R.collapseFrom({ [0] = { initial = 20, standing = 4 }, [1] = { initial = 20, standing = 2 } }, f) == 0)
		assert(R.collapseFrom({ [0] = { initial = 20, standing = 15 }, [1] = { initial = 20, standing = 4 } }, f) == 1)
		-- only once nearly all its supports are gone (user 2026-10-17): half the walls down still stands
		assert(R.collapseFrom({ [0] = { initial = 10, standing = 5 } }, f) == nil, "half the walls: stands")
		assert(R.collapseFrom({ [0] = { initial = 10, standing = 2 } }, f) == 0, "8 of 10 gone: falls")
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
	["a blast's hole is ragged: cells in it break, the rest stays, in few runs"] = function()
		local J = D.Jag
		-- a 6 x 12 panel, a hole of radius 4 round its lower-left corner
		local kept, broken = R.jag(6, 12, J.cell, function(u, v)
			return u * u + v * v <= 16
		end)
		local area = 0
		for _, list in { kept, broken } do
			for _, r in list do
				assert(r.u1 > r.u0 and r.v1 > r.v0)
				area += (r.u1 - r.u0) * (r.v1 - r.v0)
			end
		end
		assert(math.abs(area - 72) < 1e-6, `covers the panel exactly: {area}`)
		assert(#broken > 0 and #kept > 0, "part breaks, part stays")
		assert(#kept + #broken <= 2 * 8, "at most two runs a row")
		-- nothing in the hole: all of it breaks; the noise is in [0, 1) and repeats
		local k2, b2 = R.jag(6, 12, J.cell, function()
			return true
		end)
		assert(#k2 == 0 and #b2 == math.ceil(12 / J.cell), "all broken, a run a row")
		for i = 1, 50 do
			local n = R.noise(i, -i, 7)
			assert(n >= 0 and n < 1 and n == R.noise(i, -i, 7))
		end
		assert(J.jitter > 0 and J.jitter < 1 and J.remainsHP > 0 and J.remainsHP <= 1)
		assert(not J.kinds.Remains, "remains break whole")
	end,
}
