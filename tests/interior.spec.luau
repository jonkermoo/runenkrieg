--!strict
-- Building interiors (Rules/Interior, Config/Buildings.Furniture): every furnished building and block keeps its doors
-- and stairs clear, its furniture inside its walls and apart, and its floors walkable from door to stairs.
local B = require("../src/shared/Config/Buildings")
local M = require("../src/shared/Config/Metrics")
local I = require("../src/shared/Rules/Interior")

local F, cfg = B.Furniture, B.InteriorCheck

-- every furnished block: { name, block, wall thickness }
local function furnished(): { any }
	local out = {}
	for name, t in B.Templates do
		if t.interior then
			table.insert(out, { name = name, b = t, T = t.wallThickness or B.WallThickness })
		end
		for _, b in t.blocks or {} do
			if b.interior then
				table.insert(out, {
					name = `{name}.{b.name}`,
					b = b,
					T = b.wallThickness or t.wallThickness or B.WallThickness,
				})
			end
		end
	end
	table.sort(out, function(p, q)
		return p.name < q.name
	end)
	return out
end

local function box(w: number, d: number, stories: number, interior: { any }): any
	return { width = w, depth = d, stories = stories, doors = { { center = 0 } }, interior = interior }
end

local tests = {
	["a piece's footprint turns with its yaw; a linear piece runs a to b"] = function()
		local r = I.footprint({ kind = "Table", x = 0, z = 0, yaw = 90 }, F)
		assert(math.abs((r[2] - r[1]) - F.Table.d) < 1e-9 and math.abs((r[4] - r[3]) - F.Table.w) < 1e-9)
		local l = I.footprint({ kind = "Counter", a = { -4, 2 }, b = { 4, 2 } }, F)
		assert(l[1] == -4 and l[2] == 4 and math.abs(l[4] - l[3] - F.Counter.d) < 1e-9)
	end,
	["the stairs: back wall from the ground floor, front from the first, none above the top"] = function()
		local b = box(30, 20, 3, {})
		local s0, s1 = I.stairs(b, M, 1, 0), I.stairs(b, M, 1, 1)
		assert(s0 and s0[4] == 9 and s1 and s1[3] == -9, "flights alternate back and front")
		assert(I.stairs(b, M, 1, 2) == nil, "no flight from the top floor")
	end,
	["an empty room walks; a wall across it cuts the back off"] = function()
		local count, reached, missing = I.walk(box(30, 20, 1, {}), M, F, 1, 0, cfg)
		assert(count > 0 and reached == count and #missing == 0)
		local sealed = box(30, 20, 1, { { kind = "Partition", a = { -15, 2 }, b = { 15, 2 }, h = 12 } })
		local c2, r2 = I.walk(sealed, M, F, 1, 0, cfg)
		assert(r2 < c2 * cfg.reach, "a sealed back room should fail the reach")
	end,
	["a table in the doorway is caught"] = function()
		local b = box(30, 20, 1, { { kind = "Table", x = 0, z = -7 } })
		local hit = false
		for _, k in I.keepOuts(b, M, 1, 0, cfg) do
			hit = hit or I.overlap(I.footprint(b.interior[1], F), k, 0.01)
		end
		assert(hit, "the door's keep-out should catch it")
	end,
}

for _, e in furnished() do
	local b, T = e.b, e.T
	local H = b.storyHeight or M.Building.StoryHeight
	tests[`{e.name}: its furniture inside its walls, clear of its doors and stairs, apart`] = function()
		local inner = I.inner(b, T)
		for i, p in b.interior do
			local s = p.story or 0
			assert(s >= 0 and s < b.stories, `{p.kind} {i} on story {s} of {b.stories}`)
			local r = I.footprint(p, F)
			assert(
				r[1] >= inner[1] - 0.05
					and r[2] <= inner[2] + 0.05
					and r[3] >= inner[3] - 0.05
					and r[4] <= inner[4] + 0.05,
				`{p.kind} {i} pokes through a wall`
			)
			assert(I.height(p, F, H) <= H, `{p.kind} {i} taller than the room`)
			for _, k in I.keepOuts(b, M, T, s, cfg) do
				assert(not I.overlap(r, k, 0.01), `{p.kind} {i} in a doorway or on the stairs`)
			end
			for j, q in b.interior do
				if j > i and (q.story or 0) == s then
					assert(not I.overlap(r, I.footprint(q, F), 0.01), `{p.kind} {i} overlaps {q.kind} {j}`)
				end
			end
		end
	end
	tests[`{e.name}: every floor walked from its doors to its stairs`] = function()
		for s = 0, b.stories - 1 do
			local count, reached, missing = I.walk(b, M, F, T, s, cfg)
			assert(#missing == 0, `story {s}: can't reach {missing[1] and missing[1].name}`)
			assert(reached >= count * cfg.reach, `story {s}: only {reached} of {count} cells reached`)
		end
	end
end

return tests
