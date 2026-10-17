--!strict
-- The map checker (roadmap 2.1, Config/MapCheck): a walk grid over the playable area from the map's ground (Rules/
-- MapTerrain), its trees and its buildings (Rules/Village lots), then
-- - reach: where you can walk from a spawn (uphill no steeper than the max slope, any drop down, no deep water);
-- - falls: places you can get to but not back from (a pit);
-- - sight: how far a standing soldier at a point sees a standing soldier, per direction, past ground, buildings and
--   canopies, up to the fog;
-- - travel: the shortest walk from a spawn to anywhere (distance over the ground).
-- Pure: numbers and tables only.

local MapCheck = {}

export type Grid = {
	map: any,
	cfg: any,
	cell: number,
	nx: number,
	nz: number,
	minX: number,
	minZ: number,
	height: { number },
	open: { boolean }, -- a soldier can stand here
	top: { number }, -- what blocks sight at this cell (ground, or a building's top)
	canopies: { [string]: { { x: number, y: number, z: number, r: number } } },
	maxRise: number, -- the most a step uphill to a side neighbour may climb (x sqrt 2 diagonally)
}

local BUCKET = 32

local function key(x: number, z: number): string
	return math.floor(x / BUCKET) .. ":" .. math.floor(z / BUCKET)
end

function MapCheck.index(g: Grid, ix: number, iz: number): number?
	if ix < 0 or iz < 0 or ix >= g.nx or iz >= g.nz then
		return nil
	end
	return ix * g.nz + iz + 1
end

function MapCheck.cellAt(g: Grid, x: number, z: number): number?
	return MapCheck.index(g, math.floor((x - g.minX) / g.cell + 0.5), math.floor((z - g.minZ) / g.cell + 0.5))
end

function MapCheck.position(g: Grid, i: number): (number, number)
	local ix, iz = (i - 1) // g.nz, (i - 1) % g.nz
	return g.minX + ix * g.cell, g.minZ + iz * g.cell
end

local function pointInQuad(x: number, z: number, q: { { number } }): boolean
	local inside = false
	local j = #q
	for i = 1, #q do
		local a, b = q[i], q[j]
		if (a[2] > z) ~= (b[2] > z) and x < (b[1] - a[1]) * (z - a[2]) / (b[2] - a[2]) + a[1] then
			inside = not inside
		end
		j = i
	end
	return inside
end

-- `trees`: { x, z, kind, scale, far? }; `lots`: building lots ({ corners, stories, storyHeight }); `treeHeight`:
-- kind -> height at scale 1; `maxSlope`: degrees.
function MapCheck.grid(
	map: any,
	MT: any,
	cfg: any,
	trees: { any },
	lots: { any },
	treeHeight: { [string]: number },
	maxSlope: number
): Grid
	local b, cell = map.bounds, cfg.Cell
	local nx = math.floor((b.maxX - b.minX) / cell) + 1
	local nz = math.floor((b.maxZ - b.minZ) / cell) + 1
	local g: Grid = {
		map = map,
		cfg = cfg,
		cell = cell,
		nx = nx,
		nz = nz,
		minX = b.minX,
		minZ = b.minZ,
		height = table.create(nx * nz, 0),
		open = table.create(nx * nz, true),
		top = table.create(nx * nz, 0),
		canopies = {},
		maxRise = math.tan(math.rad(maxSlope)) * cell,
	}
	local river = map.river
	for ix = 0, nx - 1 do
		for iz = 0, nz - 1 do
			local i = ix * nz + iz + 1
			local x, z = b.minX + ix * cell, b.minZ + iz * cell
			local h = MT.heightAt(map, x, z)
			g.height[i] = h
			g.top[i] = h
			if river and MT.isRiver(map, x, z) and river.waterY - h > cfg.WadeDepth then
				g.open[i] = false
			end
		end
	end
	for _, t in trees do
		local x, z = t.x, t.z
		if not t.far and x >= b.minX and x <= b.maxX and z >= b.minZ and z <= b.maxZ then
			local r = cfg.TrunkRadius * t.scale
			for ix = math.floor((x - r - b.minX) / cell + 0.5), math.floor((x + r - b.minX) / cell + 0.5) do
				for iz = math.floor((z - r - b.minZ) / cell + 0.5), math.floor((z + r - b.minZ) / cell + 0.5) do
					local i = MapCheck.index(g, ix, iz)
					local cx, cz = b.minX + ix * cell, b.minZ + iz * cell
					if i and (cx - x) ^ 2 + (cz - z) ^ 2 <= (r + cell / 2) ^ 2 then
						g.open[i] = false
					end
				end
			end
			local height = (treeHeight[t.kind] or 30) * t.scale
			local k = key(x, z)
			g.canopies[k] = g.canopies[k] or {}
			table.insert(g.canopies[k], {
				x = x,
				z = z,
				y = MT.heightAt(map, x, z) + height * cfg.Canopy.centre,
				r = height * cfg.Canopy.radius,
			})
		end
	end
	for _, l in lots do
		local q = l.corners
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, c in q do
			x0, x1, z0, z1 = math.min(x0, c[1]), math.max(x1, c[1]), math.min(z0, c[2]), math.max(z1, c[2])
		end
		local high = l.stories * l.storyHeight + cfg.RoofHeight
		for ix = math.floor((x0 - b.minX) / cell), math.ceil((x1 - b.minX) / cell) do
			for iz = math.floor((z0 - b.minZ) / cell), math.ceil((z1 - b.minZ) / cell) do
				local i = MapCheck.index(g, ix, iz)
				if i and pointInQuad(b.minX + ix * cell, b.minZ + iz * cell, q) then
					g.open[i] = false
					g.top[i] = g.height[i] + high
				end
			end
		end
	end
	return g
end

local NEIGHBOURS = {
	{ 1, 0, 1 },
	{ -1, 0, 1 },
	{ 0, 1, 1 },
	{ 0, -1, 1 },
	{ 1, 1, math.sqrt(2) },
	{ 1, -1, math.sqrt(2) },
	{ -1, 1, math.sqrt(2) },
	{ -1, -1, math.sqrt(2) },
}

-- each open neighbour of `i` you can step to (`back`: the neighbours that can step to `i`), with the distance
local function steps(g: Grid, i: number, back: boolean): { { number } }
	local out = {}
	local ix, iz = (i - 1) // g.nz, (i - 1) % g.nz
	local h = g.height[i]
	for _, n in NEIGHBOURS do
		local j = MapCheck.index(g, ix + n[1], iz + n[2])
		if j and g.open[j] then
			local rise = if back then h - g.height[j] else g.height[j] - h
			if rise <= g.maxRise * n[3] then
				local run = n[3] * g.cell
				table.insert(out, { j, math.sqrt(run * run + rise * rise) })
			end
		end
	end
	return out
end

-- the open cells in a rectangle (a spawn zone)
function MapCheck.cellsIn(g: Grid, r: { minX: number, maxX: number, minZ: number, maxZ: number }): { number }
	local out = {}
	for i = 1, g.nx * g.nz do
		local x, z = MapCheck.position(g, i)
		if g.open[i] and x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ then
			table.insert(out, i)
		end
	end
	return out
end

-- the shortest walk (studs over the ground) from any of `from` to every cell (nil: can't get there); `back`: the walk
-- from every cell to `from` instead
function MapCheck.walk(g: Grid, from: { number }, back: boolean?): { [number]: number }
	local dist: { [number]: number } = {}
	-- binary heap of { cost, cell }
	local heap: { { number } } = {}
	local function push(c: number, i: number)
		table.insert(heap, { c, i })
		local k = #heap
		while k > 1 do
			local p = k // 2
			if heap[p][1] <= heap[k][1] then
				break
			end
			heap[p], heap[k] = heap[k], heap[p]
			k = p
		end
	end
	local function pop(): { number }
		local topItem = heap[1]
		local last = table.remove(heap) :: { number }
		if #heap > 0 then
			heap[1] = last
			local k = 1
			while true do
				local l, r, m = 2 * k, 2 * k + 1, k
				if l <= #heap and heap[l][1] < heap[m][1] then
					m = l
				end
				if r <= #heap and heap[r][1] < heap[m][1] then
					m = r
				end
				if m == k then
					break
				end
				heap[m], heap[k] = heap[k], heap[m]
				k = m
			end
		end
		return topItem
	end
	for _, i in from do
		dist[i] = 0
		push(0, i)
	end
	while #heap > 0 do
		local item = pop()
		local c, i = item[1], item[2]
		if c <= dist[i] then
			for _, s in steps(g, i, back == true) do
				local nc = c + s[2]
				if dist[s[1]] == nil or nc < dist[s[1]] then
					dist[s[1]] = nc
					push(nc, s[1])
				end
			end
		end
	end
	return dist
end

-- the reached cell nearest to (x, z) within `radius`, and its walk distance
function MapCheck.nearest(g: Grid, dist: { [number]: number }, x: number, z: number, radius: number): (number?, number?)
	local best, bestD = nil, math.huge
	local r = math.ceil(radius / g.cell)
	local cx, cz = math.floor((x - g.minX) / g.cell + 0.5), math.floor((z - g.minZ) / g.cell + 0.5)
	for ix = cx - r, cx + r do
		for iz = cz - r, cz + r do
			local i = MapCheck.index(g, ix, iz)
			if i and dist[i] then
				local px, pz = MapCheck.position(g, i)
				local d = (px - x) ^ 2 + (pz - z) ^ 2
				if d <= radius * radius and d < bestD then
					best, bestD = i, d
				end
			end
		end
	end
	return best, if best then dist[best] else nil
end

-- pits: cells reached from `from` that can't walk back to it
function MapCheck.pits(g: Grid, from: { number }): { number }
	local there = MapCheck.walk(g, from)
	local back = MapCheck.walk(g, from, true)
	local out = {}
	for i in there do
		if not back[i] then
			table.insert(out, i)
		end
	end
	table.sort(out)
	return out
end

-- open cells no spawn walks to, grouped into pockets (each a list of cells), biggest first
function MapCheck.pockets(g: Grid, reached: { [number]: number }): { { number } }
	local seen: { [number]: boolean } = {}
	local out = {}
	for i = 1, g.nx * g.nz do
		if g.open[i] and not reached[i] and not seen[i] then
			local pocket, stack = {}, { i }
			seen[i] = true
			while #stack > 0 do
				local c = table.remove(stack) :: number
				table.insert(pocket, c)
				local ix, iz = (c - 1) // g.nz, (c - 1) % g.nz
				for _, n in NEIGHBOURS do
					local j = MapCheck.index(g, ix + n[1], iz + n[2])
					if j and g.open[j] and not reached[j] and not seen[j] then
						seen[j] = true
						table.insert(stack, j)
					end
				end
			end
			table.insert(out, pocket)
		end
	end
	table.sort(out, function(a, b)
		return #a > #b
	end)
	return out
end

-- ground (or building) height at (x, z), bilinear between cells; nil outside the grid
local function topAt(g: Grid, x: number, z: number): number?
	local fx, fz = (x - g.minX) / g.cell, (z - g.minZ) / g.cell
	local ix, iz = math.floor(fx), math.floor(fz)
	local a, b2 = MapCheck.index(g, ix, iz), MapCheck.index(g, ix + 1, iz)
	local c, d = MapCheck.index(g, ix, iz + 1), MapCheck.index(g, ix + 1, iz + 1)
	if not (a and b2 and c and d) then
		return nil
	end
	local tx, tz = fx - ix, fz - iz
	local t = g.top
	return (t[a] * (1 - tx) + t[b2] * tx) * (1 - tz) + (t[c] * (1 - tx) + t[d] * tx) * tz
end

-- How far a standing soldier at (x, z) sees a standing soldier along unit (dx, dz), up to `limit`: the farthest
-- distance at which the line from eye to head is clear of ground, buildings and canopies.
function MapCheck.sight(g: Grid, x: number, z: number, dx: number, dz: number, limit: number): number
	local cfg = g.cfg
	local ground = topAt(g, x, z)
	if not ground then
		return 0
	end
	local eye = g.height[MapCheck.cellAt(g, x, z) :: number] + cfg.TargetHeight
	local horizon = -math.huge -- the steepest slope (rise / run) of anything closer
	local shade: { { number } } = {} -- canopy slopes { low, high } closer
	local seenTo = 0
	local d = cfg.Step
	while d <= limit do
		local px, pz = x + dx * d, z + dz * d
		local top = topAt(g, px, pz)
		if not top then
			break
		end
		local i = MapCheck.cellAt(g, px, pz) :: number
		local head = (g.height[i] + cfg.TargetHeight - eye) / d
		local hidden = head < horizon
		if not hidden then
			for _, s in shade do
				if head >= s[1] and head <= s[2] then
					hidden = true
					break
				end
			end
		end
		if not hidden then
			seenTo = d
		end
		horizon = math.max(horizon, (top - eye) / d)
		for _, c in g.canopies[key(px, pz)] or {} do
			local off = (c.x - px) ^ 2 + (c.z - pz) ^ 2
			if off < c.r * c.r then
				local half = math.sqrt(c.r * c.r - off)
				table.insert(shade, { (c.y - half - eye) / d, (c.y + half - eye) / d })
			end
		end
		d += cfg.Step
	end
	return seenTo
end

-- the farthest sight line from (x, z) over `Directions` evenly spaced directions, and how many reach past `beyond`
function MapCheck.sightRose(g: Grid, x: number, z: number, limit: number, beyond: number): (number, number, { number })
	local n = g.cfg.Directions
	local best, past, all = 0, 0, {}
	for k = 0, n - 1 do
		local a = k / n * 2 * math.pi
		local s = MapCheck.sight(g, x, z, math.cos(a), math.sin(a), limit)
		table.insert(all, s)
		best = math.max(best, s)
		if s > beyond then
			past += 1
		end
	end
	return best, past, all
end

return MapCheck
