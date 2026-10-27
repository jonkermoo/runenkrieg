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

function MapTerrain.riverCenterX(map: any, z: number): number
	local r = map.river
	return r.x + r.meanderAmp * math.sin(z / r.meanderLen * 2 * math.pi)
end

function MapTerrain.riverDistance(map: any, x: number, z: number): number
	return math.abs(x - MapTerrain.riverCenterX(map, z))
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
	local h = (relief(map.terrain, s, x, z) + ridgeHeight(map, x)) * edge + wildHeight(map, s, x, z)
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
	local d = MapTerrain.riverDistance(map, x, z)
	local bedHalf = r.width / 2 - 2
	-- Lift low land near the river above the water line so water stays inside the channel.
	local shore = r.waterY + 1.5
	local outer = bedHalf + r.bankWidth
	if land < shore and d < outer + 40 then
		land += (shore - land) * smooth(1 - (d - outer) / 40)
	end
	local bed = r.bedY
	for _, f in r.fords do
		local fz = math.abs(z - f.z)
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
	-- Dirt roads (cheap bounding check first: roads only exist around the village and farm)
	if map.village and x > 880 and x < 1960 and z > -340 and z < 340 then
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
