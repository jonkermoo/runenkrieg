--!strict
-- Every frontline map's village (Rules/Village): buildings, boundaries, props, trees, the railway.
local M = require("../src/shared/Config/Metrics")
local B = require("../src/shared/Config/Buildings")
local Maps = require("./frontlinemaps")
local MT = require("../src/shared/Rules/MapTerrain")
local V = require("../src/shared/Rules/Village")
local P = require("../src/shared/Config/Props")

return Maps.each(function(map: any, name: string)
	local layout = V.layout(map, B, M, MT, P)
	local lots = layout.lots
	local cfg = map.village
	local pad = B.RoofOverhang

	return {
		["deterministic"] = function()
			local again = V.layout(map, B, M, MT, P)
			assert(#again.lots == #lots and again.lots[#lots].x == lots[#lots].x, "layout changed between runs")
		end,
		["about 30 buildings, with every style family present"] = function()
			if name ~= "Map1" then
				return -- (Lantern Meadows' houses come with Selvara's house kit)
			end
			assert(#lots >= 26 and #lots <= 36, `{#lots} buildings`)
			local styles = {}
			for _, l in lots do
				styles[l.style] = true
			end
			for _, s in { "ThatchCottage" } do
				assert(styles[s], `no {s}`)
			end
		end,
		["buildings never overlap and keep a walkable gap"] = function()
			for i = 1, #lots do
				for j = i + 1, #lots do
					local a = V.corners(lots[i], pad + cfg.buildingGap / 2 - 0.01)
					local b = V.corners(lots[j], pad + cfg.buildingGap / 2 - 0.01)
					assert(not V.quadsOverlap(a, b), `{lots[i].id} overlaps {lots[j].id}`)
				end
			end
		end,
		["the spawn zones are clear of buildings (Normal mode: S1 / S5 spawns, the East one in the village)"] = function()
			for side, r in map.spawnZones do
				for _, l in lots do
					for x = r.minX, r.maxX, 4 do
						for z = r.minZ, r.maxZ, 4 do
							assert(not V.pointInQuad(x, z, V.corners(l, pad)), `{side} spawn on {l.id}`)
						end
					end
				end
			end
		end,
		["no building sits on a road, in the river or in a kept-clear square"] = function()
			for _, l in lots do
				for _, c in V.corners(l, pad) do
					assert(MT.roadDistance(map, c[1], c[2]) > 0, `{l.id} corner on a road`)
					for _, k in cfg.keepClear do
						assert((c[1] - k.x) ^ 2 + (c[2] - k.z) ^ 2 >= k.r * k.r, `{l.id} in a kept-clear square`)
					end
				end
				assert(not MT.isRiver(map, l.x, l.z) or B.Templates[l.style].waterside, `{l.id} in the river`)
			end
		end,
		["no building on a wave line (where a side's soldiers stand when they hold a point; Rules/Frontline)"] = function()
			local FR = require("../src/shared/Rules/Frontline")
			local Line = require("../src/shared/Config/Frontline").Line
			local S = map.sectors
			-- (a map with the leg pattern: every sector's rallies, Rules/MapTerrain.rally; the landmark compounds' own
			-- buildings, not their whole footprint: a strongpoint's yard is open)
			for i = if map.legs then 1 else 2, if map.legs then #S else #S - 1 do
				for _, side in { "West", "East" } do
					local cx, cz
					if map.legs then
						cx, cz = MT.rally(map, i, side)
					else
						cx, cz = FR.lineCentre(S, i, side, Line)
					end
					local aim = S[if side == "West" then i + 1 else i - 1]
					if not (cx and cz and aim) then
						continue
					end
					local fx, fz = aim.x - cx, aim.z - cz
					local l = math.sqrt(fx * fx + fz * fz)
					fx, fz = fx / l, fz / l
					for k = 1, Line.tries do
						local r, bk = FR.slot(k, Line)
						local x, z = cx - fz * r - fx * bk, cz + fx * r - fz * bk
						local h = Line.clear[1] / 2
						local q = { { x - h, z - h }, { x + h, z - h }, { x + h, z + h }, { x - h, z + h } }
						for _, lot in lots do
							-- (the lot with its eaves and a garden wall's width round it)
							for _, f in V.footprints(lot, B, pad + 3) do
								assert(not V.quadsOverlap(f.corners, q), `{lot.id} on {S[i].id} {side}'s wave line`)
							end
						end
					end
				end
			end
		end,
		["every road-side house faces its road (door within reach of the road)"] = function()
			for _, l in lots do
				if not l.special and l.road then -- (a hand-placed house off the road has none)
					local dx, dz = l.x + l.fx * (l.depth / 2 + 1), l.z + l.fz * (l.depth / 2 + 1)
					assert(MT.roadDistance(map, dx, dz) < cfg.setback + 6, `{l.id} door far from road`)
				end
			end
		end,
		["village is not wall-to-wall: built footprint under 35% of the area"] = function()
			local a = cfg.area
			local built = 0
			for _, l in lots do
				if l.x >= a.minX and l.x <= a.maxX then
					built += l.width * l.depth
				end
			end
			local frac = built / ((a.maxX - a.minX) * (a.maxZ - a.minZ))
			assert(frac < 0.35, `built fraction {frac}`)
		end,
		["two-story buildings fit a full stair flight"] = function()
			local run = function(h: number)
				return h / M.Building.StairRise * M.Building.StairRun
			end
			for _, l in lots do
				if l.stories >= 2 then
					assert(l.width - 2 >= run(l.storyHeight) + 3, `{l.id} too narrow for its stairs`)
				end
			end
		end,
		["garden trees avoid roads and buildings"] = function()
			for _, t in layout.trees do
				assert(MT.roadDistance(map, t.x, t.z) > cfg.trees.roadClear, "tree on road")
				for _, l in lots do
					assert(not V.pointInQuad(t.x, t.z, V.corners(l, pad)), `tree inside {l.id}`)
				end
			end
			assert(name ~= "Map1" or #layout.trees > 20, "village needs trees")
		end,
		["roads are painted on the terrain"] = function()
			local r = cfg.roads[1]
			local x, z = V.pointAt(r.points, 300)
			assert(MT.materialAt(map, x, z) == "Sand", "main road not painted")
		end,
		["props exist"] = function()
			if name == "Map1" then
				assert(#layout.poles >= 10 and #layout.signs >= 3 and #layout.cars >= 2 and #layout.fences > 10)
			else
				assert(#layout.fences >= 10 and #layout.yard >= 8, "Lantern Meadows: its hedgerows and lantern poles")
			end
		end,
		["boundaries use real prop kinds, never sit on roads, and leave every door's gate open"] = function()
			for _, f in layout.fences do
				assert(table.find(P.Kinds, f.kind), `unknown boundary {f.kind}`)
				for k = 0, 4 do
					local x = f.a[1] + (f.b[1] - f.a[1]) * k / 4
					local z = f.a[2] + (f.b[2] - f.a[2]) * k / 4
					assert(MT.roadDistance(map, x, z) >= 0.5, "boundary on a road")
				end
			end
			-- the path straight out of each front door must not cross a boundary
			for _, l in lots do
				local rx, rz = -l.fz, l.fx
				for _, door in V.frontDoors(B.Templates[l.style]) do
					local px = l.x + rx * door.center + l.fx * (l.depth / 2 + cfg.setback - 1.5)
					local pz = l.z + rz * door.center + l.fz * (l.depth / 2 + cfg.setback - 1.5)
					for _, f in layout.fences do
						local dx, dz = f.b[1] - f.a[1], f.b[2] - f.a[2]
						local len2 = dx * dx + dz * dz
						local t = math.clamp(((px - f.a[1]) * dx + (pz - f.a[2]) * dz) / len2, 0, 1)
						local d = math.sqrt((px - f.a[1] - dx * t) ^ 2 + (pz - f.a[2] - dz * t) ^ 2)
						assert(d > 1.5, `{l.id} door gate blocked`)
					end
				end
			end
		end,
		["yard clutter is real, off roads and outside other plots"] = function()
			assert(#layout.yard >= 8, `only {#layout.yard} yard props`)
			for _, y in layout.yard do
				assert(table.find(P.Kinds, y.kind), `unknown yard prop {y.kind}`)
				assert(MT.roadDistance(map, y.x, y.z) > 0, `{y.kind} on a road`)
			end
		end,
		["ground sampled over the whole footprint and round it: corners, edges and inside, no gap over the step"] = function()
			local g = B.GroundSample
			for _, l in lots do
				local pts = V.footprintPoints(l, g.pad, g.step)
				for _, c in V.corners(l, g.pad) do
					local hit = false
					for _, p in pts do
						hit = hit or (math.abs(p[1] - c[1]) < 1e-6 and math.abs(p[2] - c[2]) < 1e-6)
					end
					assert(hit, `{l.id}: a corner isn't sampled`)
				end
				local nu = math.ceil((l.width + 2 * g.pad) / g.step)
				local nv = math.ceil((l.depth + 2 * g.pad) / g.step)
				assert(#pts == (nu + 1) * (nv + 1), `{l.id}: {#pts} samples`)
				assert((l.width + 2 * g.pad) / nu <= g.step and (l.depth + 2 * g.pad) / nv <= g.step)
			end
		end,
		["the ground round a building: level with its base near the walls, rising beyond, natural past the reach"] = function()
			local c = B.GroundCut
			assert(V.cutHeight(5, 0, c) == 5 and V.cutHeight(5, c.margin, c) == 5)
			assert(math.abs((V.cutHeight(5, c.margin + 2, c) :: number) - (5 + 2 * c.grade)) < 1e-9)
			assert(V.cutHeight(5, c.reach + 0.1, c) == nil)
			assert(V.railBed({ 1, 3.5, -2 }) == 3.5)
		end,
		["steps down from a high door: a rise each, until the ground is within a step"] = function()
			local S = B.Steps
			assert(#V.steps(10, function()
				return 9.5
			end, S.rise, S.run, S.max) == 0, "a door within a step of the ground gets none")
			local flat = V.steps(10, function()
				return 4
			end, S.rise, S.run, S.max)
			assert(#flat == math.ceil((10 - 4) / S.rise) - 1, `{#flat} steps down 6`)
			assert(
				flat[#flat].top - 4 <= S.rise
					and flat[1].top == 10 - S.rise
					and math.abs(flat[2].out - flat[1].out - S.run) < 1e-9
			)
			assert(S.rise <= M.Character.MaxStepUp, "a step a soldier walks up")
			local slope = V.steps(10, function(d: number)
				return 6 - d
			end, S.rise, S.run, S.max)
			assert(#slope == S.max, "the ground falling away as fast: at most max")
		end,
		["a footing only where the ground falls past the foundation"] = function()
			assert(V.footing(10, 5, B.FoundationDepth) == 0)
			assert(V.footing(10, 0, B.FoundationDepth) == 0)
			assert(V.footing(10, -4, B.FoundationDepth) == 4)
		end,
		["the railway runs clear of every building (a station's footprint stops short of its near rail)"] = function()
			if not cfg.railX then
				return
			end
			local x0, half = cfg.railX, P.Railway.gauge / 2 + 0.3
			for _, l in lots do
				local q = V.corners(l, 0)
				local lo, hi = math.huge, -math.huge
				for _, c in q do
					lo, hi = math.min(lo, c[1]), math.max(hi, c[1])
				end
				assert(hi < x0 - half or lo > x0 + half, `{l.id} stands on the railway`)
				if B.Templates[l.style].railside then
					assert(x0 - half - hi < 3, `{l.id} is a station far from its line`)
				end
			end
		end,
		["the railway: Map 1's along its east edge, none on a map without a village (Playtest)"] = function()
			assert(V.railX(map) == cfg.railX)
			assert(V.railX(require("../src/shared/Config/Maps/Playtest")) == nil)
			assert(V.railX({}) == nil)
		end,
		["no telegraph pole in a kept-clear square"] = function()
			for _, p in layout.poles do
				for _, k in cfg.keepClear do
					assert((p.x - k.x) ^ 2 + (p.z - k.z) ^ 2 >= k.r * k.r, "a pole in a kept-clear square")
				end
			end
		end,
	}
end)
