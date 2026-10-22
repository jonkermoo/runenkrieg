--!strict
-- Player building (Config/Build; src/server/Build builds, src/client/Build shows the ghost). Pure: numbers and tables.

local Build = {}

export type Piece = { [string]: any }

-- the piece entry for `key` (Config/Build.Pieces), or nil
function Build.piece(key: any, pieces: { Piece }): Piece?
	if type(key) ~= "string" then
		return nil
	end
	for _, p in pieces do
		if p.key == key then
			return p
		end
	end
	return nil
end

-- the ground's slope in degrees between two heights `span` studs apart
function Build.slope(h1: number, h2: number, span: number): number
	if span <= 0 then
		return 90
	end
	return math.deg(math.atan(math.abs(h1 - h2) / span))
end

-- the steepest slope over a footprint's sample heights, taken as a grid of `rows` rows (row-major) `dx` / `dz` apart
function Build.steepest(heights: { number }, rows: number, dx: number, dz: number): number
	local cols = #heights // math.max(rows, 1)
	local worst = 0
	for r = 1, rows do
		for c = 1, cols do
			local h = heights[(r - 1) * cols + c]
			if c < cols then
				worst = math.max(worst, Build.slope(h, heights[(r - 1) * cols + c + 1], dx))
			end
			if r < rows then
				worst = math.max(worst, Build.slope(h, heights[r * cols + c], dz))
			end
		end
	end
	return worst
end

export type Placing = {
	piece: Piece,
	distance: number, -- builder's root to the piece's centre
	reach: number,
	slope: number, -- the steepest ground slope under it (Build.steepest)
	maxSlope: number,
	ground: boolean, -- every sample found terrain under it
	water: boolean, -- water under any sample
	overlap: boolean, -- it overlaps a building, another piece or a soldier
	mine: number, -- the builder's live pieces
	team: number, -- the team's live pieces
	perPlayer: number,
	perTeam: number,
}

-- Whether a piece can be laid here; when not, the reason to show
function Build.canPlace(p: Placing): (boolean, string?)
	if p.distance > p.reach then
		return false, "Too far"
	end
	if not p.ground then
		return false, "Needs open ground"
	end
	if p.water then
		return false, "Not in water"
	end
	if p.slope > p.maxSlope then
		return false, "Too steep"
	end
	if p.overlap then
		return false, "In the way"
	end
	if p.mine >= p.perPlayer then
		return false, "You have too many pieces"
	end
	if p.team >= p.perTeam then
		return false, "Your team has too many pieces"
	end
	return true, nil
end

-- which of `stages` cuts or courses a piece shows at `work` of `need` (0 = only the blueprint)
function Build.stageOf(work: number, need: number, stages: number): number
	if need <= 0 then
		return stages
	end
	return math.clamp(math.floor(work / need * stages + 1e-9), 0, stages)
end

-- One shovel swing on a piece at `work` of `need`: your own team's adds one (up to `need`), another team's takes one
-- off. Returns the new work and whether the piece is gone (another team's swing took the last unit).
function Build.swing(work: number, need: number, ownTeam: boolean): (number, boolean)
	if ownTeam then
		return math.min(work + 1, need), false
	end
	local left = work - 1
	return math.max(left, 0), left <= 0
end

-- whether a swing comes too soon after the last (`slack` x the dig's length)
function Build.tooSoon(now: number, last: number?, length: number, slack: number): boolean
	return last ~= nil and now - last < length * slack
end

export type Segment = {
	length: number,
	depth: number, -- how deep it is cut now (the full depth x share)
	share: number, -- how far it is dug: stage / stages (the banks rise with it)
	openA: boolean, -- an open end at u = 0 (a ramp up out of it)
	openB: boolean, -- at u = length
	exit: boolean, -- the exit piece: a ramp out of the back in its middle
}

-- The trench's ground at a point `u` along it (0 at end A, `length` at end B) and `v` across it (back negative, front
-- positive), as a height relative to the ground there before it was dug: negative where it is cut, positive where earth
-- is thrown up. Second result: only cut, never fill (ramps through banks). nil: untouched.
-- `t` is Config/Build.Trench, `firestep` Config/Metrics.Trench.FirestepWidth.
function Build.trenchAt(u: number, v: number, seg: Segment, t: any, firestep: number): (number?, boolean)
	local L, depth = seg.length, seg.depth
	if depth <= 0 then
		return nil, false
	end
	local frontWall = t.front + firestep
	local margin = t.cutMargin or 0
	local inside = v >= t.back - margin and v <= frontWall + margin
	local within = u >= 0 and u <= L
	local lowA = if seg.openA then 0 else -t.overlap
	local highB = if seg.openB then L else L + t.overlap
	-- the floor (on past a joined end, so corners meet)
	if inside and u >= lowA and u <= highB then
		return -depth, false
	end
	-- an open end's ramp, rising out along the trench
	local ramp = t.ramp
	if math.abs(v - (t.back + frontWall) / 2) <= ramp.width / 2 then
		if seg.openA and u < 0 and u >= -ramp.length then
			return -depth * (1 + u / ramp.length), true
		end
		if seg.openB and u > L and u <= L + ramp.length then
			return -depth * (1 - (u - L) / ramp.length), true
		end
	end
	-- the exit piece's ramp out of the back wall
	if seg.exit and math.abs(u - L / 2) <= ramp.width / 2 and v < t.back and v >= t.back - margin - ramp.length then
		return -depth * math.min(1 - (t.back - margin - v) / ramp.length, 1), true
	end
	if not within then
		return nil, false
	end
	-- the parapet in front and the parados behind: banks peaked in their middles
	local par = t.parapet
	if v > frontWall + margin and v <= frontWall + margin + par.width then
		local x = (v - frontWall - margin) / par.width
		return par.height * (1 - math.abs(x * 2 - 1)) * seg.share, false
	end
	local pd = t.parados
	if v < t.back - margin and v >= t.back - margin - pd.width then
		local x = (t.back - margin - v) / pd.width
		return pd.height * (1 - math.abs(x * 2 - 1)) * seg.share, false
	end
	return nil, false
end

-- A voxel column's occupancies (bottom to top, voxels `res` tall starting at `y0`) set so the surface stands at
-- height `want`: cut down to it (and filled up to it unless `cutOnly`). A smooth surface stands at its top voxel's
-- centre + res x occupancy (src/server/Ground.pit, measured in Studio).
function Build.shapeColumn(occs: { number }, y0: number, res: number, want: number, cutOnly: boolean): { number }
	local out = table.create(#occs, 0)
	for i, o in occs do
		local mid = y0 + (i - 0.5) * res
		local keep = math.clamp((want - mid) / res, 0, 1)
		out[i] = if cutOnly then math.min(o, keep) else keep
	end
	return out
end

-- The surface height of a voxel column (bottom to top) or nil when it is all air
function Build.columnTop(occs: { number }, y0: number, res: number): number?
	for i = #occs, 1, -1 do
		if occs[i] > 0 then
			return y0 + (i - 0.5) * res + occs[i] * res
		end
	end
	return nil
end

-- Trench lines: segments `{ a, b, length, exit }` joined where they share an end node id. An end node only one
-- segment uses is open (a ramp up). Returns the farthest any point of the trench lies from a way out, walking along
-- it: an open end, or an exit piece's middle.
function Build.farthestFromExit(segs: { { a: number, b: number, length: number, exit: boolean? } }): number
	local uses: { [number]: number } = {}
	for _, s in segs do
		uses[s.a] = (uses[s.a] or 0) + 1
		uses[s.b] = (uses[s.b] or 0) + 1
	end
	-- the graph: end nodes, plus a middle node per exit piece (keys above every end id)
	local edges: { [number]: { { to: number, len: number } } } = {}
	local function link(x: number, y: number, len: number)
		edges[x] = edges[x] or {}
		edges[y] = edges[y] or {}
		table.insert(edges[x], { to = y, len = len })
		table.insert(edges[y], { to = x, len = len })
	end
	local top = 0
	for id in uses do
		top = math.max(top, id)
	end
	local dist: { [number]: number } = {}
	local spans: { { x: number, y: number, len: number } } = {}
	for i, s in segs do
		if s.exit then
			local mid = top + i
			link(s.a, mid, s.length / 2)
			link(mid, s.b, s.length / 2)
			table.insert(spans, { x = s.a, y = mid, len = s.length / 2 })
			table.insert(spans, { x = mid, y = s.b, len = s.length / 2 })
			dist[mid] = 0
		else
			link(s.a, s.b, s.length)
			table.insert(spans, { x = s.a, y = s.b, len = s.length })
		end
	end
	for id, n in uses do
		if n == 1 then
			dist[id] = 0
		end
	end
	-- shortest walks from every way out (few nodes: a plain relaxation is enough)
	local changed = true
	while changed do
		changed = false
		for x, list in edges do
			local dx = dist[x]
			if dx then
				for _, e in list do
					local d = dx + e.len
					if dist[e.to] == nil or d < dist[e.to] - 1e-9 then
						dist[e.to] = d
						changed = true
					end
				end
			end
		end
	end
	local worst = 0
	for _, sp in spans do
		local dx, dy = dist[sp.x], dist[sp.y]
		if dx == nil or dy == nil then
			return math.huge -- a closed loop with no way out
		end
		-- the farthest point along this span from either end's nearest way out
		worst = math.max(worst, (dx + dy + sp.len) / 2)
	end
	return worst
end

export type Bag = { column: number, row: number, x: number, y: number, width: number, height: number }

-- A sandbag wall's bags (Config/Build.Pieces entry): for each column and row a course of bags, `x` the bag's centre
-- across the wall (0 = the middle), `y` its centre above the ground; every other row offset by half a bag (a bond),
-- the loophole row of the middle column left out.
function Build.sandbags(p: Piece): { Bag }
	local out: { Bag } = {}
	local colWidth = p.width / p.columns
	local middle = (p.columns + 1) // 2
	for c = 1, p.columns do
		local left = -p.width / 2 + (c - 1) * colWidth
		for r = 1, p.rows do
			if not (p.loophole and r == p.loophole and c == middle) then
				local y = (r - 0.5) * p.row
				if r % 2 == 1 then
					table.insert(
						out,
						{ column = c, row = r, x = left + colWidth / 2, y = y, width = colWidth, height = p.row }
					)
				else
					-- two half-offset bags: half a bag each side of the column's middle
					local half = colWidth / 2
					table.insert(out, { column = c, row = r, x = left + half / 2, y = y, width = half, height = p.row })
					table.insert(out, {
						column = c,
						row = r,
						x = left + half * 1.5,
						y = y,
						width = half,
						height = p.row,
					})
				end
			end
		end
	end
	return out
end

-- whether a point in a box's own space (`lx`, `ly`, `lz` from its centre) is inside it (`sx`, `sy`, `sz` its size)
function Build.inBox(lx: number, ly: number, lz: number, sx: number, sy: number, sz: number): boolean
	return math.abs(lx) <= sx / 2 and math.abs(ly) <= sy / 2 and math.abs(lz) <= sz / 2
end

-- the wire's harm over `dt` seconds to a soldier moving at `speed` studs/s (Config/Build.Wire)
function Build.wireHarm(speed: number, dt: number, w: any): number
	if speed <= w.moving or dt <= 0 then
		return 0
	end
	return w.damage * dt
end

-- the work a trench keeps when `caved` studs of its `length` cave in
function Build.caveWork(work: number, need: number, caved: number, length: number): number
	if length <= 0 then
		return work
	end
	return math.max(work - math.ceil(need * math.clamp(caved / length, 0, 1)), 0)
end

return Build
