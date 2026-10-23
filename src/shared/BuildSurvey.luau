--!strict
-- Where a player-built piece would go and whether it can (Config/Build, Rules/Build): the same survey on the client
-- (the build-mode ghost, src/client/Build) and the server (src/server/Build, which decides). Reads the world, so it
-- lives outside Rules.
--
-- A piece's frame: its centre on the ground, RightVector along its width, LookVector to its front. Laid pieces carry
-- attributes: "Piece" (Config/Build key), "Team", "Frame" (CFrame), "Size" (Vector3: width, height, depth). Trench
-- blocks (src/server/Trenches) carry "Kind" = "TrenchBlock", "Team", "BlockA" / "BlockB" (their ends on the ground),
-- "LinkA" / "LinkB" ("end", "tee" or "" for a dead end), "Work", "Need".

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local Rules = require(Shared.Rules.Build)

local Survey = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = false

-- a piece's footprint: width (along RightVector), height, depth (along LookVector)
function Survey.footprint(piece: Rules.Piece): Vector3
	if piece.kind == "Sandbags" then
		return Vector3.new(piece.width, piece.rows * piece.row, piece.depth)
	end
	return Vector3.new(piece.width, piece.height, piece.depth)
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

-- The ground under a piece's footprint: a grid of samples (5 along, 3 across)
function Survey.ground(piece: Rules.Piece, frame: CFrame): Report
	local size = Survey.footprint(piece)
	local cols, rows = 5, 3
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

-- the closest distance between a point and the segment a-b, flat
function Survey.toSegment(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

-- Whether a piece laid at `frame` (ground `low`) runs into anything standing over its footprint (buildings, trees,
-- props, other pieces, soldiers). Trench blocks don't count: sandbags and wire go on their banks. `ignore` is left out
-- of the search (the client's ghost).
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
		if (part.CanCollide or soldier) and not trench then
			return true
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
-- a free end of the team's trench within Trench.joinReach ("end"), onto a block's centre line when `p` is on its side
-- ("tee"), else where it is. Also the block it joins and, for an end, the way out of that end (flat unit).
function Survey.trenchSnap(folder: Instance?, team: string, p: Vector3): (Vector3, string?, Model?, Vector3?)
	if not folder then
		return p, nil, nil, nil
	end
	local T = C.Trench
	local top = Rules.trenchTop(T)
	local best: Model?, bestAt: Vector3?, bestOut: Vector3?, bestD = nil, nil, nil, T.joinReach
	for _, m in folder:GetChildren() do
		local a, b = m:GetAttribute("BlockA"), m:GetAttribute("BlockB")
		if m:IsA("Model") and m:GetAttribute("Team") == team and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
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
		if m:IsA("Model") and m:GetAttribute("Team") == team and typeof(a) == "Vector3" and typeof(b) == "Vector3" then
			local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local dir = flat.Unit
			local rel = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
			local u, v = rel:Dot(dir), rel:Dot(Vector3.new(-dir.Z, 0, dir.X))
			if u >= 0 and u <= flat.Magnitude and math.abs(v) <= top then
				return a:Lerp(b, u / flat.Magnitude), "tee", m, nil
			end
		end
	end
	return p, nil, nil, nil
end

return Survey
