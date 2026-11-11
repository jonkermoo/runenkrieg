--!strict
-- Pure terrain + tree generation for maps. Deterministic (math.noise + integer hash), no Instances,
-- so the Studio builder, a future map checker and Lune tests all see the same world.

local MapTerrain = {}

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

local function inRect(r: any, x: number, z: number, pad: number): boolean
	return x >= r.minX - pad and x <= r.maxX + pad and z >= r.minZ - pad and z <= r.maxZ + pad
end

-- Distance outside a rect (0 inside).
local function outside(r: any, x: number, z: number): number
	local dx = math.max(r.minX - x, 0, x - r.maxX)
	local dz = math.max(r.minZ - z, 0, z - r.maxZ)
	return math.sqrt(dx * dx + dz * dz)
end
MapTerrain.outside = outside

local function distToSegment(px: number, pz: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len2 = dx * dx + dz * dz
	local t = if len2 == 0 then 0 else math.clamp(((px - a[1]) * dx + (pz - a[2]) * dz) / len2, 0, 1)
	return math.sqrt((px - a[1] - dx * t) ^ 2 + (pz - a[2] - dz * t) ^ 2)
end

-- 32-bit multiply mod 2^32 without exceeding double precision (split into 16-bit halves).
local function mul32(a: number, b: number): number
	a, b = a % 4294967296, b % 4294967296
	local hi, lo = bit32.rshift(a, 16), bit32.band(a, 0xFFFF)
	return ((hi * b % 65536) * 65536 + lo * b) % 4294967296
end

-- 32-bit integer hash -> [0, 1). Stable across Lune and Roblox.
local function hash01(a: number, b: number, c: number): number
	local h = bit32.bxor(mul32(a, 374761393), mul32(b, 668265263), mul32(c, 2246822519))
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 1274126177)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

-- Fairness on a frontline map: each side's half is the other's twin. Map 1 is point-symmetric through its middle point
-- (the default); a map with `symmetry = "x"` (Lantern Meadows' arch) is mirrored across the middle point's x. The spot
-- twinned with (x, z):
local function twinOf(map: any, x: number, z: number): (number, number)
	local m = map.sectors[math.ceil(#map.sectors / 2)]
	if map.symmetry == "x" then
		return 2 * m.x - x, z
	end
	return 2 * m.x - x, 2 * m.z - z
end
MapTerrain.twinOf = twinOf

-- Distance from a point to the nearest village road edge (negative = on the road) and its id.
function MapTerrain.roadDistance(map: any, x: number, z: number): (number, string?)
	local v = map.village
	local best, id = math.huge, nil
	if not v then
		return best, id
	end
	for _, r in v.roads do
		for i = 1, #r.points - 1 do
			local d = distToSegment(x, z, r.points[i], r.points[i + 1]) - r.width / 2
			if d < best then
				best, id = d, r.id
			end
		end
	end
	return best, id
end

-- the box round every village road (edges included), worked out once per map
local roadBoxes: { [any]: { minX: number, maxX: number, minZ: number, maxZ: number } } = {}
local function roadBox(map: any): { minX: number, maxX: number, minZ: number, maxZ: number }
	local b = roadBoxes[map]
	if not b then
		b = { minX = math.huge, maxX = -math.huge, minZ = math.huge, maxZ = -math.huge }
		for _, r in map.village.roads do
			for _, p in r.points do
				b.minX, b.maxX = math.min(b.minX, p[1] - r.width), math.max(b.maxX, p[1] + r.width)
				b.minZ, b.maxZ = math.min(b.minZ, p[2] - r.width), math.max(b.maxZ, p[2] + r.width)
			end
		end
		roadBoxes[map] = b
	end
	return b
end

-- A straight river's middle line (Map 1: north-south along x, meandering).
function MapTerrain.riverCenterX(map: any, z: number): number
	local r = map.river
	assert(not r.path, "a river with a path has no single x per z: use riverNearest")
	return r.x + r.meanderAmp * math.sin(z / r.meanderLen * 2 * math.pi)
end

-- A river along a path (Config/Maps/LanternMeadows: { x, z } points, bending), each piece's box padded by FAR: a point
-- further than FAR from every piece is just "far" (every use of the distance asks about less than that)
local FAR = 160
local pathBoxes: { [any]: { { number } } } = {}
local function riverPieces(r: any): { { number } }
	local pieces = pathBoxes[r]
	if not pieces then
		pieces = {}
		for i = 1, #r.path - 1 do
			local a, b = r.path[i], r.path[i + 1]
			table.insert(pieces, {
				math.min(a[1], b[1]) - FAR,
				math.max(a[1], b[1]) + FAR,
				math.min(a[2], b[2]) - FAR,
				math.max(a[2], b[2]) + FAR,
				i,
			})
		end
		pathBoxes[r] = pieces
	end
	return pieces
end

-- Distance from (x, z) to the river's middle line and the nearest point on it.
function MapTerrain.riverNearest(map: any, x: number, z: number): (number, number, number)
	local r = map.river
	if not r.path then
		local cx = MapTerrain.riverCenterX(map, z)
		return math.abs(x - cx), cx, z
	end
	local best, bx, bz = math.huge, x, z
	for _, p in riverPieces(r) do
		if x >= p[1] and x <= p[2] and z >= p[3] and z <= p[4] then
			local a, b = r.path[p[5]], r.path[p[5] + 1]
			local dx, dz = b[1] - a[1], b[2] - a[2]
			local len2 = dx * dx + dz * dz
			local t = if len2 == 0 then 0 else math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / len2, 0, 1)
			local qx, qz = a[1] + dx * t, a[2] + dz * t
			local d = math.sqrt((x - qx) ^ 2 + (z - qz) ^ 2)
			if d < best then
				best, bx, bz = d, qx, qz
			end
		end
	end
	return best, bx, bz
end

function MapTerrain.riverDistance(map: any, x: number, z: number): number
	return (MapTerrain.riverNearest(map, x, z))
end

-- Where the straight line from (ax, az) to (bx, bz) runs through the river's water (its middle line within half its
-- `width` plus `pad` studs), looked at every `step` studs: the first and last share of the way (0..1) in the water,
-- nil when it stays dry or the map has no river. A bot squad's gathering place across the water from its own side is
-- no gathering place (user 2026-11-06 play test, Lantern Meadows 50 v 50: "everyone breaks at sector 4"; each
-- offensive over the Aurel gathered on the far bank, under the defenders' guns, and none got there).
function MapTerrain.wetSpan(
	map: any,
	ax: number,
	az: number,
	bx: number,
	bz: number,
	step: number,
	pad: number
): (number?, number?)
	local r = map.river
	if not r then
		return nil, nil
	end
	local half = r.width / 2 + pad
	local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
	local n = math.max(1, math.ceil(len / step))
	local first, last = nil, nil
	for k = 0, n do
		local t = k / n
		if MapTerrain.riverDistance(map, ax + (bx - ax) * t, az + (bz - az) * t) <= half then
			first = first or t
			last = t
		end
	end
	return first, last
end

-- A bridge over the river (a map's `river.bridges`): its west (or south) end and the unit way across, square to the
-- river where its centre (b.x, b.z) stands on the river's line.
export type BridgeFrame = { ax: number, az: number, ux: number, uz: number, length: number }

function MapTerrain.bridgeFrame(map: any, b: any): BridgeFrame
	-- the way across: from the river's line out to a probe east of the centre
	local _, qx, qz = MapTerrain.riverNearest(map, b.x + 20, b.z)
	local ux, uz = b.x + 20 - qx, b.z - qz
	local l = math.sqrt(ux * ux + uz * uz)
	ux, uz = ux / l, uz / l
	return { ax = b.x - ux * b.length / 2, az = b.z - uz * b.length / 2, ux = ux, uz = uz, length = b.length }
end

-- A walkable bridge's deck top at `s` studs from its west end: a straight line from the ground at one end to the
-- ground at the other, raised `b.hump` in the middle (a footbridge's gentle arch).
function MapTerrain.deckHeight(map: any, b: any, f: BridgeFrame, s: number): number
	local ya = MapTerrain.heightAt(map, f.ax, f.az)
	local yb = MapTerrain.heightAt(map, f.ax + f.ux * f.length, f.az + f.uz * f.length)
	local t = math.clamp(s / f.length, 0, 1)
	return ya + (yb - ya) * t + (b.hump or 0) * math.sin(math.pi * t)
end

-- Where (x, z) is on a bridge's deck: its distance along from the west end and to the side of the middle line.
function MapTerrain.onBridge(f: BridgeFrame, x: number, z: number): (number, number)
	local dx, dz = x - f.ax, z - f.az
	return dx * f.ux + dz * f.uz, dz * f.ux - dx * f.uz
end

local function ridgeHeight(map: any, x: number): number
	local r = map.ridge
	if not r or x <= r.upStart or x >= r.downEnd then
		return 0
	elseif x < r.topStart then
		return r.height * smooth((x - r.upStart) / (r.topStart - r.upStart))
	elseif x <= r.topEnd then
		return r.height
	end
	return r.height * (1 - smooth((x - r.topEnd) / (r.downEnd - r.topEnd)))
end

-- A map with `rise` (Config/Maps/Map1.rise): each sector's point on a round hill. Returns how much of the ground is the
-- hill (1 out to `flat` from a point, 0 from `radius` out; the most where two meet) and the hill's top: the rolling ground blends into
-- it, so every point's crest is the same height whatever the noise does there. A map with the leg pattern (`legs`)
-- keeps a rise at its two HQs only, if it gives one (`legs.hqRise`: radius, height, flat).
local function riseAt(map: any, x: number, z: number): (number, number)
	local r = map.rise or (map.legs and map.legs.hqRise)
	if not r then
		return 0, 0
	end
	local hqOnly = map.legs ~= nil
	local w = 0
	for _, s in map.sectors do
		local d = math.sqrt((x - s.x) ^ 2 + (z - s.z) ^ 2)
		if d < r.radius and (s.isHQ or not hqOnly) then
			w = math.max(w, 1 - smooth((d - r.flat) / (r.radius - r.flat)))
		end
	end
	return w, r.height
end

--------------------------------------------------------------------------------------------------------------------
-- The leg pattern (map rework, user approved 2026-11-06; docs/maps/MAP_RULES.md): a map with `legs` builds every
-- stretch between two neighbouring points the same way, from its sectors alone. `u` is studs along a leg out from a
-- point, `n` studs across it (to the left of the way out). See the map's `legs` table for each piece's numbers.
--------------------------------------------------------------------------------------------------------------------

export type Crest = { sector: number, side: string, cx: number, cz: number, dx: number, dz: number }
export type Knoll = { sector: number, side: string, x: number, z: number }
export type Pad = { sector: number, side: string, x: number, z: number, kind: string }
export type Legs = {
	crests: { Crest },
	folds: { Crest }, -- side: who attacks from it
	knolls: { Knoll },
	pads: { Pad },
	chain: { { number } },
	rallies: { { x: number, z: number } },
}

local function unitTo(ax: number, az: number, bx: number, bz: number): (number, number)
	local dx, dz = bx - ax, bz - az
	local l = math.sqrt(dx * dx + dz * dz)
	return dx / l, dz / l
end

-- the way from sector `i` toward its neighbour on `side`'s enemy end (West's enemy is east: i + 1), or nil at that end
function MapTerrain.legWay(map: any, i: number, side: string): (number?, number?)
	local s = map.sectors[i]
	local o = map.sectors[if side == "West" then i + 1 else i - 1]
	if not o then
		return nil, nil
	end
	return unitTo(s.x, s.z, o.x, o.z)
end

-- a spot `u` out along (dx, dz) from (x, z) and `n` to its left
local function outAlong(x: number, z: number, dx: number, dz: number, u: number, n: number): (number, number)
	return x + dx * u - dz * n, z + dz * u + dx * n
end
MapTerrain.along = outAlong

local legPieces: { [any]: Legs } = {}
function MapTerrain.legPieces(map: any): Legs
	local L = legPieces[map]
	if L then
		return L
	end
	local C = map.legs
	L = { crests = {}, folds = {}, knolls = {}, pads = {}, chain = {}, rallies = {} }
	local spawnW, spawnE = map.spawnZones.West, map.spawnZones.East
	table.insert(L.chain, { (spawnW.minX + spawnW.maxX) / 2, (spawnW.minZ + spawnW.maxZ) / 2 })
	for i, s in map.sectors do
		table.insert(L.chain, { s.x, s.z })
		-- each approach: the crest and the knolls of the side whose defence faces it, its gun pads behind the point, and
		-- the fold the enemy attacks this point from
		for _, side in { "West", "East" } do
			local dx, dz = MapTerrain.legWay(map, i, side)
			if dx and dz then
				local enemy = if side == "West" then "East" else "West"
				-- (a town sector, `crest = false`, has none: its outer houses are its defence line, and a house can't stand
				-- on a crest's slope)
				if s.crest ~= false then
					local cx, cz = outAlong(s.x, s.z, dx, dz, C.crest.u, 0)
					table.insert(L.crests, { sector = i, side = side, cx = cx, cz = cz, dx = dx, dz = dz })
				end
				local fx, fz = outAlong(s.x, s.z, dx, dz, C.fold.u, 0)
				table.insert(L.folds, { sector = i, side = enemy, cx = fx, cz = fz, dx = dx, dz = dz })
				for _, sgn in { -1, 1 } do
					local kx, kz = outAlong(s.x, s.z, dx, dz, C.knoll.u, sgn * C.knoll.n)
					table.insert(L.knolls, { sector = i, side = side, x = kx, z = kz })
					local gx, gz = outAlong(s.x, s.z, dx, dz, -C.guns.u, sgn * C.guns.n)
					table.insert(L.pads, { sector = i, side = side, x = gx, z = gz, kind = "FieldGun" })
				end
				local hx, hz = outAlong(s.x, s.z, dx, dz, -C.guns.howitzer, 0)
				table.insert(L.pads, { sector = i, side = side, x = hx, z = hz, kind = "Howitzer" })
				local rx, rz = outAlong(s.x, s.z, dx, dz, s.rally or C.rally, 0)
				table.insert(L.rallies, { x = rx, z = rz })
			end
		end
	end
	table.insert(L.chain, { (spawnE.minX + spawnE.maxX) / 2, (spawnE.minZ + spawnE.maxZ) / 2 })
	legPieces[map] = L
	return L
end

-- Where `side` spawns while sector `i` is its front sector and no attack is building there: `legs.rally` out from the
-- point toward the enemy (the sector's own `rally` where it has one: a strongpoint's buildings fill the ground nearer
-- in), behind that approach's crest; and the way it faces. Nil at the enemy's end of the chain.
function MapTerrain.rally(map: any, i: number, side: string): (number?, number?, number?, number?)
	local dx, dz = MapTerrain.legWay(map, i, side)
	if not dx or not dz then
		return nil, nil, nil, nil
	end
	local s = map.sectors[i]
	local x, z = outAlong(s.x, s.z, dx, dz, s.rally or map.legs.rally, 0)
	return x, z, dx, dz
end

-- a bearing in degrees (0 = +z, 90 = +x) of the way (dx, dz)
local function bearing(dx: number, dz: number): number
	return math.round(math.deg(math.atan2(dx, dz)) % 360)
end

-- The bots' marked spots per sector (the bot-tactics session's format, its BOT_TACTICS.md): from the leg pattern, by
-- sector index: `cover` (n soldiers), `support`, `mg`, `guns` (kind FieldGun / Howitzer), `gather` and `trench` runs
-- (ax, az, bx, bz, kind "Fire"). `side` on a spot is the side it serves (none: either); `face` a bearing. A map's own
-- `tactics[i]` lists are added to these. Nothing within `legs.flagClear` of a flag.
function MapTerrain.tactics(map: any): { [number]: any }
	local C = map.legs
	local out = {}
	for i, s in map.sectors do
		local t = { cover = {}, support = {}, mg = {}, guns = {}, gather = {}, trench = {} }
		local P = C.spots
		-- the zone's own few spots: one squad keeps it held from its edge
		for k = 0, 3 do
			local a = math.rad(P.zone.angle + 90 * k)
			local r = math.max(C.flagClear + P.zone.clear, s.radius - P.zone.inset)
			table.insert(t.cover, { x = s.x + r * math.cos(a), z = s.z + r * math.sin(a), n = 2 })
		end
		for _, side in { "West", "East" } do
			local dx, dz = MapTerrain.legWay(map, i, side)
			if dx and dz then
				local face = bearing(dx, dz)
				local enemy = if side == "West" then "East" else "West"
				local u = C.crest.u
				-- (a town, `crest = false`, has no crest spots or trench runs: its houses are the line, for the bots to
				-- score themselves or the map to list in its own `tactics`)
				local crest = s.crest ~= false
				for _, n in if crest then P.crestCover.across else {} do
					local x, z = outAlong(s.x, s.z, dx, dz, u - P.crestCover.back, n)
					table.insert(t.cover, { x = x, z = z, face = face, n = 4, side = side })
				end
				for _, n in if crest then P.crestSupport.across else {} do
					local x, z = outAlong(s.x, s.z, dx, dz, u - P.crestSupport.back, n)
					table.insert(t.support, { x = x, z = z, face = face, side = side })
				end
				for _, sgn in { -1, 1 } do
					local kx, kz = outAlong(s.x, s.z, dx, dz, C.knoll.u, sgn * C.knoll.n)
					-- raking across the crest's front: out and in toward the leg's line
					local k = P.rake
					local rx, rz = dx * k + dz * sgn * k, dz * k - dx * sgn * k
					table.insert(t.mg, { x = kx, z = kz, face = bearing(rx, rz), side = side })
					local gx, gz = outAlong(s.x, s.z, dx, dz, -C.guns.u, sgn * C.guns.n)
					table.insert(t.guns, { x = gx, z = gz, side = side, kind = "FieldGun" })
				end
				local mx, mz = outAlong(s.x, s.z, dx, dz, -math.max(C.flagClear + P.zoneMg, s.radius), 0)
				table.insert(t.mg, { x = mx, z = mz, face = face, side = side })
				local hx, hz = outAlong(s.x, s.z, dx, dz, -C.guns.howitzer, 0)
				table.insert(t.guns, { x = hx, z = hz, side = side, kind = "Howitzer" })
				for _, run in if crest then P.trench.runs else {} do
					local ax, az = outAlong(s.x, s.z, dx, dz, u - P.trench.back, run[1])
					local bx, bz = outAlong(s.x, s.z, dx, dz, u - P.trench.back, run[2])
					table.insert(t.trench, { ax = ax, az = az, bx = bx, bz = bz, kind = "Fire", side = side })
				end
				-- the enemy's attack on this point forms up in the fold on this approach, facing the point
				local f = C.fold
				for _, n in P.gather.across do
					local x, z = outAlong(s.x, s.z, dx, dz, f.u + P.gather.out, n)
					table.insert(t.gather, { x = x, z = z, face = bearing(-dx, -dz), side = enemy })
				end
				for _, sgn in { -1, 1 } do
					local x, z = outAlong(s.x, s.z, dx, dz, f.u + P.laneEnds.out, sgn * (f.half + P.laneEnds.past))
					table.insert(t.support, { x = x, z = z, face = bearing(-dx, -dz), side = enemy })
				end
			end
		end
		local own = map.tactics and map.tactics[i]
		if own then
			for kind, list in own do
				for _, spot in list do
					table.insert(t[kind], spot)
				end
			end
		end
		out[i] = t
	end
	return out
end

-- The wave lines' places for Rules/Frontline.lineQuads on a map with the leg pattern (its rallies), else nil
function MapTerrain.rallyOf(map: any): ((number, string) -> (number?, number?, number?, number?))?
	if not map.legs then
		return nil
	end
	return function(i: number, side: string)
		return MapTerrain.rally(map, i, side)
	end
end

-- (a, b): (x, z) in a piece's frame: studs out along its way and across it
local function frame(p: Crest, x: number, z: number): (number, number)
	local rx, rz = x - p.cx, z - p.cz
	return rx * p.dx + rz * p.dz, rz * p.dx - rx * p.dz
end

-- 1 inside `half`, falling to 0 over `taper` past it
local function ends(b: number, half: number, taper: number): number
	return 1 - smooth((math.abs(b) - half) / taper)
end

-- How far (x, z) is from the chain of points (spawn to spawn through every point) on a map with the leg pattern
function MapTerrain.chainDistance(map: any, x: number, z: number): number
	local L = MapTerrain.legPieces(map)
	local near = math.huge
	for i = 1, #L.chain - 1 do
		near = math.min(near, distToSegment(x, z, L.chain[i], L.chain[i + 1]))
	end
	return near
end

-- A row of overlapping hillocks along a piece's frame (a across it, b along it, -half..half), each its own size, height
-- and place from the hash of `key` (user 2026-11-10: "still too obviously placed (the hills)... make it just a overall
-- uneven terrain"): `lumps.count` of them, `radius` and `height` (x the piece's height) ranges, `shift` across, longer
-- along it by `stretch`. Those within `core` of the middle are never lower than the piece's height.
local function hillocks(L: any, a: number, b: number, half: number, height: number, key: number, seed: number): number
	local best = 0
	for j = 1, L.count do
		local t = if L.count == 1 then 0 else (j - 1) / (L.count - 1) * 2 - 1
		local function r(o: number): number
			return hash01(key, j, seed + o)
		end
		local bj = t * half + (r(1) - 0.5) * half / L.count
		-- (`forward`: only out toward the enemy, never onto the back slope where a wave waits)
		local aj = if L.forward then r(2) * L.shift else (r(2) - 0.5) * 2 * L.shift
		local rad = L.radius[1] + (L.radius[2] - L.radius[1]) * r(3)
		local hk = L.height[1] + (L.height[2] - L.height[1]) * r(4)
		if math.abs(bj) < L.core then
			hk = math.max(hk, 1)
		end
		local da, db = (a - aj) / (rad * (L.across or 1)), (b - bj) / (rad * L.stretch)
		local d2 = da * da + db * db
		if d2 < 1 then
			best = math.max(best, height * hk * (0.5 + 0.5 * math.cos(math.pi * math.sqrt(d2))))
		end
	end
	return best
end

-- The broad swells across the middle of each leg (`legs.swell`): dead ground both ways, and they hide the point beyond
-- the next one (user 2026-11-10: "not every sector visible. the meadow map is so flat you can see everything"). Each
-- is the frame of its leg at `at` of the way along it; a leg and its twin through the middle point (leg k and
-- #sectors - k) share one shape: the twin reads its frame backwards (`flip`).
type Swell = { cx: number, cz: number, dx: number, dz: number, key: number, flip: boolean }
local swellsOf: { [any]: { Swell } } = {}
local function swells(map: any): { Swell }
	local out = swellsOf[map]
	if out then
		return out
	end
	out = {}
	local S, W = map.sectors, map.legs.swell
	for k = 1, #S - 1 do
		local a, b = S[k], S[k + 1]
		local dx, dz = unitTo(a.x, a.z, b.x, b.z)
		local twin = #S - k
		table.insert(out, {
			cx = a.x + (b.x - a.x) * W.at,
			cz = a.z + (b.z - a.z) * W.at,
			dx = dx,
			dz = dz,
			key = math.min(k, twin),
			flip = k > twin,
		})
	end
	swellsOf[map] = out
	return out
end

-- How the leg pattern lifts (crests, knolls) and cuts (sunken lanes) the ground at (x, z), and how much of the rolling
-- ground's relief stays there (the open ground is kept calm, the gun pads level).
local function legsAt(map: any, x: number, z: number): (number, number)
	local C = map.legs
	local L = MapTerrain.legPieces(map)
	local up, down = 0, 0
	local cr, kn, fo = C.crest, C.knoll, C.fold
	local W = C.swell
	if W then
		for _, sw in swells(map) do
			local a, b = frame(sw :: any, x, z)
			if sw.flip then
				-- (the twin's frame runs backwards: through a point both ways flip, across an x only along it)
				a, b = -a, if map.symmetry == "x" then b else -b
			end
			if math.abs(a) < W.width and math.abs(b) < W.half + W.taper then
				local v = hillocks(W.lumps, a, b, W.half, W.height, 100 + sw.key, map.seed) * ends(b, W.half, W.taper)
				-- (down to nothing by a river: its banks and bridges stay as they are)
				if v > 0 and map.river then
					v *= smooth((MapTerrain.riverDistance(map, x, z) - W.riverClear) / W.riverFade)
				end
				up = math.max(up, v)
			end
		end
	end
	for _, c in L.crests do
		local a, b = frame(c, x, z)
		-- a natural rise (`crest.bend`: user 2026-11-10, "just make it natural looking rises"): its line wanders toward
		-- and away from the point, its height and its two ends vary, all along it (b) from noise; none of it at its
		-- middle (b = 0), so the rise over the point and the open ground stays `height`. Keyed so that a crest and its
		-- twin through the middle point (West's at i, East's at #sectors + 1 - i) get the same shape: fair cover.
		local half, lift = cr.half, 1
		if cr.bend then
			local key = (if c.side == "West" then c.sector else #map.sectors + 1 - c.sector) * 7.31
			local seed = map.seed * 0.001
			local function wob(v: number, o: number): number
				return math.noise(v / cr.bendScale, key + o, seed) - math.noise(0, key + o, seed)
			end
			a -= cr.bend * wob(b, 0.5)
			lift = 1 + cr.vary * math.abs(wob(b, 3.7)) -- (only ever higher: the rise still hides the spawns behind it)
			half *= 1 + cr.reach * math.noise(if b < 0 then 1.7 else 4.3, key, seed)
		end
		-- a lumpy rise (`crest.lumps`, user 2026-11-10: "still too obviously placed"): the long bell kept whole only round
		-- its middle (`core`, where it hides the rally), down to `base` of it further out, and a row of hillocks over it
		local baseK = 1
		local Lu = cr.lumps
		if Lu then
			baseK = Lu.base + (1 - Lu.base) * (1 - smooth((math.abs(b) - Lu.core) / Lu.fade))
			if math.abs(a) < Lu.shift + Lu.radius[2] and math.abs(b) < half + cr.taper then
				local ki = if c.side == "West" then c.sector else #map.sectors + 1 - c.sector
				-- (an x-mirrored map's twin crest runs the other way along: b mirrored)
				local lb = if map.symmetry == "x" and c.side == "East" then -b else b
				-- (placed along the crest's own `half`: the varied one jumps at its middle, b = 0)
				up = math.max(up, hillocks(Lu, a, lb, cr.half, cr.height, ki, map.seed) * ends(b, half, cr.taper))
			end
		end
		if math.abs(a) < cr.width / 2 and math.abs(b) < half + cr.taper then
			local bell = 0.5 + 0.5 * math.cos(math.pi * a / (cr.width / 2))
			up = math.max(up, cr.height * lift * baseK * bell * ends(b, half, cr.taper))
		end
	end
	for _, k in L.knolls do
		local d = math.sqrt((x - k.x) ^ 2 + (z - k.z) ^ 2)
		if d < kn.radius then
			up = math.max(up, kn.height * (1 - smooth((d - kn.top / 2) / (kn.radius - kn.top / 2))))
		end
	end
	for _, f in L.folds do
		local a, b = frame(f, x, z)
		local reach = fo.floor / 2 + fo.wall
		if math.abs(a) < reach and math.abs(b) < fo.half then
			local across = 1 - smooth((math.abs(a) - fo.floor / 2) / fo.wall)
			local lengthwise = math.clamp((fo.half - math.abs(b)) / fo.ends, 0, 1)
			down = math.min(down, -fo.depth * across * smooth(lengthwise))
		end
	end
	-- the relief kept: `calm.keep` near the chain, all of it from `calm.width + calm.fade` out; none on a gun pad
	local cm = C.calm
	local near = MapTerrain.chainDistance(map, x, z)
	local keep = cm.keep + (1 - cm.keep) * smooth((near - cm.width) / cm.fade)
	local g = C.guns
	for _, p in L.pads do
		local d = math.sqrt((x - p.x) ^ 2 + (z - p.z) ^ 2)
		if d < g.pad / 2 + g.fade then
			keep = math.min(keep, keep * smooth((d - g.pad / 2) / g.fade))
		end
	end
	-- calm round every rally (`legs.rallyCalm`): the rolling ground can't lift a waiting wave over its own crest
	local rc = C.rallyCalm
	if rc then
		for _, r in L.rallies do
			local d = math.sqrt((x - r.x) ^ 2 + (z - r.z) ^ 2)
			if d < rc.radius + rc.fade then
				keep = math.min(keep, keep * smooth((d - rc.radius) / rc.fade))
			end
		end
	end
	return up + down, keep
end

MapTerrain.legShape = legsAt

-- 0 = fully flattened (inside a reserved area), 1 = natural terrain.
function MapTerrain.flattenWeight(map: any, x: number, z: number): (number, number)
	local w, baseY = 1, 0
	for _, r in map.reserved do
		if r.baseY ~= nil then
			local d = outside(r, x, z)
			local k = smooth(d / r.falloff)
			if k < w then
				w, baseY = k, r.baseY
			end
		end
	end
	return w, baseY
end

-- Gentle, walkable unevenness: swells, bumps and occasional mounds.
local function relief(t: any, s: number, x: number, z: number): number
	local n = t.baseAmp * math.noise(x / t.baseScale, z / t.baseScale, s)
		+ t.midAmp * math.noise(x / t.midScale, z / t.midScale, s + 10.5)
		+ t.detailAmp * math.noise(x / t.detailScale, z / t.detailScale, s + 21.3)
		+ t.bumpAmp * math.noise(x / t.bumpScale, z / t.bumpScale, s + 32.9)
	local mound = math.max(0, math.noise(x / t.moundScale, z / t.moundScale, s + 44.1) - t.moundThreshold)
	return n + t.moundAmp * mound * mound / ((1 - t.moundThreshold) ^ 2)
end

-- Ridged hills outside the bounds: rise after `start`, peak, then fall back to flat at the margin edge.
local function wildHeight(map: any, s: number, x: number, z: number): number
	local w = map.wild
	if not w then
		return 0
	end
	local out = outside(map.bounds, x, z)
	if out <= w.start then
		return 0
	end
	local m = map.terrainMargin
	local k = smooth((out - w.start) / w.ramp) * (1 - smooth((out - (m - w.fall)) / w.fall))
	if k <= 0 then
		return 0
	end
	local ridged = 1 - math.abs(math.noise(x / w.scale, z / w.scale, s + 60.7))
	local rough = math.noise(x / w.roughScale, z / w.roughScale, s + 71.3)
	return k * (w.amp * ridged * ridged + w.roughAmp * rough)
end

-- A map with `mirror` (its centre) is point-symmetric: a value is the average of its own and its mirror point's, so the
-- two sides match and the seam through the centre stays smooth.
local function symmetric(map: any, x: number, z: number, f: (number, number) -> number): number
	local m = map.mirror
	if not m then
		return f(x, z)
	end
	return (f(x, z) + f(2 * m.x - x, 2 * m.z - z)) / 2
end

-- The valley (`ground.valley`, user 2026-11-10: "make it just a overall uneven terrain, with this area more
-- unelevated (does not have to be a perfect line, make it natural)"): the way between the points stays low, the
-- ground lifts `lift` toward the flanks between `near` and `far` from the chain, the edge wandering `edge` either way
-- from noise (the same at a point and its mirror through the middle point: fair); returns the lift and how far into
-- the flank (0..1), where the rolling ground grows `rough` times rougher.
local function valleyAt(map: any, s: number, x: number, z: number): (number, number)
	local V = map.ground and map.ground.valley
	if not V or not map.legs then
		return 0, 0
	end
	local function wob(px: number, pz: number): number
		return math.noise(px / V.edgeScale, pz / V.edgeScale, s + 83.9)
	end
	local tx, tz = twinOf(map, x, z)
	local d = MapTerrain.chainDistance(map, x, z) + V.edge * (wob(x, z) + wob(tx, tz))
	local w = smooth((d - V.near) / (V.far - V.near))
	return V.lift * w, w
end

-- The rolling ground's coordinates bent by low noise (`ground.warp`: amp, scale), so its swells and hollows wander
-- instead of lying in rows (domain warping, iquilezles.org/articles/warp)
local function warped(map: any, s: number, x: number, z: number): (number, number)
	local W = map.ground and map.ground.warp
	if not W then
		return x, z
	end
	return x + W.amp * math.noise(x / W.scale, z / W.scale, s + 91.7),
		z + W.amp * math.noise(x / W.scale, z / W.scale, s + 97.3)
end

-- Ground height before the river is cut, one side's.
local function landRaw(map: any, x: number, z: number): number
	local s = map.seed * 0.001
	-- Fade the walkable relief to flat at the margin edge so the skirt joins seamlessly.
	local m = map.terrainMargin
	local edge = 1 - smooth((outside(map.bounds, x, z) - m * 0.6) / (m * 0.38))
	local hill, top = riseAt(map, x, z)
	local shape, keep = 0, 1
	if map.legs then
		shape, keep = legsAt(map, x, z)
	end
	-- settled ground round each landmark (`ground.settle`: its plot level, as built; the rolling ground and the valley
	-- pick up past it), so a strongpoint's blocks stand on one level
	local G = map.ground
	if G and G.settle and map.village then
		for _, sp in map.village.specials or {} do
			local d = math.sqrt((x - sp.x) ^ 2 + (z - sp.z) ^ 2)
			if d < G.settle.radius + G.settle.fade then
				keep *= G.settle.floor + (1 - G.settle.floor) * smooth((d - G.settle.radius) / G.settle.fade)
			end
		end
	end
	local lift, flank = valleyAt(map, s, x, z)
	local rough = 1 + ((map.ground and map.ground.valley and map.ground.valley.rough or 1) - 1) * flank
	local wx, wz = warped(map, s, x, z)
	local h = (
		(relief(map.terrain, s, wx, wz) * keep * rough + lift) * (1 - hill)
		+ top * hill
		+ ridgeHeight(map, x)
		+ shape
	)
			* edge
		+ wildHeight(map, s, x, z)
	local w, baseY = MapTerrain.flattenWeight(map, x, z)
	return baseY + (h - baseY) * w
end

local function landHeight(map: any, x: number, z: number): number
	return symmetric(map, x, z, function(px, pz)
		return landRaw(map, px, pz)
	end)
end

-- Final terrain surface height at (x, z).
function MapTerrain.heightAt(map: any, x: number, z: number): number
	local land = landHeight(map, x, z)
	local r = map.river
	if not r then
		return land
	end
	local d, qx, qz = MapTerrain.riverNearest(map, x, z)
	local bedHalf = r.width / 2 - 2
	-- Lift low land near the river above the water line so water stays inside the channel.
	local shore = r.waterY + 1.5
	local outer = bedHalf + r.bankWidth
	if land < shore and d < outer + 40 then
		land += (shore - land) * smooth(1 - (d - outer) / 40)
	end
	local bed = r.bedY
	for _, f in r.fords do
		-- how far along the river from the ford (a straight river's ford is a z; a path river's a point on it)
		local fz = math.sqrt((qx - (f.x or qx)) ^ 2 + (qz - f.z) ^ 2)
		if fz < f.width / 2 + 6 then
			bed = math.max(bed, f.bedY - (f.bedY - r.bedY) * smooth((fz - f.width / 2) / 6))
		end
	end
	if d <= bedHalf then
		return math.min(land, bed)
	elseif d <= bedHalf + r.bankWidth then
		local k = smooth((d - bedHalf) / r.bankWidth)
		return math.min(land, bed + (land - bed) * k)
	end
	return land
end

-- How much lower the terrain voxels lay a ford with `sink` than heightAt (0 elsewhere): the voxel writer
-- (Greybox/Ground) lays ground about 2 studs over heightAt, which leaves a shallow ford's bed over the water line, a dry
-- bar; a ford that should show its water sinks its voxels so they sit at its bed. Full across the bed and along the
-- ford, fading over the banks and the ford's ends the way the ford's own bed does.
function MapTerrain.fordSink(map: any, x: number, z: number): number
	local r = map.river
	if not r then
		return 0
	end
	local d, qx, qz = MapTerrain.riverNearest(map, x, z)
	local bedHalf = r.width / 2 - 2
	if d > bedHalf + r.bankWidth then
		return 0
	end
	local across = if d <= bedHalf then 1 else 1 - smooth((d - bedHalf) / r.bankWidth)
	local sink = 0
	for _, f in r.fords do
		if f.sink then
			local fz = math.sqrt((qx - (f.x or qx)) ^ 2 + (qz - f.z) ^ 2)
			local along = if fz <= f.width / 2 then 1 else 1 - smooth((fz - f.width / 2) / 6)
			sink = math.max(sink, f.sink * across * math.max(along, 0))
		end
	end
	return sink
end

-- Slope in degrees by central differences.
function MapTerrain.slopeAt(map: any, x: number, z: number): number
	local e = 2
	local hx = (MapTerrain.heightAt(map, x + e, z) - MapTerrain.heightAt(map, x - e, z)) / (2 * e)
	local hz = (MapTerrain.heightAt(map, x, z + e) - MapTerrain.heightAt(map, x, z - e)) / (2 * e)
	return math.deg(math.atan(math.sqrt(hx * hx + hz * hz)))
end

function MapTerrain.isRiver(map: any, x: number, z: number): boolean
	local r = map.river
	return r ~= nil and MapTerrain.riverDistance(map, x, z) <= r.width / 2 + r.bankWidth
end

--------------------------------------------------------------------------------------------------------------------
-- Fields on the flanks (`map.fields`, user 2026-11-10: "a lot of open space... it can be open, it just cant look
-- empty"): a grid of parcels `size` studs, turned `angle` degrees, laid point-symmetric round the middle point (a
-- parcel and its twin get the same kind, edges and stacks: fair cover). A parcel is a field where all of it is at
-- least `near` from the chain, no more than `beyond` past the bounds, clear of the river and of every point by `pointClear`; each is
-- ploughed (`Plough`: earth in stripes `stripe` wide), hay meadow (`Meadow`, haystacks) or pasture (`Pasture`) by
-- `kinds` shares. Each field edge is a hedge, a rail fence, a stone wall or open by `edges` shares, a gate's gap in its
-- middle. Ref: Historic England farmstead guidance (hedged closes round the farms), docs/maps/ENVIRONMENT_RESEARCH.md.
--------------------------------------------------------------------------------------------------------------------

type FieldGrid = { mx: number, mz: number, c: number, s: number, w: number, h: number }
local function fieldGrid(map: any): FieldGrid
	local F = map.fields
	local m = map.sectors[math.ceil(#map.sectors / 2)]
	local a = math.rad(F.angle)
	return { mx = m.x, mz = m.z, c = math.cos(a), s = math.sin(a), w = F.size[1], h = F.size[2] }
end

-- (u, v) in the grid's frame, and back
local function toGrid(g: FieldGrid, x: number, z: number): (number, number)
	local rx, rz = x - g.mx, z - g.mz
	return rx * g.c + rz * g.s, -rx * g.s + rz * g.c
end
local function fromGrid(g: FieldGrid, u: number, v: number): (number, number)
	return g.mx + u * g.c - v * g.s, g.mz + u * g.s + v * g.c
end

-- a parcel's canonical twin and whether (i, j) is the twin (its spots mirror): through the middle point (i, j) <->
-- (-i - 1, -j - 1); across its x (`symmetry = "x"`, the grid unturned) (i, j) <-> (-i - 1, j)
local function canon(map: any, i: number, j: number): (number, number, boolean)
	if i < 0 then
		return -i - 1, if map.symmetry == "x" then j else -j - 1, true
	end
	return i, j, false
end
-- an edge's canonical twin: the west edge of (i, j) (u = i * w) twins the west edge of (-i, -j - 1) through the point,
-- of (-i, j) across the x; its south edge (v = j * h) the south edge of (-i - 1, -j), or of (-i - 1, j)
local function westEdge(map: any, i: number, j: number): (number, number)
	if map.symmetry == "x" then
		return math.abs(i), j
	end
	return if i < 0 or (i == 0 and j < 0) then -i else i, if i < 0 or (i == 0 and j < 0) then -j - 1 else j
end
local function southEdge(map: any, i: number, j: number): (number, number)
	if map.symmetry == "x" then
		return if i < 0 then -i - 1 else i, j
	end
	return if j < 0 or (j == 0 and i < 0) then -i - 1 else i, if j < 0 or (j == 0 and i < 0) then -j else j
end

local function pick(shares: { [string]: number }, order: { string }, r: number): string?
	local acc = 0
	for _, k in order do
		acc += shares[k] or 0
		if r < acc then
			return k
		end
	end
	return nil
end
local FIELD_KINDS = { "Plough", "Meadow", "Pasture" }
local EDGE_KINDS = { "Hedge", "RailFence", "StoneWall" }

local fieldKinds: { [any]: { [string]: string | false } } = {}
-- the kind of parcel (i, j) ("Plough", "Meadow", "Pasture"), or nil where it's no field
local function parcelKind(map: any, i: number, j: number): string?
	local cache = fieldKinds[map]
	if not cache then
		cache = {}
		fieldKinds[map] = cache
	end
	local id = `{i},{j}`
	local hit = cache[id]
	if hit ~= nil then
		return if hit then hit else nil
	end
	local F = map.fields
	local g = fieldGrid(map)
	local ok = true
	local b, mg = map.bounds, F.beyond
	for _, p in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 }, { 0.5, 0.5 }, { 0.5, 0 }, { 0, 0.5 }, { 1, 0.5 }, { 0.5, 1 } } do
		local x, z = fromGrid(g, (i + p[1]) * g.w, (j + p[2]) * g.h)
		-- (checked at the twin's mirrored spot too, so a parcel and its twin are fields alike)
		local x2, z2 = twinOf(map, x, z)
		for _, q in { { x, z }, { x2, z2 } } do
			if
				MapTerrain.chainDistance(map, q[1], q[2]) < F.near
				or outside(b, q[1], q[2]) > mg
				or MapTerrain.isRiver(map, q[1], q[2])
			then
				ok = false
			end
			for _, s in map.sectors do
				if (q[1] - s.x) ^ 2 + (q[2] - s.z) ^ 2 < (s.radius + F.pointClear) ^ 2 then
					ok = false
				end
			end
			for _, zone in map.spawnZones do
				if inRect(zone, q[1], q[2], F.pointClear) then
					ok = false
				end
			end
		end
	end
	local kind: string? = nil
	if ok then
		local ci, cj = canon(map, i, j)
		kind = pick(F.kinds, FIELD_KINDS, hash01(ci + 5000, cj + 5000, map.seed + 81))
	end
	cache[id] = kind or false
	return kind
end

-- The field kind at (x, z) and whether it's a plough furrow there, or nil off the fields
function MapTerrain.fieldAt(map: any, x: number, z: number): (string?, boolean)
	if not map.fields then
		return nil, false
	end
	local g = fieldGrid(map)
	local u, v = toGrid(g, x, z)
	local kind = parcelKind(map, math.floor(u / g.w), math.floor(v / g.h))
	return kind, kind == "Plough" and math.floor(u / map.fields.stripe) % 2 == 0
end

export type FieldRun = { kind: string, a: { number }, b: { number } }
export type FieldStack = { kind: string, x: number, z: number, yaw: number }
local fieldsOf: { [any]: { runs: { FieldRun }, stacks: { FieldStack } } } = {}

-- Every field's edges (a run each side of its gate) and the meadows' haystacks
function MapTerrain.fieldLayout(map: any): { runs: { FieldRun }, stacks: { FieldStack } }
	local hit = fieldsOf[map]
	if hit then
		return hit
	end
	local out = { runs = {}, stacks = {} }
	fieldsOf[map] = out
	local F = map.fields
	if not F then
		return out
	end
	local g = fieldGrid(map)
	local b, mg = map.bounds, map.terrainMargin
	local u0, v0 = math.huge, math.huge
	local u1, v1 = -math.huge, -math.huge
	for _, p in
		{
			{ b.minX - mg, b.minZ - mg },
			{ b.maxX + mg, b.minZ - mg },
			{ b.minX - mg, b.maxZ + mg },
			{ b.maxX + mg, b.maxZ + mg },
		}
	do
		local u, v = toGrid(g, p[1], p[2])
		u0, v0, u1, v1 = math.min(u0, u), math.min(v0, v), math.max(u1, u), math.max(v1, v)
	end
	local function run(kind: string, ua: number, va: number, ub: number, vb: number)
		local ax, az = fromGrid(g, ua, va)
		local bx, bz = fromGrid(g, ub, vb)
		table.insert(out.runs, { kind = kind, a = { ax, az }, b = { bx, bz } })
	end
	-- an edge along the grid's line from (ua, va) to (ub, vb), split by a gate in its middle
	local function edge(kind: string, ua: number, va: number, ub: number, vb: number)
		local l = math.sqrt((ub - ua) ^ 2 + (vb - va) ^ 2)
		local k = (l - F.gate) / 2 / l
		run(kind, ua, va, ua + (ub - ua) * k, va + (vb - va) * k)
		run(kind, ub - (ub - ua) * k, vb - (vb - va) * k, ub, vb)
	end
	for i = math.floor(u0 / g.w), math.floor(u1 / g.w) do
		for j = math.floor(v0 / g.h), math.floor(v1 / g.h) do
			local here = parcelKind(map, i, j)
			local ci, cj, twin = canon(map, i, j)
			-- its west edge (u = i * w) and south edge (v = j * h), each where a field lies either side; an edge's kind
			-- keyed by the edge and its twin alike
			if here or parcelKind(map, i - 1, j) then
				local ei, ej = westEdge(map, i, j)
				local kind = pick(F.edges, EDGE_KINDS, hash01(ei + 5000, ej + 5000, map.seed + 82))
				if kind then
					edge(kind, i * g.w, j * g.h, i * g.w, (j + 1) * g.h)
				end
			end
			if here or parcelKind(map, i, j - 1) then
				local ei, ej = southEdge(map, i, j)
				local kind = pick(F.edges, EDGE_KINDS, hash01(ei + 5000, ej + 5000, map.seed + 83))
				if kind then
					edge(kind, i * g.w, j * g.h, (i + 1) * g.w, j * g.h)
				end
			end
			-- a meadow's haystacks, in from its edges (a twin's at the mirrored spots)
			if here == "Meadow" then
				local n = math.floor(hash01(ci + 5000, cj + 5000, map.seed + 84) * (F.stacks.max + 1))
				for k = 1, n do
					local lu = F.stacks.inset
						+ (g.w - 2 * F.stacks.inset) * hash01(ci + 5000, cj + 5000 + k * 97, map.seed + 85)
					local lv = F.stacks.inset
						+ (g.h - 2 * F.stacks.inset) * hash01(ci + 5000, cj + 5000 + k * 97, map.seed + 86)
					local yaw = hash01(ci + 5000, cj + 5000 + k * 97, map.seed + 87) * 360
					if twin then
						if map.symmetry == "x" then
							lu, yaw = g.w - lu, (360 - yaw) % 360
						else
							lu, lv, yaw = g.w - lu, g.h - lv, (yaw + 180) % 360
						end
					end
					local x, z = fromGrid(g, i * g.w + lu, j * g.h + lv)
					table.insert(out.stacks, { kind = "Haystack", x = x, z = z, yaw = yaw })
				end
			end
		end
	end
	return out
end

-- Surface material name (an Enum.Material name) for a column.
function MapTerrain.materialAt(map: any, x: number, z: number): string
	local r = map.river
	if r then
		local d = MapTerrain.riverDistance(map, x, z)
		if d <= r.width / 2 then
			return "Mud"
		elseif d <= r.width / 2 + r.bankWidth then
			return "Ground"
		end
	end
	-- Dirt roads (cheap bounding check first: roads only exist inside their own box)
	local box = map.village and roadBox(map)
	if box and x > box.minX and x < box.maxX and z > box.minZ and z < box.maxZ then
		if MapTerrain.roadDistance(map, x, z) < 0 then
			return "Sand"
		end
	end
	local slope = MapTerrain.slopeAt(map, x, z)
	if slope > 34 then
		return "Rock"
	elseif slope > (map.terrain.dirtSlope or 24) then
		return "Ground"
	end
	for _, res in map.reserved do
		if inRect(res, x, z, 0) then
			return "Grass"
		end
	end
	-- the fields: ploughed earth in furrows, hay meadow, pasture
	local field, furrow = MapTerrain.fieldAt(map, x, z)
	if field == "Plough" then
		return if furrow then "Mud" else "Ground"
	elseif field == "Meadow" then
		return "LeafyGrass"
	elseif field == "Pasture" then
		return "Grass"
	end
	local s = map.seed * 0.001
	local patch = symmetric(map, x, z, function(px, pz)
		return math.noise(px / 60, pz / 60, s + 40.2)
	end)
	if patch > map.terrain.patchThreshold then
		return "Ground"
	end
	local fs = map.trees.forestScale
	local forest = symmetric(map, x, z, function(px, pz)
		return math.noise(px / fs, pz / fs, s + 20.7)
	end)
	if forest > map.trees.groveThreshold then
		return "LeafyGrass"
	end
	return "Grass"
end

MapTerrain.hash01 = hash01

-- Where a trunk should be planted: the lowest ground under its footprint (so it never floats on a
-- slope), sunk a little further so voxel smoothing cannot leave a gap.
function MapTerrain.treeBaseY(map: any, x: number, z: number): number
	local r = map.trees.footprint
	local y = MapTerrain.heightAt(map, x, z)
	for i = 0, 5 do
		local a = i * math.pi / 3
		y = math.min(y, MapTerrain.heightAt(map, x + r * math.cos(a), z + r * math.sin(a)))
	end
	return y - map.trees.sink
end

export type Tree = { x: number, z: number, kind: string, scale: number, yaw: number, variant: number, far: boolean }

-- Clumps of trees (`trees.clumps`, user 2026-11-10: "the minimum tree cluster has too little trees, some are just
-- alone"): instead of lone trees, a clump's centre in some of the `cell`-stud squares (`chance`), each its own radius
-- (most small, a few big: the share raised to `tail`), its ground grown at `density`; at cell 14 a radius of 18 holds
-- about 4 trees, 40 about 20. The same at a point and its mirror through the middle point (fair cover). A neyman-scott
-- cluster process, simplified to discs.
-- the centre of the clump (x, z) stands in, or nil (a twin clump's centre is its twin's, mirrored)
local function clumpCentre(map: any, x: number, z: number): (number?, number?)
	local K = map.trees.clumps
	local function inClump(px: number, pz: number): (number?, number?)
		local gx, gz = math.floor(px / K.cell), math.floor(pz / K.cell)
		for ix = gx - 1, gx + 1 do
			for iz = gz - 1, gz + 1 do
				if hash01(ix, iz, map.seed + 71) < K.chance then
					local cx = (ix + hash01(ix, iz, map.seed + 72)) * K.cell
					local cz = (iz + hash01(ix, iz, map.seed + 73)) * K.cell
					local r = K.radius[1] + (K.radius[2] - K.radius[1]) * hash01(ix, iz, map.seed + 74) ^ K.tail
					if (px - cx) ^ 2 + (pz - cz) ^ 2 < r * r then
						return cx, cz
					end
				end
			end
		end
		return nil, nil
	end
	local cx, cz = inClump(x, z)
	if cx and cz then
		return cx, cz
	end
	local tx, tz = twinOf(map, x, z)
	cx, cz = inClump(tx, tz)
	if cx and cz then
		return twinOf(map, cx, cz)
	end
	return nil, nil
end

local function clumpAt(map: any, x: number, z: number): number
	return if clumpCentre(map, x, z) then map.trees.clumps.density else 0
end

function MapTerrain.treeDensity(map: any, x: number, z: number): number
	local T = map.trees
	local b = map.bounds
	for _, r in map.reserved do
		if inRect(r, x, z, 4) then
			return 0
		end
	end
	if
		map.river
		and MapTerrain.riverDistance(map, x, z) <= map.river.width / 2 + map.river.bankWidth + T.riverClear
	then
		return 0
	end
	for _, zone in map.spawnZones do
		if inRect(zone, x, z, 6) then
			return 0
		end
	end
	for _, s in map.sectors do
		if (x - s.x) ^ 2 + (z - s.z) ^ 2 < (s.radius * T.sectorClearFrac) ^ 2 then
			return 0
		end
	end
	-- the fields are cleared farmland: no trees on them (their hedges stand along the edges)
	if map.fields and MapTerrain.fieldAt(map, x, z) then
		return 0
	end
	if MapTerrain.slopeAt(map, x, z) > T.maxSlope then
		return 0
	end
	-- the leg pattern's open ground: no trees along the chain (user 2026-11-06: "just being able to see an enemy is
	-- considered not safe"); the copses stand out on the flanks
	-- A map with `legs.open` (Map 1; user 2026-11-10: "add more trees and such in the really open field") grows
	-- copses and lone trees there instead, off the way between the points, the knolls, the gun pads and the rallies
	if map.legs and MapTerrain.chainDistance(map, x, z) < map.legs.calm.width then
		local O = map.legs.open
		if not O or MapTerrain.chainDistance(map, x, z) < O.lane then
			return 0
		end
		local L = MapTerrain.legPieces(map)
		for _, k in L.knolls do
			if (x - k.x) ^ 2 + (z - k.z) ^ 2 < O.knollClear ^ 2 then
				return 0
			end
		end
		for _, p in L.pads do
			if (x - p.x) ^ 2 + (z - p.z) ^ 2 < O.padClear ^ 2 then
				return 0
			end
		end
		for i = 1, #map.sectors do
			for _, side in { "West", "East" } do
				local rx, rz = MapTerrain.rally(map, i, side)
				if rx and rz and (x - rx) ^ 2 + (z - rz) ^ 2 < O.rallyClear ^ 2 then
					return 0
				end
			end
		end
		-- the copses point-symmetric through the middle point, like the points (fair cover)
		local seed = map.seed * 0.001 + 61.3
		local tx, tz = twinOf(map, x, z)
		local c = math.max(math.noise(x / O.scale, z / O.scale, seed), math.noise(tx / O.scale, tz / O.scale, seed))
		return if c > O.threshold then O.copse else (if T.clumps then clumpAt(map, x, z) else O.lone)
	end
	local out = outside(b, x, z)
	if out > 0 then
		return if out <= T.edgeBand then T.edgeDensity else T.outerDensity
	end
	local forest = symmetric(map, x, z, function(px, pz)
		return math.noise(px / T.forestScale, pz / T.forestScale, map.seed * 0.001 + 20.7)
	end)
	if forest > T.groveThreshold then
		return T.groveDensity
	end
	return if T.clumps then clumpAt(map, x, z) else T.scatterDensity
end

function MapTerrain.trees(map: any): { Tree }
	local T = map.trees
	local b, m = map.bounds, map.terrainMargin
	local mid = map.mirror
	local out: { Tree } = {}
	local x0 = math.floor((b.minX - m) / T.cell)
	local x1 = math.floor((b.maxX + m) / T.cell)
	local z0 = math.floor((b.minZ - m) / T.cell)
	local z1 = math.floor((b.maxZ + m) / T.cell)
	for cx = x0, x1 do
		for cz = z0, z1 do
			local jx, jz = hash01(cx, cz, 1), hash01(cx, cz, 2)
			local x = (cx + 0.25 + 0.5 * jx) * T.cell
			local z = (cz + 0.25 + 0.5 * jz) * T.cell
			-- a mirrored map grows its West half (x under the centre's) and copies it round the centre (below)
			local half = not mid or (x < mid.x and (x - mid.x) ^ 2 + (z - mid.z) ^ 2 > 4)
			if half and hash01(cx, cz, 3) < MapTerrain.treeDensity(map, x, z) then
				-- a clump's trees drawn in toward its centre (`clumps.pull`), so it stands as one group, not a scatter
				-- the planting grid spaces out; kept where it was if that lands on cleared ground
				local K = T.clumps
				local ccx, ccz = nil, nil
				if K then
					ccx, ccz = clumpCentre(map, x, z)
				end
				if ccx and ccz then
					local px, pz = ccx + (x - ccx) * (1 - K.pull), ccz + (z - ccz) * (1 - K.pull)
					if MapTerrain.treeDensity(map, px, pz) > 0 then
						x, z = px, pz
					end
				end
				local k = hash01(cx, cz, 4)
				local onRidge = ridgeHeight(map, x) > 1
				local pineShare = if onRidge then 0.7 else 0.45
				local kind = if k < pineShare
					then "Pine"
					elseif k < pineShare + (1 - pineShare) * 0.7 then "Broadleaf"
					else "Birch"
				table.insert(out, {
					x = x,
					z = z,
					kind = kind,
					scale = 0.8 + 0.45 * hash01(cx, cz, 5),
					yaw = hash01(cx, cz, 6) * 360,
					variant = math.floor(hash01(cx, cz, 7) * 1000),
					far = outside(b, x, z) > T.edgeBand,
				})
			end
		end
	end
	-- (a clump's drawn-in trees: none closer than the clump spacing to one kept before it)
	if T.clumps then
		local min = T.cell * 0.5 * (1 - T.clumps.pull)
		local grid: { [string]: { Tree } } = {}
		local kept: { Tree } = {}
		for _, t in out do
			local gx, gz = math.floor(t.x / min), math.floor(t.z / min)
			local ok = true
			for ox = -1, 1 do
				for oz = -1, 1 do
					for _, o in grid[`{gx + ox}:{gz + oz}`] or {} do
						ok = ok and (t.x - o.x) ^ 2 + (t.z - o.z) ^ 2 >= min * min
					end
				end
			end
			if ok then
				local k = `{gx}:{gz}`
				grid[k] = grid[k] or {}
				table.insert(grid[k], t)
				table.insert(kept, t)
			end
		end
		out = kept
	end
	if mid then
		for i = 1, #out do
			local t = out[i]
			local copy = table.clone(t)
			copy.x, copy.z, copy.yaw = 2 * mid.x - t.x, 2 * mid.z - t.z, (t.yaw + 180) % 360
			table.insert(out, copy)
		end
	end
	return out
end

return MapTerrain
