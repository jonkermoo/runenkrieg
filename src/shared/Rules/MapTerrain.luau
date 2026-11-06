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
-- it, so every point's crest is the same height whatever the noise does there.
local function riseAt(map: any, x: number, z: number): (number, number)
	local r = map.rise
	if not r then
		return 0, 0
	end
	local w = 0
	for _, s in map.sectors do
		local d = math.sqrt((x - s.x) ^ 2 + (z - s.z) ^ 2)
		if d < r.radius then
			w = math.max(w, 1 - smooth((d - r.flat) / (r.radius - r.flat)))
		end
	end
	return w, r.height
end

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

-- Ground height before the river is cut, one side's.
local function landRaw(map: any, x: number, z: number): number
	local s = map.seed * 0.001
	-- Fade the walkable relief to flat at the margin edge so the skirt joins seamlessly.
	local m = map.terrainMargin
	local edge = 1 - smooth((outside(map.bounds, x, z) - m * 0.6) / (m * 0.38))
	local hill, top = riseAt(map, x, z)
	local h = (relief(map.terrain, s, x, z) * (1 - hill) + top * hill + ridgeHeight(map, x)) * edge
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
	elseif slope > 24 then
		return "Ground"
	end
	for _, res in map.reserved do
		if inRect(res, x, z, 0) then
			return "Grass"
		end
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
	if MapTerrain.slopeAt(map, x, z) > T.maxSlope then
		return 0
	end
	local out = outside(b, x, z)
	if out > 0 then
		return if out <= T.edgeBand then T.edgeDensity else T.outerDensity
	end
	local forest = symmetric(map, x, z, function(px, pz)
		return math.noise(px / T.forestScale, pz / T.forestScale, map.seed * 0.001 + 20.7)
	end)
	return if forest > T.groveThreshold then T.groveDensity else T.scatterDensity
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
