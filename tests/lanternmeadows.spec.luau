--!strict
-- Layout invariants for Lantern Meadows against the metrics contract and the map rules (docs/maps/MAP_RULES.md).
local Front = require("../src/shared/Config/Frontline")
local M = require("../src/shared/Config/Metrics")
local Cfg = require("../src/shared/Config/MapCheck")
local Map = require("../src/shared/Config/Maps/LanternMeadows")
local Map1 = require("../src/shared/Config/Maps/Map1")
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
	["the leg pattern: crests stand over the point and the open ground, lanes are sunk, knolls rise"] = function()
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
					-- over the open ground at its foot; the swells further out (user 2026-11-10: "the meadow map is so
					-- flat you can see everything") lower than it, so its defenders still see over them
					local foot = at(i, side, C.crest.u + C.crest.width, 0)
					assert(top - h(foot) > 4, `{s.id}'s {side} crest stands {top - h(foot)} over the open ground`)
					for _, k in { 0.35, 0.5, 0.65 } do
						local q = at(i, side, dist(s, o) * k, 0)
						assert(top > h(q), `{s.id}'s {side} crest stands {top - h(q)} under a swell`)
					end
					local floor = h(at(i, side, C.fold.u, 0))
					local lip = math.max(h(at(i, side, C.fold.u - 14, 0)), h(at(i, side, C.fold.u + 14, 0)))
					assert(lip - floor > 3.5, `{s.id}'s {side} lane is {lip - floor} deep`)
					for _, sgn in { -1, 1 } do
						local k = at(i, side, C.knoll.u, sgn * C.knoll.n)
						local foot = at(i, side, C.knoll.u, sgn * (C.knoll.n + C.knoll.radius + 6))
						assert(h(k) - h(foot) > 4, `{s.id}'s knoll is {h(k) - h(foot)} high`)
					end
				end
			end
		end
	end,
	["the open ground is open: no trees along the chain (user 2026-11-06)"] = function()
		for _, t in MT.trees(Map) do
			assert(MT.chainDistance(Map, t.x, t.z) >= Map.legs.calm.width, `a tree at {t.x}, {t.z}`)
		end
	end,
	["the arch: legs 600 long, turning 4-25 degrees, mirrored about S3's x (user 2026-11-06; 600 since the 2026-11-11 stretch)"] = function()
		local mx = sectors[3].x
		for i = 1, #sectors - 1 do
			local a, b = sectors[i], sectors[i + 1]
			local turn = math.deg(math.atan(math.abs(b.z - a.z) / (b.x - a.x)))
			assert(turn >= 4 and turn <= 25, `{a.id}->{b.id} turns {turn}`)
			local m = sectors[#sectors + 1 - i]
			assert(m.x == 2 * mx - a.x and m.z == a.z, `{a.id} has no mirror`)
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
			local target = 600 -- (Metrics.Sector.Spacing since the stretch, user 2026-11-11: "maps need to be longer and less wide")
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
	["the Aurel runs between the S3 and S4 zones, then past S5 along the south edge"] = function()
		local r = Map.river
		local reach = r.width / 2 + r.bankWidth
		for _, s in sectors do
			local d = MT.riverDistance(Map, s.x, s.z)
			assert(d > s.radius + reach, `the river cuts into {s.id}`)
		end
		-- crossing: on the S3-S4 line, the river lies between the two points
		local s3, s4 = sectors[3], sectors[4]
		local _, qx = MT.riverNearest(Map, (s3.x + s4.x) / 2, (s3.z + s4.z) / 2)
		assert(qx > s3.x + s3.radius and qx < s4.x - s4.radius, "the river doesn't cross between S3 and S4")
		-- the bend: S5's camp is on the river (its south bank within reach of the point's rise)
		local s5, wet = sectors[5], nil
		-- (just past the south edge since the 2026-11-11 stretch to 560 wide)
		for z = s5.z, Map.bounds.minZ - 80, -2 do
			wet = wet or (MT.riverDistance(Map, s5.x, z) < r.width / 2 and s5.z - z)
		end
		assert(wet and wet < 260, "S5 isn't by the river")
		assert(MT.riverDistance(Map, sectors[1].x, sectors[1].z) > 600, "the West has no river")
	end,
	["the Aurel: a wide festival ford, a narrow one and the rock ford, on the river, wadeable, deep between"] = function()
		local r = Map.river
		local wide, narrow = 0, 0
		for _, f in r.fords do
			assert(f.width > M.Character.Width, "ford too narrow for a soldier")
			if f.width >= 16 then
				wide += 1
			else
				narrow += 1
			end
			assert(MT.riverDistance(Map, f.x, f.z) < 3, `the ford at {f.x}, {f.z} is off the river`)
			local depth = r.waterY - MT.heightAt(Map, f.x, f.z)
			assert(depth > 0 and depth < Cfg.WadeDepth, `the ford at {f.x}, {f.z} is {depth} deep`)
		end
		assert(wide >= 2 and narrow >= 1, "need 2+ wide fords (the festival and the rock ford) and a narrow one")
		for _, q in { { 1680, Map.bounds.minZ + 330 }, { 1685, Map.bounds.minZ + 560 }, { 2200, Map.bounds.minZ + 32 } } do
			local _, cx, cz = MT.riverNearest(Map, q[1], q[2])
			assert(r.waterY - MT.heightAt(Map, cx, cz) > 4, `the river is shallow at {cx}, {cz}`)
		end
	end,
	["the Aurel's crossings: one near each bot lane over it, S3 to S4 (Config/Bots.Routes)"] = function()
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
		assert(MT.fordSink(Map, 1600, Map.sectors[4].z) == 0, "sinks dry land")
	end,
	["the Aurel's bridges: on the river, ends on dry banks, a walkable deck over the water"] = function()
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
	["a house built of blocks has its gates at its blocks' doors (the long house's, under its portico and beside it)"] = function()
		local B = require("../src/shared/Config/Buildings")
		local V = require("../src/shared/Rules/Village")
		local d = V.frontDoors(B.Templates.SelvaLongHouse)
		assert(#d == 2 and d[1].center == -6 and d[2].center == 9, "long house doors")
		assert(V.frontDoors(B.Templates.SelvaCasetta)[1].center == 0)
	end,
	["built off Map 1: its ground and skirt clear of Map 1's"] = function()
		assert(Map.offMap, "Lantern Meadows replaces only its own terrain")
		local own = Map.terrainMargin + Map.skirt.width
		local other = Map1.terrainMargin + Map1.skirt.width
		assert(Map.bounds.maxZ + own < Map1.bounds.minZ - other, "Lantern Meadows' ground runs into Map 1's")
		assert(Map.bounds.minZ - own > -9000, "too far out")
	end,
	["fair cover: the lanes' hedge banks mirror over S3's x, like the points"] = function()
		local x0 = sectors[3].x
		local runs = Map.village.hedgerows
		assert(#runs >= 2 * 2 * (#sectors - 1), "two hedge runs on every lane")
		for _, h in runs do
			local found = false
			for _, o in runs do
				local ma, mb = { 2 * x0 - h.a[1], h.a[2] }, { 2 * x0 - h.b[1], h.b[2] }
				for _, pair in { { o.a, o.b }, { o.b, o.a } } do
					found = found
						or (
							math.abs(pair[1][1] - ma[1]) < 1e-6
							and math.abs(pair[1][2] - ma[2]) < 1e-6
							and math.abs(pair[2][1] - mb[1]) < 1e-6
							and math.abs(pair[2][2] - mb[2]) < 1e-6
						)
				end
			end
			assert(found, `a hedgerow from {h.a[1]}, {h.a[2]} has no mirror over S3`)
		end
	end,
	["each spawn sits behind its own HQ, ~300 out, still in the HQ's sector (user 2026-11-02; 300 since the 2026-11-11 stretch)"] = function()
		for side, i in { West = 1, East = #sectors } do
			local r, hq = Map.spawnZones[side], sectors[i]
			local d = dist({ x = (r.minX + r.maxX) / 2, z = (r.minZ + r.maxZ) / 2 }, hq)
			assert(d > 280 and d < 340, `{side} spawn {d} from its HQ`)
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
