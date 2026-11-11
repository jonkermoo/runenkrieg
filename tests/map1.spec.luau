--!strict
-- Layout invariants for Map 1 (rebuilt on the leg pattern, user approved 2026-11-10) against the metrics contract and the map rules (docs/maps/MAP_RULES.md).
local Front = require("../src/shared/Config/Frontline")
local M = require("../src/shared/Config/Metrics")
local Cfg = require("../src/shared/Config/MapCheck")
local Map = require("../src/shared/Config/Maps/Map1")
local MT = require("../src/shared/Rules/MapTerrain")
local R = require("../src/shared/Rules/Frontline")
local Sec = require("../src/shared/Rules/Sectors")
local SecCfg = require("../src/shared/Config/Sectors")

local sectors = Map.sectors

local function dist(a, b): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

local function unit(x: number, z: number): (number, number)
	local l = math.sqrt(x * x + z * z)
	return x / l, z / l
end

-- the first `rows` rows of `side`'s wave line while sector `i` is its front sector, as src/server/Frontline stands it on
-- a map with the leg pattern: at the sector's rally (Rules/MapTerrain.rally), facing the enemy's next point
local function waveLine(side: string, i: number, rows: number): { { number } }
	local cx, cz, fx, fz = MT.rally(Map, i, side)
	assert(cx and cz and fx and fz, `{side} has no rally at {sectors[i].id}`)
	local out = {}
	for k = 1, rows * Front.Line.perRow do
		local r, b = R.slot(k, Front.Line)
		table.insert(out, { cx - fz * r - fx * b, cz + fx * r - fz * b })
	end
	return out
end

-- (x, z) `u` out from sector i toward its neighbour on `side`'s enemy end and `n` across
local function at(i: number, side: string, u: number, n: number): { number }
	local dx, dz = MT.legWay(Map, i, side)
	local x, z = MT.along(sectors[i].x, sectors[i].z, dx :: number, dz :: number, u, n)
	return { x, z }
end

-- whether the ground leaves a clear line from `ah` over the ground at a to `bh` over the ground at b
local function clear(a: { number }, ah: number, b: { number }, bh: number): boolean
	local ya, yb = MT.heightAt(Map, a[1], a[2]) + ah, MT.heightAt(Map, b[1], b[2]) + bh
	local d = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	for t = 2, d - 2, 2 do
		local k = t / d
		if MT.heightAt(Map, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k) > ya + (yb - ya) * k then
			return false
		end
	end
	return true
end

return {
	["rallies: each side's spawn behind its own crest, in its own sector, on dry ground clear of trees (user 2026-11-06)"] = function()
		local B = require("../src/shared/Config/Buildings")
		local P = require("../src/shared/Config/Props")
		local V = require("../src/shared/Rules/Village")
		local lots = V.layout(Map, B, M, MT, P).lots
		local quads = R.lineQuads(sectors, Front.Line, Front.Line.treeClear, MT.rallyOf(Map))
		local rows = Front.Line.tries // Front.Line.perRow
		for i, s in sectors do
			for _, side in { "West", "East" } do
				if MT.legWay(Map, i, side) then
					local cx, cz = MT.rally(Map, i, side)
					local d = dist({ x = cx :: number, z = cz :: number }, s)
					local want = s.rally or Map.legs.rally
					assert(math.abs(d - want) < 1e-6 and want < Map.legs.crest.u - 20, "behind the crest")
					for _, p in waveLine(side, i, rows) do
						local id = Sec.sectorAt(Map, MT, p[1], p[2], SecCfg.Divider.RiverSegments)
						assert(id == s.id, `{side}'s line at {s.id} reaches into {id}`)
						assert(not MT.isRiver(Map, p[1], p[2]), `{side}'s line at {s.id} stands in the river`)
						local inside = false
						for _, q in quads do
							inside = inside or V.pointInQuad(p[1], p[2], q)
						end
						assert(inside, `a slot of {side}'s line at {s.id} isn't in its cleared ground`)
					end
				end
			end
		end
		for _, t in V.naturalTrees(Map, MT, lots, Map.village.trees.buildingClear, quads) do
			for _, q in quads do
				assert(not V.pointInQuad(t.x, t.z, q), "a tree on a wave line's ground")
			end
		end
	end,
	["spawns behind cover: no enemy short of the crest sees a rally (its point, crest, lane, the open ground)"] = function()
		local eye, head = M.Character.EyeHeight, M.Character.Height
		local C = Map.legs
		for i = 1, #sectors - 1 do
			for _, p in { { "West", i, "East", i + 1 }, { "East", i + 1, "West", i } } do
				local side, own, foe, from = p[1] :: string, p[2] :: number, p[3] :: string, p[4] :: number
				if sectors[own].crest == false then
					continue -- (a town: its houses hide its spawns, checked by the Studio audit with the buildings)
				end
				local viewers = waveLine(foe, from, 1)
				table.insert(viewers, { sectors[from].x, sectors[from].z })
				-- the enemy on its own crest facing us, in the lane it attacks us from, halfway across the open ground
				for _, n in { -80, 0, 80 } do
					table.insert(viewers, at(from, foe, C.crest.u, n))
					table.insert(viewers, at(own, side, C.fold.u, n))
					table.insert(viewers, at(own, side, dist(sectors[own], sectors[from]) / 2, n))
				end
				for _, slot in waveLine(side, own, 2) do
					for _, v in viewers do
						assert(
							not clear(v, eye, slot, head),
							`{side}'s line at {sectors[own].id} seen from {v[1]}, {v[2]}`
						)
					end
				end
			end
		end
	end,
	["an attacked point's reinforcements can't see it: the spawn a sector back is hidden from its zone and crests"] = function()
		local eye, head = M.Character.EyeHeight, M.Character.Height
		local C = Map.legs
		for i = 2, #sectors - 1 do
			for _, side in { "West", "East" } do
				local back = if side == "West" then i - 1 else i + 1
				if sectors[back].crest == false then
					continue -- (a town: its houses hide its spawns, checked by the Studio audit with the buildings)
				end
				local viewers = {}
				for k = 0, 15 do
					local a = k * math.pi / 8
					table.insert(viewers, {
						sectors[i].x + math.cos(a) * sectors[i].radius,
						sectors[i].z + math.sin(a) * sectors[i].radius,
					})
				end
				local foe = if side == "West" then "East" else "West"
				for _, n in { -80, 0, 80 } do
					table.insert(viewers, at(i, foe, C.crest.u, n)) -- the crest facing the spawn
				end
				for _, slot in waveLine(side, back, 2) do
					for _, v in viewers do
						assert(
							not clear(slot, eye, v, head),
							`{side}'s spawn at {sectors[back].id} sees {sectors[i].id} at {v[1]}, {v[2]}`
						)
					end
				end
				local d = dist(sectors[i], sectors[back]) - C.rally
				assert(d > 400, `{side} reinforces {sectors[i].id} from {d} studs`)
			end
		end
	end,
	["the leg pattern: crests stand over the point and the open ground, knolls rise; no sunken lanes (user 2026-11-10)"] = function()
		local C = Map.legs
		local function h(q: { number }): number
			return MT.heightAt(Map, q[1], q[2])
		end
		for i, s in sectors do
			for _, side in { "West", "East" } do
				local o = sectors[if side == "West" then i + 1 else i - 1]
				if o and s.crest ~= false then
					local top = h(at(i, side, C.crest.u, 0))
					local base = h({ s.x, s.z })
					assert(top - base > 4 or s.isHQ, `{s.id}'s {side} crest stands {top - base} over its point`)
					-- over the open ground at its foot; the swell further out (user 2026-11-10: "not every sector
					-- visible") lower than it, so its defenders still see over it
					local foot = at(i, side, C.crest.u + C.crest.width, 0)
					assert(top - h(foot) > 4, `{s.id}'s {side} crest stands {top - h(foot)} over the open ground`)
					local mid = at(i, side, dist(s, o) / 2, 0)
					assert(top > h(mid), `{s.id}'s {side} crest stands {top - h(mid)} over the swell`)
					for _, sgn in { -1, 1 } do
						local k = at(i, side, C.knoll.u, sgn * C.knoll.n)
						local foot = at(i, side, C.knoll.u, sgn * (C.knoll.n + C.knoll.radius + 6))
						assert(h(k) - h(foot) > 4, `{s.id}'s knoll is {h(k) - h(foot)} high`)
					end
				end
			end
		end
	end,
	["copses and lone trees on the open ground, off the way between the points, knolls, gun pads and rallies (user 2026-11-10)"] = function()
		local O = Map.legs.open
		local L = MT.legPieces(Map)
		local open = 0
		for _, t in MT.trees(Map) do
			local near = MT.chainDistance(Map, t.x, t.z)
			if near >= Map.legs.calm.width then
				continue
			end
			open += 1
			assert(near >= O.lane, `a tree in the way between the points at {t.x}, {t.z}`)
			for _, k in L.knolls do
				assert((t.x - k.x) ^ 2 + (t.z - k.z) ^ 2 >= O.knollClear ^ 2, `a tree on a knoll at {t.x}, {t.z}`)
			end
			for _, p in L.pads do
				assert((t.x - p.x) ^ 2 + (t.z - p.z) ^ 2 >= O.padClear ^ 2, `a tree on a gun pad at {t.x}, {t.z}`)
			end
		end
		assert(open >= 150 and open <= 900, `{open} trees on the open ground`)
	end,
	["the step: the end legs turn 15-25 degrees south, the middle ones 2-8 north, point-symmetric about S3"] = function()
		local c = sectors[3]
		for i = 1, #sectors - 1 do
			local a, b = sectors[i], sectors[i + 1]
			local turn = math.deg(math.atan((b.z - a.z) / (b.x - a.x)))
			if i == 1 or i == #sectors - 1 then
				assert(turn <= -15 and turn >= -25, `{a.id}->{b.id} turns {turn}`)
			else
				assert(turn >= 2 and turn <= 8, `{a.id}->{b.id} turns {turn}`)
			end
			local m = sectors[#sectors + 1 - i]
			assert(m.x == 2 * c.x - a.x and m.z == 2 * c.z - a.z, `{a.id} has no mirror`)
		end
	end,
	["chain is 5 points, an HQ at each end (user 2026-10-27: S1 and S5 are the HQs)"] = function()
		assert(#sectors == 5, "expected 5 entries")
		assert(sectors[1].isHQ and sectors[#sectors].isHQ, "chain must start and end with an HQ")
		for i = 2, #sectors - 1 do
			assert(not sectors[i].isHQ, `{sectors[i].id} is fought over, not an HQ`)
		end
	end,
	["exactly one neutral sector, in the center"] = function()
		local neutral = {}
		for i, s in sectors do
			if s.startOwner == "Neutral" then
				table.insert(neutral, i)
			end
		end
		assert(#neutral == 1 and neutral[1] == 3, "the center sector must be the only neutral one")
	end,
	["start ownership is symmetric"] = function()
		for i = 1, 2 do
			assert(sectors[i].startOwner == "West", `{sectors[i].id} should start West`)
			assert(sectors[#sectors + 1 - i].startOwner == "East", `{sectors[#sectors + 1 - i].id} should start East`)
		end
	end,
	["sector spacing within 15% of the metric"] = function()
		for i = 1, #sectors - 1 do
			local d = dist(sectors[i], sectors[i + 1])
			local target = 520 -- (the map rework's spacing, user 2026-11-06; Metrics.Sector.Spacing is Map 1's 420)
			assert(math.abs(d - target) / target <= 0.05, `{sectors[i].id}->{sectors[i + 1].id} is {d}`)
		end
	end,
	["capture zones never overlap"] = function()
		for i = 1, #sectors - 1 do
			local a, b = sectors[i], sectors[i + 1]
			assert(dist(a, b) > a.radius + b.radius, `{a.id} and {b.id} overlap`)
		end
	end,
	["sectors sit inside the playable bounds"] = function()
		local b = Map.bounds
		for _, s in sectors do
			assert(s.x - s.radius >= b.minX and s.x + s.radius <= b.maxX, `{s.id} out of X bounds`)
			assert(s.z - s.radius >= b.minZ and s.z + s.radius <= b.maxZ, `{s.id} out of Z bounds`)
		end
	end,
	["the river runs between the S3 and S4 zones, far from the HQs"] = function()
		local r = Map.river
		local reach = r.width / 2 + r.bankWidth
		for _, s in sectors do
			local d = MT.riverDistance(Map, s.x, s.z)
			assert(d > s.radius + reach, `the river cuts into {s.id}`)
		end
		local s3, s4 = sectors[3], sectors[4]
		local _, qx = MT.riverNearest(Map, (s3.x + s4.x) / 2, (s3.z + s4.z) / 2)
		assert(qx > s3.x + s3.radius and qx < s4.x - s4.radius, "the river doesn't cross between S3 and S4")
		assert(MT.riverDistance(Map, sectors[1].x, sectors[1].z) > 600, "the West has no river")
		assert(MT.riverDistance(Map, sectors[5].x, sectors[5].z) > 600, "the East has no river")
	end,
	["the river: the rock ford and a narrow one, on the river, wadeable, deep between"] = function()
		local r = Map.river
		for _, f in r.fords do
			assert(f.width > M.Character.Width, "ford too narrow for a soldier")
			assert(MT.riverDistance(Map, f.x, f.z) < 3, `the ford at {f.x}, {f.z} is off the river`)
			local depth = r.waterY - MT.heightAt(Map, f.x, f.z)
			assert(depth > 0 and depth < Cfg.WadeDepth, `the ford at {f.x}, {f.z} is {depth} deep`)
		end
		for _, z in { 80, 220, -220 } do
			local _, cx, cz = MT.riverNearest(Map, 1690, z)
			assert(r.waterY - MT.heightAt(Map, cx, cz) > 4, `the river is shallow at {cx}, {cz}`)
		end
	end,
	["the crossings: one near each bot lane over it, S3 to S4 (Config/Bots.Routes)"] = function()
		local RT = require("../src/shared/Config/Bots").Routes
		local a, b = sectors[3], sectors[4]
		local wx, wz = b.x - a.x, b.z - a.z
		local len = math.sqrt(wx * wx + wz * wz)
		local crossings = {}
		for _, f in Map.river.fords do
			table.insert(crossings, f)
		end
		for _, br in Map.river.bridges do
			table.insert(crossings, br)
		end
		for _, k in { -1, 0, 1 } do
			-- the lane: from S3 through its waypoint (Bots/Commander) to S4; where it meets the river
			local mx = a.x + wx * RT.midShare - wz / len * k * len * RT.laneOffset
			local mz = a.z + wz * RT.midShare + wx / len * k * len * RT.laneOffset
			local hit
			for _, leg in { { a.x, a.z, mx, mz }, { mx, mz, b.x, b.z } } do
				for t = 0, 1, 0.002 do
					local x, z = leg[1] + (leg[3] - leg[1]) * t, leg[2] + (leg[4] - leg[2]) * t
					if not hit and MT.riverDistance(Map, x, z) < 2 then
						hit = { x, z }
					end
				end
			end
			assert(hit, `lane {k} never meets the river`)
			local near = math.huge
			for _, c in crossings do
				near = math.min(near, math.sqrt((c.x - hit[1]) ^ 2 + (c.z - hit[2]) ^ 2))
			end
			assert(near < 40, string.format("lane %d meets the river %.0f studs from a crossing", k, near))
		end
	end,
	["the rock ford: wide shallow water you can see (not a dry bar), wadeable, with its rock path"] = function()
		local r = Map.river
		local n = 0
		for _, f in r.fords do
			if f.rocks then
				n += 1
				assert(f.width >= 24, "the rock ford is narrow")
				for _, dz in { -f.width / 2 + 2, 0, f.width / 2 - 2 } do
					local _, cx, cz = MT.riverNearest(Map, f.x, f.z + dz)
					local depth = r.waterY - MT.heightAt(Map, cx, cz)
					assert(depth > 1.5 and depth < Cfg.WadeDepth, `the rock ford is {depth} deep at {dz}`)
				end
			end
		end
		assert(n == 1, "one rock ford")
		-- its voxels sunk so the water shows: the whole sink on the ford's bed, none off it or at the other fords
		for _, f in r.fords do
			local _, cx, cz = MT.riverNearest(Map, f.x, f.z)
			local want = f.sink or 0
			assert(math.abs(MT.fordSink(Map, cx, cz) - want) < 1e-6, `ford at {f.z} sinks {MT.fordSink(Map, cx, cz)}`)
		end
		assert(MT.fordSink(Map, 1600, 0) == 0, "sinks dry land")
	end,
	["the bridges: on the river, ends on dry banks, a walkable deck over the water"] = function()
		local r = Map.river
		local maxRise = math.tan(math.rad(M.Movement.MaxSlopeAngle))
		for _, br in r.bridges do
			assert(MT.riverDistance(Map, br.x, br.z) < 3, `{br.id} is off the river`)
			assert(br.width > M.Character.Width + 2, `{br.id} too narrow`)
			local f = MT.bridgeFrame(Map, br)
			for _, s in { 0, f.length } do
				local x, z = f.ax + f.ux * s, f.az + f.uz * s
				assert(MT.riverDistance(Map, x, z) > r.width / 2 + r.bankWidth, `{br.id}'s end is on the bank`)
				assert(MT.heightAt(Map, x, z) > r.waterY, `{br.id}'s end is under water`)
			end
			if br.deck then
				local prev = MT.deckHeight(Map, br, f, 0)
				for s = 1, f.length do
					local y = MT.deckHeight(Map, br, f, s)
					assert(y > r.waterY + 1, `{br.id}'s deck in the water at {s}`)
					assert(math.abs(y - prev) < maxRise, `{br.id}'s deck too steep at {s}`)
					prev = y
				end
			end
		end
	end,
	["the main region: Map 1 replaces all terrain, Lantern Meadows' and the playtest ground stay clear of it"] = function()
		assert(not Map.offMap, "Map 1 is the main map")
	end,
	["fair cover: the natural rises mirror through S3's point, like the points (user 2026-11-10)"] = function()
		local c = sectors[3]
		local L = MT.legPieces(Map)
		local twins = 0
		for _, cr in L.crests do
			local twin = #sectors + 1 - cr.sector
			local has = false
			for _, o in L.crests do
				has = has or (o.sector == twin and o.side ~= cr.side)
			end
			if not has then
				continue -- (its twin is Ashby's, a town with no crest)
			end
			twins += 1
			for b = -160, 160, 10 do
				for a = -40, 40, 8 do
					local x, z = cr.cx + cr.dx * a - cr.dz * b, cr.cz + cr.dz * a + cr.dx * b
					local here = MT.legShape(Map, x, z)
					local there = MT.legShape(Map, 2 * c.x - x, 2 * c.z - z)
					assert(math.abs(here - there) < 1e-6, `the rise at {x}, {z} is {here}, its twin {there}`)
				end
			end
		end
		assert(twins >= 4, `{twins} crests with a twin`)
	end,
	["the rises are natural: each crest's line wanders and its height varies along it (user 2026-11-10)"] = function()
		local C = Map.legs.crest
		local L = MT.legPieces(Map)
		for _, cr in L.crests do
			local lo, hi, tops = math.huge, -math.huge, {}
			for b = -90, 90, 15 do
				local best, at = -math.huge, 0
				for a = -40, 40, 1 do
					local x, z = cr.cx + cr.dx * a - cr.dz * b, cr.cz + cr.dz * a + cr.dx * b
					local v = MT.legShape(Map, x, z)
					if v > best then
						best, at = v, a
					end
				end
				lo, hi = math.min(lo, best), math.max(hi, best)
				table.insert(tops, at)
			end
			local wander = math.max(table.unpack(tops)) - math.min(table.unpack(tops))
			assert(wander >= 6, `sector {cr.sector}'s {cr.side} crest is straight (its top wanders {wander})`)
			assert(hi - lo >= 1.5, `sector {cr.sector}'s {cr.side} crest is level ({lo} to {hi})`)
			assert(lo > 2 and hi < C.height * 2, `sector {cr.sector}'s {cr.side} crest {lo} to {hi} high`)
		end
	end,
	["each spawn sits behind its own HQ, ~400 out, still in the HQ's sector (user 2026-11-02)"] = function()
		for side, i in { West = 1, East = #sectors } do
			local r, hq = Map.spawnZones[side], sectors[i]
			local d = dist({ x = (r.minX + r.maxX) / 2, z = (r.minZ + r.maxZ) / 2 }, hq)
			assert(d > 380 and d < 460, `{side} spawn {d} from its HQ`)
			for _, c in { { r.minX, r.minZ }, { r.maxX, r.minZ }, { r.maxX, r.maxZ }, { r.minX, r.maxZ } } do
				assert(
					Sec.sectorAt(Map, MT, c[1], c[2], SecCfg.Divider.RiverSegments) == hq.id,
					`{side} spawn leaves {hq.id}`
				)
			end
			local behind = if side == "West" then r.maxX < hq.x - hq.radius else r.minX > hq.x + hq.radius
			assert(behind, `{side} spawn isn't behind its HQ`)
		end
	end,
	["map fits the fog: you cannot see HQ to HQ"] = function()
		assert(dist(sectors[1], sectors[#sectors]) > Map.fogEnd, "map too small for its fog")
	end,
}
