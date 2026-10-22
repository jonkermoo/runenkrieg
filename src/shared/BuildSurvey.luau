--!strict
-- Where a player-built piece would go and whether it can (Config/Build, Rules/Build): the same survey on the client
-- (the build-mode ghost, src/client/Build) and the server (src/server/Build, which decides). Reads the world, so it
-- lives outside Rules.
--
-- A piece's frame: its centre on the ground, RightVector along its width (a trench's length, end A at -length/2, end
-- B at +length/2), LookVector to its front (the side it faces the enemy from). Laid pieces carry attributes: "Piece"
-- (Config/Build key), "Team", "Frame" (CFrame), "Size" (Vector3: width, height, depth), and trenches "EndA" / "EndB"
-- (Vector3 on the ground) and "OpenA" / "OpenB" (no other trench joined there).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local M = require(Shared.Config.Metrics)
local Rules = require(Shared.Rules.Build)

local Survey = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = false

-- a piece's footprint: width (along RightVector), height, depth (along LookVector), and its centre's offset to the
-- front from the frame (a trench's band runs from its back wall to its parapet)
function Survey.footprint(piece: Rules.Piece): (Vector3, number)
	if piece.kind == "Trench" then
		local T = C.Trench
		local back = T.back - T.cutMargin - T.parados.width
		local front = T.front + M.Trench.FirestepWidth + T.cutMargin + T.parapet.width
		return Vector3.new(T.length, M.Trench.Depth, front - back), (front + back) / 2
	elseif piece.kind == "Sandbags" then
		return Vector3.new(piece.width, piece.rows * piece.row, piece.depth), 0
	end
	return Vector3.new(piece.width, piece.height, piece.depth), 0
end

-- the frame flattened to a yaw at `at`
function Survey.frame(at: Vector3, look: Vector3): CFrame
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	return CFrame.lookAt(at, at + flat.Unit)
end

-- The trench ends of `team` no other trench has joined, as { model, end = "A" | "B", at }
function Survey.freeEnds(folder: Instance?, team: string): { { model: Model, which: string, at: Vector3 } }
	local out = {}
	if not folder then
		return out
	end
	for _, m in folder:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("Team") == team and m:GetAttribute("EndA") then
			for _, which in { "A", "B" } do
				local at = m:GetAttribute("End" .. which)
				if m:GetAttribute("Open" .. which) == true and typeof(at) == "Vector3" then
					table.insert(out, { model = m, which = which, at = at })
				end
			end
		end
	end
	return out
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- A trench frame moved so that one of its ends meets a free end of the team's trench within Config/Build.Trench.snap
-- (its yaw kept). Returns the frame and the joins: { A = free end?, B = free end? }.
function Survey.snap(folder: Instance?, team: string, frame: CFrame): (CFrame, { [string]: any })
	local half = C.Trench.length / 2
	local ends = Survey.freeEnds(folder, team)
	local best, bestD, mine = nil, C.Trench.snap, nil
	for _, e in ends do
		for _, which in { "A", "B" } do
			local p = frame.Position + frame.RightVector * (if which == "A" then -half else half)
			local d = flatDistance(p, e.at)
			if d < bestD then
				best, bestD, mine = e, d, which
			end
		end
	end
	local joins: { [string]: any } = {}
	if best and mine then
		local p = frame.Position + frame.RightVector * (if mine == "A" then -half else half)
		local shift = Vector3.new(best.at.X - p.X, 0, best.at.Z - p.Z)
		frame = frame + shift
		joins[mine] = best
		-- the other end may land on another free end too (closing a gap)
		local other = if mine == "A" then "B" else "A"
		local q = frame.Position + frame.RightVector * (if other == "A" then -half else half)
		for _, e in ends do
			if e ~= best and e.model ~= best.model and flatDistance(q, e.at) < C.Trench.snap * 0.5 then
				joins[other] = e
				break
			end
		end
	end
	return frame, joins
end

export type Report = {
	heights: { number },
	rows: number,
	dx: number,
	dz: number,
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

-- The ground under a piece's footprint: a grid of samples (5 along, 3 across)
function Survey.ground(piece: Rules.Piece, frame: CFrame): Report
	local size, offset = Survey.footprint(piece)
	local cols, rows = 5, 3
	local heights = {}
	local ground, water, low = true, false, math.huge
	for r = 1, rows do
		for c = 1, cols do
			local u = (c - 1) / (cols - 1) - 0.5
			local v = (r - 1) / (rows - 1) - 0.5
			local p = frame.Position + frame.RightVector * (u * size.X) + frame.LookVector * (offset + v * size.Z)
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
	local slope = Rules.steepest(heights, rows, size.X / (cols - 1), size.Z / (rows - 1))
	return {
		heights = heights,
		rows = rows,
		dx = size.X / (cols - 1),
		dz = size.Z / (rows - 1),
		ground = ground,
		water = water,
		slope = slope,
		low = if low == math.huge then frame.Position.Y else low,
		centre = centre,
	}
end

-- the closest distance between a point and the segment a-b, flat
local function toSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	return (ap - ab * t).Magnitude
end
Survey.toSegment = toSegment

-- Whether a piece laid at `frame` (ground `low`) runs into anything: parts standing over its footprint (buildings,
-- trees, props, other pieces, soldiers) or, for a trench, another trench it isn't joined to. `ignore` is left out of
-- the part search (the client's ghost).
function Survey.blocked(
	piece: Rules.Piece,
	frame: CFrame,
	low: number,
	folder: Instance?,
	joins: { [string]: any }?,
	ignore: { Instance }?
): boolean
	local size, offset = Survey.footprint(piece)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = { workspace.Terrain }
	for _, i in ignore or {} do
		table.insert(skip, i)
	end
	params.FilterDescendantsInstances = skip
	local tall = if piece.kind == "Trench" then 5 else size.Y
	local box = CFrame.fromMatrix(
		Vector3.new(frame.Position.X, low + 0.8 + tall / 2, frame.Position.Z) + frame.LookVector * offset,
		frame.RightVector,
		Vector3.yAxis
	)
	-- a trench's banks are wide: only its cut band has to be clear of parts
	local across = if piece.kind == "Trench" then C.Trench.front + M.Trench.FirestepWidth - C.Trench.back else size.Z
	for _, part in workspace:GetPartBoundsInBox(box, Vector3.new(size.X, tall, across), params) do
		local model = part:FindFirstAncestorWhichIsA("Model")
		local soldier = model and model:FindFirstChildOfClass("Humanoid") ~= nil
		if part.CanCollide or soldier then
			-- (a trench under laid sandbags or wire is fine: those are checked from their side)
			if not (piece.kind == "Trench" and folder and part:IsDescendantOf(folder)) then
				return true
			end
		end
	end
	if piece.kind ~= "Trench" or not folder then
		return false
	end
	-- other trenches: no closer than the cut band's width, except next to the end it joins
	local half = C.Trench.length / 2
	local a = frame.Position - frame.RightVector * half
	local b = frame.Position + frame.RightVector * half
	local width = C.Trench.front + M.Trench.FirestepWidth - C.Trench.back
	for _, m in folder:GetChildren() do
		local ea, eb = m:GetAttribute("EndA"), m:GetAttribute("EndB")
		if m:IsA("Model") and typeof(ea) == "Vector3" and typeof(eb) == "Vector3" then
			for i = 0, 8 do
				local p = a:Lerp(b, i / 8)
				local nearJoin = false
				for _, j in joins or {} do
					if j.model == m and flatDistance(p, j.at) < width + C.Trench.overlap then
						nearJoin = true
					end
				end
				if not nearJoin and toSegment(p, ea, eb) < width then
					return true
				end
			end
		end
	end
	return false
end

-- how far `p` is from a laid piece (flat): from a trench's centre line, or from the edge of another piece's box
function Survey.distanceTo(model: Instance, p: Vector3): number
	local ea, eb = model:GetAttribute("EndA"), model:GetAttribute("EndB")
	if typeof(ea) == "Vector3" and typeof(eb) == "Vector3" then
		return toSegment(p, ea, eb)
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

return Survey
