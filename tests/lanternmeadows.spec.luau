--!strict
-- Layout invariants for Lantern Meadows against the metrics contract and the map rules (docs/maps/MAP_RULES.md).
local Front = require("../src/shared/Config/Frontline")
local M = require("../src/shared/Config/Metrics")
local Cfg = require("../src/shared/Config/MapCheck")
local Map = require("../src/shared/Config/Maps/LanternMeadows")
local Map1 = require("../src/shared/Config/Maps/Map1")
local MT = require("../src/shared/Rules/MapTerrain")
local R = require("../src/shared/Rules/Frontline")

local sectors = Map.sectors

local function dist(a, b): number
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

local function unit(x: number, z: number): (number, number)
	local l = math.sqrt(x * x + z * z)
	return x / l, z / l
end

-- the first `rows` rows of `side`'s wave line at sector `i`, as src/server/Frontline stands it: at its own HQ in its
-- spawn zone, else Line.edge past the zone toward its own end, facing the sector it attacks
local function waveLine(side: string, i: number, rows: number): { { number } }
	local s = sectors[i]
	local cx, cz
	if i == (if side == "West" then 1 else #sectors) then
		local r = Map.spawnZones[side]
		cx, cz = (r.minX + r.maxX) / 2, (r.minZ + r.maxZ) / 2
	else
		local b = sectors[if side == "West" then i - 1 else i + 1]
		local dx, dz = unit(b.x - s.x, b.z - s.z)
		cx, cz = s.x + dx * (s.radius + Front.Line.edge), s.z + dz * (s.radius + Front.Line.edge)
	end
	local aim = sectors[if side == "West" then i + 1 else i - 1]
	local fx, fz = unit(aim.x - cx, aim.z - cz)
	local out = {}
	for k = 1, rows * Front.Line.perRow do
		local r, b = R.slot(k, Front.Line)
		table.insert(out, { cx - fz * r - fx * b, cz + fx * r - fz * b })
	end
	return out
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
	["spawns behind cover: the ground hides a wave line from the next sector's point and wave line (user 2026-11-01)"] = function()
		local eye, head = M.Character.EyeHeight, M.Character.Height
		for i = 1, #sectors - 1 do
			for _, p in { { "West", i, "East", i + 1 }, { "East", i + 1, "West", i } } do
				local side, at, foe, from = p[1] :: string, p[2] :: number, p[3] :: string, p[4] :: number
				local viewers = waveLine(foe, from, 1)
				table.insert(viewers, { sectors[from].x, sectors[from].z })
				for _, slot in waveLine(side, at, 2) do
					for _, v in viewers do
						assert(
							not clear(v, eye, slot, head),
							`{side}'s line at {sectors[at].id} seen from {foe} at {sectors[from].id}`
						)
					end
				end
			end
		end
	end,
	["points on rises: the same crest everywhere, the zone's edge within the zone's height of its point"] = function()
		for _, s in sectors do
			local top = MT.heightAt(Map, s.x, s.z)
			assert(math.abs(top - Map.rise.height) < 1, `{s.id}'s crest is {top}`)
			for k = 0, 15 do
				local a = k * math.pi / 8
				local y = MT.heightAt(Map, s.x + math.cos(a) * s.radius, s.z + math.sin(a) * s.radius)
				assert(math.abs(y - top) < Front.Height, `{s.id}'s zone edge is {top - y} under its point`)
			end
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
			local target = M.Sector.Spacing
			assert(math.abs(d - target) / target <= 0.15, `{sectors[i].id}->{sectors[i + 1].id} is {d}`)
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
		for z = s5.z, Map.bounds.minZ, -2 do
			wet = wet or (MT.riverDistance(Map, s5.x, z) < r.width / 2 and s5.z - z)
		end
		assert(wet and wet < 220, "S5 isn't by the river")
		assert(MT.riverDistance(Map, sectors[1].x, sectors[1].z) > 600, "the West has no river")
	end,
	["the Aurel: a wide festival ford and two narrow ones, on the river, wadeable, deep between"] = function()
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
		assert(wide >= 1 and narrow >= 2, "need 1+ wide ford and 2+ narrow fords")
		for _, q in { { 1444, Map.bounds.minZ + 380 }, { 1445, Map.bounds.minZ + 180 }, { 2000, Map.bounds.minZ + 28 } } do
			local _, cx, cz = MT.riverNearest(Map, q[1], q[2])
			assert(r.waterY - MT.heightAt(Map, cx, cz) > 4, `the river is shallow at {cx}, {cz}`)
		end
	end,
	["built off Map 1: its ground and skirt clear of Map 1's"] = function()
		assert(Map.offMap, "Lantern Meadows replaces only its own terrain")
		local own = Map.terrainMargin + Map.skirt.width
		local other = Map1.terrainMargin + Map1.skirt.width
		assert(Map.bounds.maxZ + own < Map1.bounds.minZ - other, "Lantern Meadows' ground runs into Map 1's")
		assert(Map.bounds.minZ - own > -9000, "too far out")
	end,
	["fair cover: the hedgerows round S2 the same either side of its x, the landmarks on their point's x"] = function()
		local x0 = sectors[2].x
		local runs = {}
		for _, h in Map.village.hedgerows do
			table.insert(runs, h)
		end
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
			assert(found, `a hedgerow from {h.a[1]}, {h.a[2]} has no mirror over S2`)
		end
		for _, l in Map.village.specials do
			local nearest, d = nil, math.huge
			for _, s in sectors do
				local e = math.sqrt((l.x - s.x) ^ 2 + (l.z - s.z) ^ 2)
				if e < d then
					nearest, d = s, e
				end
			end
			if d < 200 then
				assert(l.x == nearest.x, `{l.id} isn't on {nearest.id}'s x`)
			end
		end
	end,
	["each spawn sits behind its own HQ, about as far out as the old HQ points (~225 studs)"] = function()
		for side, i in { West = 1, East = #sectors } do
			local r, hq = Map.spawnZones[side], sectors[i]
			local d = dist({ x = (r.minX + r.maxX) / 2, z = (r.minZ + r.maxZ) / 2 }, hq)
			assert(d > 180 and d < 270, `{side} spawn {d} from its HQ`)
			local behind = if side == "West" then r.maxX < hq.x - hq.radius else r.minX > hq.x + hq.radius
			assert(behind, `{side} spawn isn't behind its HQ`)
		end
	end,
	["map fits the fog: you cannot see HQ to HQ"] = function()
		assert(dist(sectors[1], sectors[#sectors]) > Map.fogEnd, "map too small for its fog")
	end,
}
