--!strict
-- Pure, deterministic village layout: building lots along roads, fences/hedges, poles, signposts,
-- parked cars and garden trees. No Instances; the Studio builder turns this into geometry.

local Village = {}

export type Lot = {
	id: string,
	style: string,
	x: number, -- center
	z: number,
	fx: number, -- unit vector the front (door) faces
	fz: number,
	width: number,
	depth: number,
	stories: number,
	storyHeight: number,
	roofPitch: number,
	wall: { finish: string, class: string },
	roof: string,
	chimneys: number,
	dormer: boolean,
	road: string?,
	special: boolean,
}

local function pick<T>(list: { T }, u: number): T
	return list[math.floor(u * #list) + 1]
end

local function lerpRange(r: { number }, u: number): number
	return math.floor(r[1] + (r[2] - r[1]) * u + 0.5)
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
	styleName: string,
	styles: any,
	seedA: number,
	seedB: number,
	x: number,
	z: number,
	fx: number,
	fz: number
): Lot
	local st = styles[styleName]
	local stories = pick(st.stories, hash01(seedA, seedB, 11))
	local width = lerpRange(st.width, hash01(seedA, seedB, 12))
	return {
		id = id,
		style = styleName,
		x = x,
		z = z,
		fx = fx,
		fz = fz,
		width = width,
		depth = lerpRange(st.depth, hash01(seedA, seedB, 13)),
		stories = stories,
		storyHeight = st.storyHeight,
		roofPitch = st.roofPitch,
		wall = pick(st.walls, hash01(seedA, seedB, 14)),
		roof = pick(st.roofs, hash01(seedA, seedB, 15)),
		chimneys = pick(st.chimneys, hash01(seedA, seedB, 16)),
		dormer = stories >= 2 and hash01(seedA, seedB, 17) < st.dormerChance,
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
}

-- MT = Rules/MapTerrain (passed in: shared Rules modules cannot require each other in both Lune and Roblox).
function Village.layout(map: any, B: any, M: any, MT: any): Layout
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
		local lot = makeLot(hash01, s.id, s.style, B.Styles, 900 + i, 1, s.x, s.z, s.front[1], s.front[2])
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
					then B.RoadStyles.Row
					elseif road.id == "Main" then B.RoadStyles.Main
					else B.RoadStyles.Lane
				local styleName = pick(styleList, hash01(ri, ci, 22))
				local lot = makeLot(hash01, road.id .. "_" .. ci, styleName, B.Styles, ri, ci, 0, 0, -nx, -nz)
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
				local twoStoryOk = lot.stories < 2
					or lot.width - 2 >= lot.storyHeight / M.Building.StairRise * M.Building.StairRun + 3
				if not twoStoryOk then
					lot.stories = 1
					lot.dormer = false
				end
				if inArea and fits(lot) then
					table.insert(lots, lot)
					placed += 1
				end
			end
		end
	end

	-- 3. Front fences or hedges, with a gate gap at the door path
	local fences = {}
	for i, l in lots do
		if not l.special and hash01(i, 3, 31) < 0.75 then
			local rx, rz = -l.fz, l.fx
			local d = l.depth / 2 + cfg.setback - 1.5
			local cx, cz = l.x + l.fx * d, l.z + l.fz * d
			local half = l.width / 2 + 2
			local kind = if l.style == "Row" or hash01(i, 3, 32) < 0.6 then "Fence" else "Hedge"
			for _, side in { -1, 1 } do
				local inner, outer = 2.5, half
				table.insert(fences, {
					kind = kind,
					a = { cx + rx * side * inner, cz + rz * side * inner },
					b = { cx + rx * side * outer, cz + rz * side * outer },
				})
			end
		end
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

	return { lots = lots, fences = fences, poles = poles, signs = signs, cars = cars, trees = trees }
end

return Village
