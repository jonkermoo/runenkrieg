--!strict
-- Where a player-built piece would go and whether it can (Config/Build, Rules/Build): the same survey on the client
-- (the build-mode ghost, src/client/Build) and the server (src/server/Build, which decides). Reads the world, so it
-- lives outside Rules.
--
-- A piece's frame: its centre on the ground, RightVector along its width, LookVector to its front. Laid pieces carry
-- attributes: "Piece" (Config/Build key), "Team", "Frame" (CFrame), "Size" (Vector3: width, height, depth). Trench
-- blocks (src/server/Trenches) carry "Kind" = "TrenchBlock", "Team", "BlockA" / "BlockB" (their ends on the ground),
-- "Tilt" (the ground's rise per stud across them), "LinkA" / "LinkB" ("end", "tee" or "" for a dead end), "Work", "Need". A gun piece's "Frame" is its footprint's
-- centre (Survey.box); "At" (CFrame) is the gun itself, on the ground, looking out along the muzzle. A bridge's "Frame"
-- is its trench square's centre on the ground, RightVector along the trench, LookVector across it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local ArtilleryCfg = require(Shared.Config.Artillery)
local TreeCfg = require(Shared.Config.TreeSway)
local Rules = require(Shared.Rules.Build)

local Survey = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = false

-- a piece's footprint: width (along RightVector), height, depth (along LookVector)
function Survey.footprint(piece: Rules.Piece): Vector3
	return Vector3.new(piece.width, piece.height, piece.depth)
end

-- the centre of a piece's footprint laid at `frame` (a gun's lies `back` studs behind it)
function Survey.box(piece: Rules.Piece, frame: CFrame): CFrame
	return frame * CFrame.new(0, 0, piece.back or 0)
end

-- the frame flattened to a yaw at `at`
function Survey.frame(at: Vector3, look: Vector3): CFrame
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(at, at + flat.Unit)
end

export type Report = {
	heights: { number },
	ground: boolean,
	water: boolean,
	slope: number,
	low: number, -- the lowest ground under it
	centre: number, -- the ground height at the frame
}

-- the terrain's height under (x, z), whether it was water there, or nil
function Survey.groundAt(x: number, z: number, near: number): (number?, boolean)
	local hit = workspace:Raycast(Vector3.new(x, near + 60, z), Vector3.new(0, -160, 0), terrainOnly)
	if not hit then
		return nil, false
	end
	return hit.Position.Y, hit.Material == Enum.Material.Water
end

-- The ground under a piece's footprint: a grid of samples, COLS along, ROWS across
local COLS, ROWS = 5, 3
function Survey.ground(piece: Rules.Piece, frame: CFrame): Report
	local size = Survey.footprint(piece)
	local cols, rows = COLS, ROWS
	local heights = {}
	local ground, water, low = true, false, math.huge
	for r = 1, rows do
		for c = 1, cols do
			local u = (c - 1) / (cols - 1) - 0.5
			local v = (r - 1) / (rows - 1) - 0.5
			local p = frame.Position + frame.RightVector * (u * size.X) + frame.LookVector * (v * size.Z)
			local h, wet = Survey.groundAt(p.X, p.Z, frame.Position.Y)
			if h then
				table.insert(heights, h)
				low = math.min(low, h)
			else
				ground = false
				table.insert(heights, frame.Position.Y)
			end
			water = water or wet
		end
	end
	local centre = Survey.groundAt(frame.Position.X, frame.Position.Z, frame.Position.Y) or frame.Position.Y
	return {
		heights = heights,
		ground = ground,
		water = water,
		slope = Rules.steepest(heights, rows, size.X / (cols - 1), size.Z / (rows - 1)),
		low = if low == math.huge then frame.Position.Y else low,
		centre = centre,
	}
end

-- A piece's frame laid on the ground under it (`report`, from Survey.ground at `frame`): at the plane that best fits
-- the ground there (Rules.groundPlane), tilted with it, its yaw kept (user round 7: "make sure the sandbags and barbed
-- wires are build according to the terrain, not flat everytime")
function Survey.onGround(piece: Rules.Piece, frame: CFrame, report: Report): CFrame
	local size = Survey.footprint(piece)
	local h, gx, gz = Rules.groundPlane(report.heights, ROWS, COLS, size.X, size.Z)
	local right = frame.RightVector + Vector3.yAxis * gx
	local look = frame.LookVector + Vector3.yAxis * gz
	local up = right:Cross(look).Unit
	return CFrame.fromMatrix(Vector3.new(frame.Position.X, h, frame.Position.Z), right.Unit, up)
end

-- How a piece with a `lay` (a gun, an MG nest: Config/Build.Slope, Rules.slopeLay) lies on the ground under it
-- (`report`, from Survey.ground at `frame`, its footprint's centre): the plane it is laid on, through the fitted
-- ground's height at its centre and tilted down the same slope by its tilt, and that tilt in degrees and the degrees
-- the earth takes out; nil when the slope is past its `maxSlope`. A piece without a `lay`: level, as `frame`.
function Survey.lay(piece: Rules.Piece, frame: CFrame, report: Report): (CFrame?, number, number)
	local size = Survey.footprint(piece)
	local h, gx, gz = Rules.groundPlane(report.heights, ROWS, COLS, size.X, size.Z)
	local level = CFrame.new(frame.Position.X, h, frame.Position.Z) * frame.Rotation
	local lay = piece.lay
	if not lay then
		return level, 0, 0
	end
	local tilt, cut = Rules.slopeLay(Rules.planeSlope(gx, gz), lay, piece.maxSlope or 90)
	if not tilt then
		return nil, 0, 0
	end
	local tx, tz = Rules.layPlane(gx, gz, tilt)
	local right = frame.RightVector + Vector3.yAxis * tx
	local up = right:Cross(frame.LookVector + Vector3.yAxis * tz).Unit
	return CFrame.fromMatrix(level.Position, right.Unit, up), tilt, cut
end

-- the closest distance between a point and the segment a-b, flat
function Survey.toSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

-- Whether a standing tree is too near a trench run from `a` to `b` (Rules.treeTooNear): its trunk (the "Trunk" of a
-- tree tagged TreeCfg.Tag) by its pivot, at the trunk's widest
function Survey.treeNear(a: Vector3, b: Vector3): boolean
	local T = C.Trench
	local reach = Rules.trenchTop(T) + T.joins.heapReach + T.treeClear + 4
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local mid = (a + b) / 2
	local box = if flat.Magnitude > 1e-3 then CFrame.lookAt(mid, mid + flat) else CFrame.new(mid)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { workspace.Terrain }
	for _, part in workspace:GetPartBoundsInBox(box, Vector3.new(2 * reach, 200, flat.Magnitude + 2 * reach), params) do
		local tree = part.Parent
		if part.Name == "Trunk" and tree and tree:IsA("Model") and CollectionService:HasTag(tree, TreeCfg.Tag) then
			local at = tree:GetPivot().Position
			if Rules.treeTooNear(a.X, a.Z, b.X, b.Z, at.X, at.Z, math.max(part.Size.X, part.Size.Z), T) then
				return true
			end
		end
	end
	return false
end

-- Whether a piece laid at `frame` (ground `low`) runs into anything standing over its footprint (buildings, trees,
-- props, other pieces, soldiers). Trench blocks don't count: sandbags and wire go on their banks (their open cut:
-- Survey.overTrench). `ignore` is left out
-- of the search (the builder, the client's ghost). Soldiers don't stop a gun (its ground is wide: they step aside or
-- fall in its pit). Round the footprint, `C.Margin` out and from the ground up, anything solid that isn't a soldier,
-- a piece or a trench stops it too (pieces go by footprint: Survey.onPiece).
function Survey.blocked(piece: Rules.Piece, frame: CFrame, low: number, ignore: { Instance }?): boolean
	local size = Survey.footprint(piece)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { workspace.Terrain }
	for _, i in ignore or {} do
		table.insert(skip, i)
	end
	params.FilterDescendantsInstances = skip
	local box = CFrame.fromMatrix(
		Vector3.new(frame.Position.X, low + 0.8 + size.Y / 2, frame.Position.Z),
		frame.RightVector,
		Vector3.yAxis
	)
	for _, part in workspace:GetPartBoundsInBox(box, size, params) do
		local model = part:FindFirstAncestorWhichIsA("Model")
		local soldier = model and model:FindFirstChildOfClass("Humanoid") ~= nil
		local trench = model and model:GetAttribute("Kind") == "TrenchBlock"
		local stops = if soldier then piece.kind ~= "Gun" else part.CanCollide
		if stops and not trench then
			return true
		end
	end
	local structures = workspace:FindFirstChild(C.Folder)
	if structures then
		table.insert(skip, structures)
	end
	params.FilterDescendantsInstances = skip
	local m = C.Margin
	local around = CFrame.fromMatrix(
		Vector3.new(frame.Position.X, low + (0.8 + size.Y) / 2, frame.Position.Z),
		frame.RightVector,
		Vector3.yAxis
	)
	for _, part in
		workspace:GetPartBoundsInBox(around, Vector3.new(size.X + 2 * m, 0.8 + size.Y, size.Z + 2 * m), params)
	do
		local model = part:FindFirstAncestorWhichIsA("Model")
		if part.CanCollide and not (model and model:FindFirstChildOfClass("Humanoid")) then
			return true
		end
	end
	return false
end

-- Whether a piece laid with its footprint at `box` (Survey.box) overlaps another piece's in `structures` (their "Frame"
-- and "Size" attributes; trench blocks have none: Survey.nearTrench). The pieces are checked by footprint, not parts:
-- a wire's parts don't collide, so Survey.blocked never sees one (user 2026-10-27: "it should not be able to be placed
-- on top of each other or on top of any other strucuter"). `skip`: a piece left out.
function Survey.onPiece(piece: Rules.Piece, box: CFrame, structures: Instance?, skip: Instance?): boolean
	local size = Survey.footprint(piece)
	local mine: Rules.Footprint = {
		x = box.Position.X,
		z = box.Position.Z,
		rx = box.RightVector.X,
		rz = box.RightVector.Z,
		width = size.X,
		depth = size.Z,
	}
	for _, m in (if structures then structures:GetChildren() else {}) do
		local frame, other = m:GetAttribute("Frame"), m:GetAttribute("Size")
		if m ~= skip and typeof(frame) == "CFrame" and typeof(other) == "Vector3" then
			local theirs: Rules.Footprint = {
				x = frame.Position.X,
				z = frame.Position.Z,
				rx = frame.RightVector.X,
				rz = frame.RightVector.Z,
				width = other.X,
				depth = other.Z,
			}
			if Rules.footprintsOverlap(mine, theirs) then
				return true
			end
		end
	end
	return false
end

-- Whether a gun piece laid with its gun at `at` comes too close to another gun (Rules.gunsClear): the guns standing
-- in Config/Artillery.Folder ("Gun" their Config/Artillery key) and the gun pieces laid in `structures` ("At").
-- `skip`: a gun piece left out (the client's own).
function Survey.gunGap(piece: Rules.Piece, at: Vector3, structures: Instance?, skip: Instance?): boolean
	local function clash(gun: any, p: Vector3): boolean
		local other: any = nil
		for _, q in C.Pieces do
			if q.kind == "Gun" and q.gun == gun then
				other = q
			end
		end
		local d = Vector3.new(p.X - at.X, 0, p.Z - at.Z).Magnitude
		return not Rules.gunsClear(d, gun == piece.gun, piece.spacing, piece.clear, if other then other.clear else 0)
	end
	local guns = workspace:FindFirstChild(ArtilleryCfg.Folder)
	for _, m in (if guns then guns:GetChildren() else {}) do
		if m:IsA("Model") and m:GetAttribute("Gun") ~= nil and clash(m:GetAttribute("Gun"), m:GetPivot().Position) then
			return true
		end
	end
	for _, m in (if structures then structures:GetChildren() else {}) do
		local p = Rules.piece(m:GetAttribute("Piece"), C.Pieces)
		local spot = m:GetAttribute("At")
		-- (a standing built gun is in the Artillery folder as well: the same spot, the same verdict)
		if m ~= skip and p and p.kind == "Gun" and typeof(spot) == "CFrame" and clash(p.gun, spot.Position) then
			return true
		end
	end
	return false
end

-- Whether a trench (any block in `structures`, planned or dug) runs within Rules.trenchKeep of the footprint of a
-- `piece` at `box` (Survey.box): from the trench's line, its half width over the walls and its bank, a gun's gap more.
-- False for a piece that may stand on a bank.
function Survey.nearTrench(piece: Rules.Piece, box: CFrame, structures: Instance?): boolean
	local reach = Rules.trenchKeep(piece, C.Trench)
	if not reach then
		return false
	end
	local hx, hz = piece.width / 2, piece.depth / 2
	for _, m in (if structures then structures:GetChildren() else {}) do
		local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			local steps = math.max(math.ceil((b - a).Magnitude), 1)
			for i = 0, steps do
				local l = box:PointToObjectSpace(a:Lerp(b, i / steps))
				local dx = math.max(math.abs(l.X) - hx, 0)
				local dz = math.max(math.abs(l.Z) - hz, 0)
				if dx * dx + dz * dz < reach * reach then
					return true
				end
			end
		end
	end
	return false
end

-- The name of the first piece in `structures` a trench run from `a` to `b` would come nearer than its
-- Rules.trenchKeep (a foxhole, wire or a gun keeps the trench off as it keeps off trenches), nil when none
function Survey.nearPieces(a: Vector3, b: Vector3, structures: Instance?): string?
	for _, m in (if structures then structures:GetChildren() else {}) do
		local p = Rules.piece(m:GetAttribute("Piece"), C.Pieces)
		local frame, size = m:GetAttribute("Frame"), m:GetAttribute("Size")
		local keep = p and Rules.trenchKeep(p, C.Trench)
		if p and keep and typeof(frame) == "CFrame" and typeof(size) == "Vector3" then
			local f: Rules.Footprint = {
				x = frame.Position.X,
				z = frame.Position.Z,
				rx = frame.RightVector.X,
				rz = frame.RightVector.Z,
				width = size.X,
				depth = size.Z,
			}
			if Rules.footprintToSeg(f, a.X, a.Z, b.X, b.Z, 1) < keep then
				return p.name
			end
		end
	end
	return nil
end

-- Whether a piece laid with its footprint at `box` (Survey.box) reaches over a trench square's open cut (Rules.trenchCut:
-- its top edges less Trench.overhang), dug or only planned: any block in `structures`. Its bank is fine.
function Survey.overTrench(piece: Rules.Piece, box: CFrame, structures: Instance?): boolean
	local size = Survey.footprint(piece)
	local mine: Rules.Footprint = {
		x = box.Position.X,
		z = box.Position.Z,
		rx = box.RightVector.X,
		rz = box.RightVector.Z,
		width = size.X,
		depth = size.Z,
	}
	local half = Rules.trenchTop(C.Trench) - C.Trench.overhang
	for _, m in (if structures then structures:GetChildren() else {}) do
		local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
		if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			if Rules.footprintsOverlap(mine, Rules.trenchCut(a.X, a.Z, b.X, b.Z, half)) then
				return true
			end
		end
	end
	return false
end

-- how far `p` is from a laid piece (flat): from a trench block's line, or from the edge of another piece's box
function Survey.distanceTo(model: Instance, p: Vector3): number
	local a, b = model:GetAttribute("BlockA"), model:GetAttribute("BlockB")
	if typeof(a) == "Vector3" and typeof(b) == "Vector3" then
		return Survey.toSegment(p, a, b)
	end
	local frame, size = model:GetAttribute("Frame"), model:GetAttribute("Size")
	if typeof(frame) ~= "CFrame" or typeof(size) ~= "Vector3" then
		return math.huge
	end
	local l = frame:PointToObjectSpace(p)
	local dx = math.max(math.abs(l.X) - size.X / 2, 0)
	local dz = math.max(math.abs(l.Z) - size.Z / 2, 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- For the trench planner's ghost: where a plan's end at `p` would go, as the server snaps it (src/server/Trenches): onto
-- a free end of any trench within Trench.joinReach ("end"), onto a block's floor edge on the side `p` is on
-- ("tee"), else where it is. Also the block it joins and, for an end, the way out of that end (flat unit).
function Survey.trenchSnap(folder: Instance?, _team: string, p: Vector3): (Vector3, string?, Model?, Vector3?)
	if not folder then
		return p, nil, nil, nil
	end
	local T = C.Trench
	local top = Rules.trenchTop(T)
	local best: Model?, bestAt: Vector3?, bestOut: Vector3?, bestD = nil, nil, nil, T.joinReach
	for _, m in folder:GetChildren() do
		local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
		if m:IsA("Model") and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
			for _, e in { { a, m:GetAttribute("LinkA"), -dir }, { b, m:GetAttribute("LinkB"), dir } } do
				local d = Vector3.new(p.X - e[1].X, 0, p.Z - e[1].Z).Magnitude
				if (e[2] == nil or e[2] == "") and d < bestD then
					best, bestAt, bestOut, bestD = m, e[1], e[3], d
				end
			end
		end
	end
	if best and bestAt then
		return bestAt, "end", best, bestOut
	end
	for _, m in folder:GetChildren() do
		local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
		if m:IsA("Model") and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local dir = flat.Unit
			local rel = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
			local u, v = rel:Dot(dir), rel:Dot(Vector3.new(-dir.Z, 0, dir.X))
			if u >= 0 and u <= flat.Magnitude and math.abs(v) <= top then
				-- at its floor's edge on that side (Trenches.snap)
				local side = Vector3.new(-dir.Z, 0, dir.X) * (if v >= 0 then T.floor else -T.floor)
				return a:Lerp(b, u / flat.Magnitude) + side, "tee", m, nil
			end
		end
	end
	return p, nil, nil, nil
end

-- The trench square a bridge laid at `p` would go on (Config/Build.Bridge, Rules.bridgeSpot): the block in `structures`
-- whose line `p` is nearest, within its top width, and what decides it: its HP, its ends and how straight they run on,
-- whether a trench tees into its side, how far the nearest other bridge is (`skip` left out). Also the bridge's frame
-- (see the header), the square's length and its model, when there is a square.
function Survey.bridgeSpot(
	structures: Instance?,
	p: Vector3,
	skip: Instance?
): (Rules.BridgeSpot, CFrame?, number?, Model?)
	local spot: Rules.BridgeSpot =
		{ found = false, dug = 0, ends = { "", "" }, bends = { 0, 0 }, teed = false, nearest = math.huge }
	if not structures then
		return spot, nil, nil, nil
	end
	local T = C.Trench
	local blocks: { { m: Model, a: Vector3, b: Vector3 } } = {}
	local best, bestD = nil, Rules.trenchTop(T)
	for _, m in structures:GetChildren() do
		local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
		if m:IsA("Model") and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			local blk = { m = m, a = a, b = b }
			table.insert(blocks, blk)
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local u = Vector3.new(p.X - a.X, 0, p.Z - a.Z):Dot(flat.Unit)
			local d = Survey.toSegment(p, a, b)
			if d < bestD and u >= 0 and u <= flat.Magnitude then
				best, bestD = blk, d
			end
		end
	end
	if not best then
		return spot, nil, nil, nil
	end
	local m, a, b = best.m, best.a, best.b
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local dir = flat.Unit
	spot.found = true
	local hp, max = m:GetAttribute("HP"), m:GetAttribute("MaxHP")
	spot.dug = if type(hp) == "number" and type(max) == "number" and max > 0 then hp / max * 100 else 0
	for i, e in { { a, m:GetAttribute("LinkA") }, { b, m:GetAttribute("LinkB") } } do
		spot.ends[i] = if type(e[2]) == "string" then e[2] else ""
		if spot.ends[i] == "end" then
			-- the square joined there: the one with an end on this one's
			for _, o in blocks do
				if o.m ~= m and ((o.a - e[1]).Magnitude < 0.5 or (o.b - e[1]).Magnitude < 0.5) then
					local od = Vector3.new(o.b.X - o.a.X, 0, o.b.Z - o.a.Z).Unit
					spot.bends[i] = math.deg(math.acos(math.clamp(math.abs(od:Dot(dir)), 0, 1)))
				end
			end
		end
	end
	-- another trench teed into its side: an end of another block marked "tee" on this one's floor edge
	for _, o in blocks do
		if o.m ~= m then
			for _, e in { { o.a, o.m:GetAttribute("LinkA") }, { o.b, o.m:GetAttribute("LinkB") } } do
				if e[2] == "tee" and Survey.toSegment(e[1], a, b) < T.floor + 1 then
					spot.teed = true
				end
			end
		end
	end
	local centre = (a + b) / 2
	for _, o in structures:GetChildren() do
		local frame = o:GetAttribute("Frame")
		local piece = Rules.piece(o:GetAttribute("Piece"), C.Pieces)
		if o ~= skip and piece and piece.kind == "Bridge" and typeof(frame) == "CFrame" then
			local d = Vector3.new(frame.Position.X - centre.X, 0, frame.Position.Z - centre.Z).Magnitude
			spot.nearest = math.min(spot.nearest, d)
		end
	end
	-- (along the trench's own slope, end to end: user round 7, "make it be parallel to the surface of the trench its on")
	-- (and across with the square's tilt, "Tilt": user 2026-11-02, trenches follow the slope)
	local along = (b - a).Unit
	local tilt = m:GetAttribute("Tilt")
	local side = Vector3.new(-dir.Z, if type(tilt) == "number" then tilt else 0, dir.X).Unit
	local up = side:Cross(along).Unit
	return spot, CFrame.fromMatrix(centre, along, up), (b - a).Magnitude, m
end

-- The middle of a dugout's footprint, its steps and room, laid at `frame` (Survey.dugoutSpot), on the trench floor;
-- its size: Vector3(width, height, its steps' run plus its depth)
function Survey.dugoutBox(piece: Rules.Piece, frame: CFrame): (CFrame, Vector3)
	local run = C.Dugout.stair + piece.depth
	return frame * CFrame.new(0, 0, run / 2), Vector3.new(piece.width, piece.height, run)
end

-- The trench square wall a dugout laid at `p` would go in (Config/Build.Dugout, Rules.dugoutSpot): the block in
-- `structures` whose line `p` is nearest (within its wall tops and Dugout.reach past them, along it), the wall on the
-- side `p` is on, and what decides it: its HP and length, whether a trench tees into that wall, a bridge on it, how far
-- the nearest other dugout's doorway is and whether its room clashes with this one's (Rules.dugoutClash; `skip` left
-- out). Also the dugout's frame when there is a square: the square's floor at the foot of that wall, in its middle
-- along it, level, LookVector out into the trench (its Config/Assets pieces' space: +Z back into the wall); and the
-- square's model. (A laid dugout's "Frame" is the middle of its footprint, steps and room: Survey.dugoutBox.)
function Survey.dugoutSpot(structures: Instance?, p: Vector3, skip: Instance?): (Rules.DugoutSpot, CFrame?, Model?)
	local spot: Rules.DugoutSpot =
		{ found = false, dug = 0, length = 0, teed = false, bridge = false, nearest = math.huge }
	if not structures then
		return spot, nil, nil
	end
	local T, D = C.Trench, C.Dugout
	local piece = Rules.piece("Dugout", C.Pieces) :: Rules.Piece
	local top = Rules.trenchTop(T)
	local best: Model?, bestD = nil, top + D.reach
	for _, m in structures:GetChildren() do
		local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
		if m:IsA("Model") and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local u = Vector3.new(p.X - a.X, 0, p.Z - a.Z):Dot(flat.Unit)
			local d = Survey.toSegment(p, a, b)
			if d < bestD and u >= 0 and u <= flat.Magnitude then
				best, bestD = m, d
			end
		end
	end
	if not best then
		return spot, nil, nil
	end
	local m = best
	local a, b = m:GetAttribute("BlockA") :: Vector3, m:GetAttribute("BlockB") :: Vector3
	local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	local across = Vector3.new(-dir.Z, 0, dir.X) -- (src/server/Trenches: a block's right)
	local side = if Vector3.new(p.X - a.X, 0, p.Z - a.Z):Dot(across) >= 0 then 1 else -1
	spot.found = true
	spot.length = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
	local hp, max = m:GetAttribute("HP"), m:GetAttribute("MaxHP")
	spot.dug = if type(hp) == "number" and type(max) == "number" and max > 0 then hp / max * 100 else 0
	-- another trench teed into that wall: an end of another block marked "tee" on this one's floor edge on that side
	local mid = (a + b) / 2
	for _, o in structures:GetChildren() do
		local oa, ob = o:GetAttribute("BlockA"), o:GetAttribute("BlockB")
		if o ~= m and typeof(oa) == "Vector3" and typeof(ob) == "Vector3" then
			for _, e in { { oa, o:GetAttribute("LinkA") }, { ob, o:GetAttribute("LinkB") } } do
				local at = e[1] :: Vector3
				local onSide = Vector3.new(at.X - mid.X, 0, at.Z - mid.Z):Dot(across) * side > 0
				if e[2] == "tee" and onSide and Survey.toSegment(at, a, b) < T.floor + D.teeGap then
					spot.teed = true
				end
			end
		end
	end
	-- the square's floor at the foot of that wall (Trenches' floorAt: its cross-section turned by its tilt)
	local tilt = m:GetAttribute("Tilt")
	local t = if type(tilt) == "number" then tilt else 0
	local c = 1 / math.sqrt(1 + t * t)
	local outT = across * c + Vector3.yAxis * t * c
	local upT = Vector3.yAxis * c - across * t * c
	local foot = mid + outT * (side * T.floor) - upT * T.depth
	local frame = CFrame.lookAt(foot, foot - across * side)
	-- (another dugout's "Frame" is the middle of its box: its wall foot is back out of it along its run)
	local function feet(f: CFrame): any
		return { x = f.Position.X, y = f.Position.Y, z = f.Position.Z, rx = f.RightVector.X, rz = f.RightVector.Z }
	end
	local mine = feet(frame)
	for _, o in structures:GetChildren() do
		local f = o:GetAttribute("Frame")
		local q = Rules.piece(o:GetAttribute("Piece"), C.Pieces)
		if o ~= skip and q and typeof(f) == "CFrame" then
			if q.kind == "Dugout" then
				local its = f * CFrame.new(0, 0, -(D.stair + piece.depth) / 2)
				local d = Vector3.new(its.X - frame.X, 0, its.Z - frame.Z).Magnitude
				spot.nearest = math.min(spot.nearest, d)
				spot.clash = spot.clash or Rules.dugoutClash(mine, feet(its), piece, D)
			elseif
				q.kind == "Bridge"
				and Vector3.new(f.Position.X - mid.X, 0, f.Position.Z - mid.Z).Magnitude < D.bridgeGap
			then
				spot.bridge = true
			end
		end
	end
	return spot, frame, m
end

return Survey
