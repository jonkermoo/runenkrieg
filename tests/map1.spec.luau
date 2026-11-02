--!strict
-- Layout invariants for Map 1 against the metrics contract.
local Front = require("../src/shared/Config/Frontline")
local M = require("../src/shared/Config/Metrics")
local Map1 = require("../src/shared/Config/Maps/Map1")
local MT = require("../src/shared/Rules/MapTerrain")
local R = require("../src/shared/Rules/Frontline")
local Sec = require("../src/shared/Rules/Sectors")
local SecCfg = require("../src/shared/Config/Sectors")

local sectors = Map1.sectors

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
		local r = Map1.spawnZones[side]
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
	local ya, yb = MT.heightAt(Map1, a[1], a[2]) + ah, MT.heightAt(Map1, b[1], b[2]) + bh
	local d = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
	for t = 2, d - 2, 2 do
		local k = t / d
		if MT.heightAt(Map1, a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k) > ya + (yb - ya) * k then
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
	["every wave line slot stays in its own sector and out of the river, however many rows (user 2026-11-02)"] = function()
		local rows = Front.Line.tries // Front.Line.perRow
		for i = 2, #sectors - 1 do
			for _, side in { "West", "East" } do
				for _, p in waveLine(side, i, rows) do
					local id = Sec.sectorAt(Map1, MT, p[1], p[2], SecCfg.Divider.RiverSegments)
					assert(id == sectors[i].id, `{side}'s line at {sectors[i].id} reaches into {id}`)
					assert(not MT.isRiver(Map1, p[1], p[2]), `{side}'s line at {sectors[i].id} stands in the river`)
				end
			end
		end
	end,
	["points on rises: the same crest everywhere, the zone's edge within the zone's height of its point"] = function()
		for _, s in sectors do
			local top = MT.heightAt(Map1, s.x, s.z)
			assert(math.abs(top - Map1.rise.height) < 1, `{s.id}'s crest is {top}`)
			for k = 0, 15 do
				local a = k * math.pi / 8
				local y = MT.heightAt(Map1, s.x + math.cos(a) * s.radius, s.z + math.sin(a) * s.radius)
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
		local b = Map1.bounds
		for _, s in sectors do
			assert(s.x - s.radius >= b.minX and s.x + s.radius <= b.maxX, `{s.id} out of X bounds`)
			assert(s.z - s.radius >= b.minZ and s.z + s.radius <= b.maxZ, `{s.id} out of Z bounds`)
		end
	end,
	["river lies between the S3 and S4 zones"] = function()
		local s3, s4 = sectors[3], sectors[4]
		local r = Map1.river
		local reach = r.width / 2 + r.bankWidth + r.meanderAmp
		assert(s3.x + s3.radius < r.x - reach, "river cuts into S3")
		assert(s4.x - s4.radius > r.x + reach, "river cuts into S4")
	end,
	["river has a vehicle-width ford and infantry alternatives"] = function()
		local wide, narrow = 0, 0
		for _, f in Map1.river.fords do
			assert(f.width > M.Character.Width, "ford too narrow for a soldier")
			if f.width >= 16 then
				wide += 1
			else
				narrow += 1
			end
		end
		assert(wide >= 1 and narrow >= 2, "need 1+ vehicle ford and 2+ infantry fords")
	end,
	["each spawn sits behind its own HQ, ~400 out, still in the HQ's sector (user 2026-11-02)"] = function()
		for side, i in { West = 1, East = #sectors } do
			local r, hq = Map1.spawnZones[side], sectors[i]
			local d = dist({ x = (r.minX + r.maxX) / 2, z = (r.minZ + r.maxZ) / 2 }, hq)
			assert(d > 360 and d < 440, `{side} spawn {d} from its HQ`)
			for _, c in { { r.minX, r.minZ }, { r.maxX, r.minZ }, { r.maxX, r.maxZ }, { r.minX, r.maxZ } } do
				assert(
					Sec.sectorAt(Map1, MT, c[1], c[2], SecCfg.Divider.RiverSegments) == hq.id,
					`{side} spawn leaves {hq.id}`
				)
			end
			local behind = if side == "West" then r.maxX < hq.x - hq.radius else r.minX > hq.x + hq.radius
			assert(behind, `{side} spawn isn't behind its HQ`)
		end
	end,
	["map fits the fog: you cannot see HQ to HQ"] = function()
		assert(dist(sectors[1], sectors[#sectors]) > Map1.fogEnd, "map too small for its fog")
	end,
}
