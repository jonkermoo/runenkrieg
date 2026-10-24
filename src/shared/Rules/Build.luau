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

-- Trenches v2 (Config/Build.Trench, src/server/Trenches). A trench is made of blocks along straight runs; inside a block
-- `u` runs along it from end A (0) to end B (`length`) and `v` across it, from its centre line.

-- the half width across the top of a trench's walls
function Build.trenchTop(t: any): number
	return t.floor + t.depth / math.tan(math.rad(t.wallAngle))
end

-- A run `length` long split into segments of a fixed `block` studs (user 2026-10-23: "make each segment a fixed size.
-- if you plan to make a trench that isnt a fixed size, then it will blend with the last segment or become a partial
-- segment"): what's left over goes onto the last segment when it's under half a segment, else it is a partial segment
-- of its own; a run shorter than a segment is one partial segment. A list of { from, to } along the run; nil when the
-- run is shorter than `minBlock`.
function Build.planBlocks(length: number, block: number, minBlock: number): { { from: number, to: number } }?
	if length < minBlock - 1e-6 then
		return nil
	end
	local n = math.floor(length / block + 1e-6)
	local left = length - n * block
	local out = {}
	for i = 1, n do
		table.insert(out, { from = (i - 1) * block, to = i * block })
	end
	if n == 0 or left >= block / 2 then
		table.insert(out, { from = n * block, to = length })
	elseif left > 1e-6 then
		out[n].to = length -- (blends into the last segment)
	end
	return out
end

export type BlockShape = {
	length: number,
	extA: number, -- how far its hole runs on past end A where another trench joins there (0 at a dead end)
	extB: number,
	deadA: boolean, -- a dead end: the walls close round it
	deadB: boolean,
}

-- How far a point (`u` along a block, `v` across) is from the block's floor centre in the trench's own sense: |v| along
-- the block and on past a joined end; round a dead end, the floor's edge plus the distance past it (the end wall
-- curves round like the sides). nil past a joined end's reach.
function Build.trenchReach(u: number, v: number, b: BlockShape, floor: number): number?
	local av = math.abs(v)
	if u >= 0 and u <= b.length then
		return av
	end
	local past = if u < 0 then -u else u - b.length
	local dead = if u < 0 then b.deadA else b.deadB
	local ext = if u < 0 then b.extA else b.extB
	if dead then
		return floor + math.sqrt(math.max(av - floor, 0) ^ 2 + past * past)
	end
	return if past <= ext then av else nil
end

-- A trench's ground at reach `r` from its floor centre (Build.trenchReach), relative to the ground there before:
-- negative where it is cut (`share` of the full depth: the floor, then walls rising at the wall angle to the top), positive
-- where earth is thrown up as the bank past the top (a hump), nil beyond.
function Build.trenchProfile(r: number, share: number, t: any): number?
	if share <= 0 then
		return nil
	end
	local depth = t.depth * share
	local top = Build.trenchTop(t)
	if r <= t.floor then
		return -depth
	end
	if r <= top then
		return -depth * (1 - (r - t.floor) / (top - t.floor))
	end
	if r <= top + t.bank.width then
		return t.bank.height * share * math.sin(math.pi * (r - top) / t.bank.width)
	end
	return nil
end

-- The angle (degrees) a trench line bends at a joint: `ox, oz` out of the old block's end, `nx, nz` from the joint
-- into the new one (flat, unit). 0 is straight on.
function Build.bend(ox: number, oz: number, nx: number, nz: number): number
	return math.deg(math.acos(math.clamp(ox * nx + oz * nz, -1, 1)))
end

-- A 0..1 hash of a square's seed (the same on every run), `salt` picking which roll.
local function roll(seed: number, salt: number): number
	local x = math.sin(seed * 12.9898 + salt * 78.233) * 43758.5453
	return x - math.floor(x)
end

export type TrenchPieces = { walls: { number }, ends: { number }, floor: number, flip: boolean }

-- A trench square's dirt pieces (Config/Build.Trench.pieces `p`), rolled from its seed: the wall on each side (1 its
-- left, 2 its right), a plain wall for each dead end (1 end A, 2 end B), the floor, and whether the floor is laid
-- turned round. A side gets a wood wall (plank steps) at
-- `woodChance`, but not where the square before it in the run (`prevSeed`) rolled one on that side.
function Build.trenchPieces(seed: number, prevSeed: number?, p: any): TrenchPieces
	local plain, wood = {}, {}
	for i = 1, p.walls do
		table.insert(if table.find(p.wood, i) then wood else plain, i)
	end
	local walls = {}
	for side = 1, 2 do
		local isWood = roll(seed, side) < p.woodChance and not (prevSeed and roll(prevSeed, side) < p.woodChance)
		local from = if isWood then wood else plain
		walls[side] = from[math.floor(roll(seed, side + 2) * #from) + 1]
	end
	return {
		walls = walls,
		ends = { plain[math.floor(roll(seed, 7) * #plain) + 1], plain[math.floor(roll(seed, 8) * #plain) + 1] },
		floor = math.floor(roll(seed, 5) * p.floors) + 1,
		flip = roll(seed, 6) < 0.5,
	}
end

-- How deep a trench square is cut (0..1 of the full depth) at `hp`: while it's being dug, its HP's share; once it has
-- been dug full (`built`), full depth down to `h.hold`% HP, then buried with what's left.
function Build.trenchDepth(hp: number, built: boolean, h: any): number
	if built then
		return math.clamp(hp / (h.max * h.hold / 100), 0, 1)
	end
	return math.clamp(hp / h.max, 0, 1)
end

-- A square's HP after a swing: Build adds `swing` up to `max`, Destroy takes it off. Second: whether it's gone.
function Build.trenchSwing(hp: number, max: number, swing: number, build: boolean): (number, boolean)
	if build then
		return math.min(hp + swing, max), false
	end
	local left = hp - swing
	return math.max(left, 0), left <= 0
end

-- How far a blast `d` studs from a trench square's line counts as being from it (Config/Build.Trench.blast): inside the
-- trench, its distance past the floor's edge; in the zone of `zone` trench widths past the top edge, `edge`; further
-- out, `edge` plus how far past the zone.
function Build.trenchBlastDistance(d: number, t: any): number
	local top = Build.trenchTop(t)
	local B = t.blast
	if d <= top then
		return math.min(math.max(d - t.floor, 0), B.edge)
	end
	local zone = top + B.zone * 2 * top
	if d <= zone then
		return B.edge
	end
	return B.edge + (d - zone)
end

-- the HP a blast takes off a square (`b`: Config/Build.Trench.blast): none under `b.from` kPa at its line, rising with
-- the log of the pressure (to the power `b.curve`) to `b.cap` of `max` at `b.full`
function Build.trenchBlast(kpa: number, max: number, b: any): number
	if kpa <= b.from then
		return 0
	end
	local t = math.min(math.log(kpa / b.from) / math.log(b.full / b.from), 1)
	return max * b.cap * t ^ b.curve
end

-- Where a segment from (ax, az) to (bx, bz) runs inside a rectangle (centre cx, cz; unit axis ux, uz along it; half
-- sizes hu along and hv across): the share of the segment from 0 to 1 where it enters and leaves it, or nil.
function Build.clipRect(
	ax: number,
	az: number,
	bx: number,
	bz: number,
	cx: number,
	cz: number,
	ux: number,
	uz: number,
	hu: number,
	hv: number
): (number?, number?)
	-- the segment in the rectangle's own frame
	local function local2(x: number, z: number): (number, number)
		local dx, dz = x - cx, z - cz
		return dx * ux + dz * uz, -dx * uz + dz * ux
	end
	local pu, pv = local2(ax, az)
	local qu, qv = local2(bx, bz)
	local du, dv = qu - pu, qv - pv
	local t0, t1 = 0, 1
	for _, e in { { -du, pu + hu }, { du, hu - pu }, { -dv, pv + hv }, { dv, hv - pv } } do
		local p, q = e[1], e[2]
		if math.abs(p) < 1e-9 then
			if q < 0 then
				return nil, nil
			end
		else
			local r = q / p
			if p < 0 then
				t0 = math.max(t0, r)
			else
				t1 = math.min(t1, r)
			end
		end
	end
	if t0 > t1 then
		return nil, nil
	end
	return t0, t1
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

return Build
