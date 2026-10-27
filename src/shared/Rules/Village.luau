--!strict
-- Pure, deterministic village layout: building lots along roads, fences/hedges, poles, signposts,
-- parked cars and garden trees. No Instances; the Studio builder turns this into geometry.

local Village = {}

export type Lot = {
	id: string,
	style: string, -- Config/Buildings.Templates key
	x: number, -- center
	z: number,
	fx: number, -- unit vector the front (door) faces
	fz: number,
	width: number,
	depth: number,
	stories: number,
	storyHeight: number,
	colorSeed: number, -- picks the color scheme for this copy
	road: string?,
	special: boolean,
}

local function pick<T>(list: { T }, u: number): T
	return list[math.floor(u * #list) + 1]
end

-- Corners of a lot's footprint, inflated by `pad`.
function Village.corners(l: Lot, pad: number): { { number } }
	local rx, rz = -l.fz, l.fx -- frontage axis
	local hw, hd = l.width / 2 + pad, l.depth / 2 + pad
	local out = {}
	for _, s in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		table.insert(out, { l.x + rx * hw * s[1] + l.fx * hd * s[2], l.z + rz * hw * s[1] + l.fz * hd * s[2] })
	end
	return out
end

-- Separating-axis test for two convex quads.
local function quadsOverlap(a: { { number } }, b: { { number } }): boolean
	for _, poly in { a, b } do
		for i = 1, 4 do
			local p, q = poly[i], poly[i % 4 + 1]
			local ax, az = -(q[2] - p[2]), q[1] - p[1]
			local amin, amax, bmin, bmax = math.huge, -math.huge, math.huge, -math.huge
			for _, v in a do
				local d = v[1] * ax + v[2] * az
				amin, amax = math.min(amin, d), math.max(amax, d)
			end
			for _, v in b do
				local d = v[1] * ax + v[2] * az
				bmin, bmax = math.min(bmin, d), math.max(bmax, d)
			end
			if amax <= bmin or bmax <= amin then
				return false
			end
		end
	end
	return true
end
Village.quadsOverlap = quadsOverlap

function Village.pointInQuad(x: number, z: number, quad: { { number } }): boolean
	local sign = 0
	for i = 1, 4 do
		local p, q = quad[i], quad[i % 4 + 1]
		local c = (q[1] - p[1]) * (z - p[2]) - (q[2] - p[2]) * (x - p[1])
		local s = if c > 0 then 1 elseif c < 0 then -1 else 0
		if s ~= 0 then
			if sign == 0 then
				sign = s
			elseif s ~= sign then
				return false
			end
		end
	end
	return true
end

local function polylineLength(points: { { number } }): number
	local total = 0
	for i = 1, #points - 1 do
		total += math.sqrt((points[i + 1][1] - points[i][1]) ^ 2 + (points[i + 1][2] - points[i][2]) ^ 2)
	end
	return total
end

local function pointAt(points: { { number } }, s: number): (number, number, number, number)
	local acc = 0
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		if acc + len >= s or i == #points - 1 then
			local t = math.clamp((s - acc) / len, 0, 1)
			return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, (b[1] - a[1]) / len, (b[2] - a[2]) / len
		end
		acc += len
	end
	error("empty polyline")
end
Village.pointAt = pointAt
Village.polylineLength = polylineLength

local function makeLot(
	hash01: (number, number, number) -> number,
	id: string,
	templateName: string,
	B: any,
	M: any,
	seedA: number,
	seedB: number,
	x: number,
	z: number,
	fx: number,
	fz: number
): Lot
	local t = B.Templates[templateName]
	assert(t, "unknown building template " .. templateName)
	return {
		id = id,
		style = templateName,
		x = x,
		z = z,
		fx = fx,
		fz = fz,
		width = t.width,
		depth = t.depth,
		stories = t.stories,
		storyHeight = t.storyHeight or M.Building.StoryHeight,
		colorSeed = math.floor(hash01(seedA, seedB, 14) * 100000),
		special = false,
	}
end

export type Layout = {
	lots: { Lot },
	fences: { any },
	poles: { any },
	signs: { any },
	cars: { any },
	trees: { any },
	yard: { any },
}

-- MT = Rules/MapTerrain (passed in: shared Rules modules cannot require each other in both Lune and Roblox).
-- P = Config/Props (boundary + yard kinds).
function Village.layout(map: any, B: any, M: any, MT: any, P: any): Layout
	local cfg = map.village
	local hash01 = MT.hash01
	local function roadDistance(x: number, z: number): number
		return (MT.roadDistance(map, x, z))
	end
	local lots: { Lot } = {}
	local pad = B.RoofOverhang + cfg.buildingGap / 2

	local function fits(l: Lot): boolean
		local quad = Village.corners(l, pad)
		for _, other in lots do
			if quadsOverlap(quad, Village.corners(other, pad)) then
				return false
			end
		end
		-- roads: sample the footprint perimeter and center
		local fp = Village.corners(l, B.RoofOverhang + 1)
		for i = 1, 4 do
			local p, q = fp[i], fp[i % 4 + 1]
			for k = 0, 4 do
				local t = k / 4
				local d = roadDistance(p[1] + (q[1] - p[1]) * t, p[2] + (q[2] - p[2]) * t)
				if d < 0 then
					return false
				end
			end
		end
		for _, c in cfg.keepClear do
			for _, v in fp do
				if (v[1] - c.x) ^ 2 + (v[2] - c.z) ^ 2 < c.r * c.r then
					return false
				end
			end
		end
		if MT.isRiver(map, l.x, l.z) then
			return false
		end
		return true
	end

	-- 1. Hand-placed landmarks
	for i, s in cfg.specials do
		local lot = makeLot(hash01, s.id, s.style, B, M, 900 + i, 1, s.x, s.z, s.front[1], s.front[2])
		lot.special = true
		table.insert(lots, lot)
	end

	-- 2. Lots along roads, candidates in hash order so the chosen ones scatter naturally
	local a = cfg.area
	for ri, road in cfg.roads do
		if (road.maxLots or 0) > 0 then
			local len = polylineLength(road.points)
			local candidates = {}
			local s = cfg.lotSpacing / 2 + (road.lotsFrom or 0) * len
			local k = 0
			while s < len - 8 do
				for _, side in { -1, 1 } do
					k += 1
					table.insert(candidates, { s = s, side = side, order = hash01(ri, k, 21) })
				end
				s += cfg.lotSpacing
			end
			if not road.rows then
				table.sort(candidates, function(p, q)
					return p.order < q.order
				end)
			end
			local placed = 0
			for ci, c in candidates do
				if placed >= road.maxLots then
					break
				end
				local px, pz, dx, dz = pointAt(road.points, c.s)
				local nx, nz = -dz * c.side, dx * c.side -- away from the road
				local styleList = if road.rows
					then B.RoadTemplates.Row
					elseif road.id == "Main" then B.RoadTemplates.Main
					else B.RoadTemplates.Lane
				local styleName = pick(styleList, hash01(ri, ci, 22))
				local lot = makeLot(hash01, road.id .. "_" .. ci, styleName, B, M, ri, ci, 0, 0, -nx, -nz)
				local off = road.width / 2 + cfg.setback + lot.depth / 2
				-- organic roads: small jitter in setback and angle
				if not road.rows then
					off += hash01(ri, ci, 23) * 4
					local ang = (hash01(ri, ci, 24) - 0.5) * math.rad(14)
					local c0, s0 = math.cos(ang), math.sin(ang)
					lot.fx, lot.fz = lot.fx * c0 - lot.fz * s0, lot.fx * s0 + lot.fz * c0
				end
				lot.x, lot.z = px + nx * off, pz + nz * off
				lot.road = road.id
				local inArea = lot.x > a.minX + 15
					and lot.x < a.maxX - 15
					and lot.z > a.minZ + 15
					and lot.z < a.maxZ - 15
				if inArea and fits(lot) then
					table.insert(lots, lot)
					placed += 1
				end
			end
		end
	end

	-- 3. Plot boundaries (Config/Props.BoundaryKinds): along the front with a gate gap at every door of
	-- the template, plus side runs back to the house's rear line so yards read as enclosed.
	local fences = {}
	local function clearOfRoads(p1: { number }, p2: { number }): boolean
		for k = 0, 4 do
			local t = k / 4
			if roadDistance(p1[1] + (p2[1] - p1[1]) * t, p1[2] + (p2[2] - p1[2]) * t) < 0.6 then
				return false
			end
		end
		return true
	end
	local function add(kind: string, p1: { number }, p2: { number })
		local len = math.sqrt((p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2)
		if len >= 1.5 and clearOfRoads(p1, p2) then
			table.insert(fences, { kind = kind, a = p1, b = p2 })
		end
	end
	for i, l in lots do
		if not l.special and hash01(i, 3, 31) < 0.85 then
			local rx, rz = -l.fz, l.fx
			local d = l.depth / 2 + cfg.setback - 1.5
			local half = l.width / 2 + 2
			local kind = if l.road == "RowStreet" then "PicketFence" else pick(P.BoundaryKinds, hash01(i, 3, 32))
			local function at(u: number, f: number): { number }
				return { l.x + rx * u + l.fx * f, l.z + rz * u + l.fz * f }
			end
			-- gate gaps over every door (template doors are in local X = frontage, centered on the plot)
			local gaps = {}
			for _, door in B.Templates[l.style].doors or { { center = 0 } } do
				table.insert(gaps, { door.center - 2.6, door.center + 2.6 })
			end
			table.sort(gaps, function(g1, g2)
				return g1[1] < g2[1]
			end)
			local u = -half
			for _, g in gaps do
				add(kind, at(u, d), at(g[1], d))
				u = g[2]
			end
			add(kind, at(u, d), at(half, d))
			-- sides, from the front line back to the rear wall line
			for _, side in { -1, 1 } do
				add(kind, at(side * half, d), at(side * half, -l.depth / 2))
			end
		end
	end

	-- 3b. Yard clutter beside some houses (Config/Props.YardKinds), clear of roads, plots and the river
	local yard = {}
	for i, l in lots do
		if not l.special and hash01(i, 4, 41) < P.YardChance then
			local rx, rz = -l.fz, l.fx
			local side = if hash01(i, 4, 42) < 0.5 then -1 else 1
			local u = side * (l.width / 2 + 4.5)
			local f = (hash01(i, 4, 43) - 0.5) * l.depth * 0.5
			local x, z = l.x + rx * u + l.fx * f, l.z + rz * u + l.fz * f
			local ok = roadDistance(x, z) > 3 and not MT.isRiver(map, x, z)
			for j, other in lots do
				if j ~= i and Village.pointInQuad(x, z, Village.corners(other, B.RoofOverhang + 2)) then
					ok = false
				end
			end
			if ok then
				table.insert(
					yard,
					{ kind = pick(P.YardKinds, hash01(i, 4, 44)), x = x, z = z, yaw = hash01(i, 4, 45) * 360 }
				)
			end
		end
	end
	for _, f in cfg.features or {} do
		table.insert(yard, { kind = f.kind, x = f.x, z = f.z, yaw = f.yaw or 0 })
	end

	-- 4. Telegraph poles along one road
	local poles = {}
	do
		local road
		for _, r in cfg.roads do
			if r.id == cfg.poles.road then
				road = r
			end
		end
		local len = polylineLength(road.points)
		local s = 20
		while s < len do
			local px, pz, dx, dz = pointAt(road.points, s)
			local side = cfg.poles.side
			local x, z = px - dz * side * (road.width / 2 + 2), pz + dx * side * (road.width / 2 + 2)
			local blocked = false
			for _, l in lots do
				if Village.pointInQuad(x, z, Village.corners(l, B.RoofOverhang + 1)) then
					blocked = true
				end
			end
			if not blocked and not MT.isRiver(map, x, z) then
				table.insert(poles, { x = x, z = z, dx = dx, dz = dz })
			end
			s += cfg.poles.spacing
		end
	end

	-- 5. Signposts where lanes leave the main road
	local signs = {}
	for _, r in cfg.roads do
		if r.id ~= "Main" and r.id ~= "FarmTrack" then
			local px, pz, dx, dz = pointAt(r.points, r.width + 4)
			table.insert(
				signs,
				{ x = px - dz * (r.width / 2 + 1.5), z = pz + dx * (r.width / 2 + 1.5), dx = dx, dz = dz }
			)
		end
	end

	-- 6. Parked cars along the main road, at the road edge in front of houses
	local cars = {}
	for _, l in lots do
		if #cars >= cfg.cars then
			break
		end
		if l.road == "Main" and hash01(#cars, 5, 41) < 0.8 then
			local d = l.depth / 2 + cfg.setback + 2.5
			table.insert(cars, { x = l.x + l.fx * d, z = l.z + l.fz * d, dx = -l.fz, dz = l.fx, variant = #cars })
		end
	end

	-- 7. Garden trees inside the village area, clear of roads, buildings and squares
	local trees = {}
	local T = cfg.trees
	for cx = math.floor(a.minX / T.cell), math.floor(a.maxX / T.cell) do
		for cz = math.floor(a.minZ / T.cell), math.floor(a.maxZ / T.cell) do
			if hash01(cx, cz, 51) < T.density then
				local x = (cx + 0.25 + 0.5 * hash01(cx, cz, 52)) * T.cell
				local z = (cz + 0.25 + 0.5 * hash01(cx, cz, 53)) * T.cell
				local ok = roadDistance(x, z) > T.roadClear and not MT.isRiver(map, x, z)
				for _, c in cfg.keepClear do
					if (x - c.x) ^ 2 + (z - c.z) ^ 2 < c.r * c.r then
						ok = false
					end
				end
				if ok then
					for _, l in lots do
						if Village.pointInQuad(x, z, Village.corners(l, B.RoofOverhang + T.buildingClear)) then
							ok = false
							break
						end
					end
				end
				if ok then
					local k = hash01(cx, cz, 54)
					table.insert(trees, {
						x = x,
						z = z,
						kind = if k < 0.25 then "Pine" elseif k < 0.8 then "Broadleaf" else "Birch",
						scale = 0.75 + 0.35 * hash01(cx, cz, 55),
						yaw = hash01(cx, cz, 56) * 360,
						variant = math.floor(hash01(cx, cz, 57) * 1000),
						far = false,
					})
				end
			end
		end
	end

	return { lots = lots, fences = fences, poles = poles, signs = signs, cars = cars, trees = trees, yard = yard }
end

local function segmentDistance(x: number, z: number, a: { number }, b: { number }): number
	local dx, dz = b[1] - a[1], b[2] - a[2]
	local len2 = dx * dx + dz * dz
	local t = if len2 == 0 then 0 else math.clamp(((x - a[1]) * dx + (z - a[2]) * dz) / len2, 0, 1)
	return math.sqrt((x - a[1] - dx * t) ^ 2 + (z - a[2] - dz * t) ^ 2)
end

-- A hand-placed layout (a map's `layout`: lots, fences and yard pieces in world studs, as Config/Maps/Playtest) in
-- the shape `layout` returns; its trees are the map's natural ones (Rules/MapTerrain.trees) less those within
-- `trees.buildingClear` of a building, fence or yard piece.
function Village.fixed(map: any, B: any, M: any, MT: any): Layout
	local L = map.layout
	local lots: { Lot } = {}
	for _, p in L.lots do
		local t = B.Templates[p.style]
		assert(t, "unknown building template " .. p.style)
		table.insert(lots, {
			id = p.id,
			style = p.style,
			x = p.x,
			z = p.z,
			fx = p.fx,
			fz = p.fz,
			width = t.width,
			depth = t.depth,
			stories = t.stories,
			storyHeight = t.storyHeight or M.Building.StoryHeight,
			colorSeed = p.colorSeed,
			special = true,
		})
	end
	local clear = map.trees.buildingClear
	local quads = {}
	for _, l in lots do
		table.insert(quads, Village.corners(l, clear))
	end
	local trees = {}
	for _, t in MT.trees(map) do
		local ok = true
		for _, q in quads do
			if Village.pointInQuad(t.x, t.z, q) then
				ok = false
				break
			end
		end
		for _, f in L.fences do
			ok = ok and segmentDistance(t.x, t.z, f.a, f.b) > clear / 2
		end
		for _, y in L.yard do
			ok = ok and (t.x - y.x) ^ 2 + (t.z - y.z) ^ 2 > clear * clear
		end
		if ok then
			table.insert(trees, t)
		end
	end
	return { lots = lots, fences = L.fences, poles = {}, signs = {}, cars = {}, trees = trees, yard = L.yard }
end

return Village
