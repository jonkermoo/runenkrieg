--!strict
-- Player building on the server (phase 4.4 stage 1; Config/Build, Rules/Build, shared/BuildSurvey). The client lays a
-- blueprint (Net "Build" "Place": the piece and where); the server snaps it, surveys the ground, checks the rules and
-- the caps, and lays it in Workspace[Config/Build.Folder]. Every shovel swing at a piece (Net "Build" "Work") adds a
-- unit of work for its own team and takes one off for another; the piece rises in stages as it is worked and is torn
-- down at 0 (a trench filled in). A blueprint nobody works on goes after Config/Build.BlueprintLife.
-- - Trenches are cut into the terrain, voxel by voxel, from the ground as it was before any trench touched it (kept
--   per voxel), so joining, caving in and filling are all the same reshape of the live trenches over the ground.
--   When done, plank revetments and a firestep go in: Wood sections (src/server/Destruction breaks them).
-- - Sandbag walls: a section of class "Sandbag" per column of bags, the rows filling in as it is worked.
-- - Barbed wire: pickets and strands nothing queries (bullets pass); src/server/Wire slows and hurts soldiers in it.
-- Build.blast (from src/server/Damage.blast): a big enough blast caves a trench in round it and cuts wire.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local D = require(Shared.Config.Destruction)
local M = require(Shared.Config.Metrics)
local Palette = require(Shared.Config.Palette)
local ShovelCfg = require(Shared.Config.Shovel)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Build)
local Survey = require(Shared.BuildSurvey)
local Net = require(Shared.Net)

local Build = {}

local VOXEL = 4
local T = C.Trench

type Rec = {
	model: Model,
	piece: Rules.Piece,
	team: string,
	owner: number,
	work: number,
	need: number,
	built: boolean, -- has stood once (a trench keeps its full depth until torn down)
	born: number,
	worked: number,
	frame: CFrame,
	-- trenches
	a: number?, -- end node ids
	b: number?,
	floorA: number?, -- the ground line's height at each end
	floorB: number?,
	caved: { { at: Vector3, r: number } }?,
}

local recs: { [Model]: Rec } = {}
local lastSwing: { [Player]: number } = {}
-- trench end nodes: where they are, their ground height
local nodes: { [number]: { at: Vector3 } } = {}
local nextNode = 0
-- the ground before any trench: per voxel ("x,y,z" in voxel units), { occupancy, material }
local original: { [string]: { o: number, m: Enum.Material } } = {}

local function rgb(c: { number }, jitter: number?): Color3
	local k = 1 + (jitter or 0)
	return Color3.fromRGB(math.clamp(c[1] * k, 0, 255), math.clamp(c[2] * k, 0, 255), math.clamp(c[3] * k, 0, 255))
end

local function folder(): Folder
	local f = workspace:FindFirstChild(C.Folder)
	if not f then
		f = Instance.new("Folder")
		f.Name = C.Folder
		f.Parent = workspace
	end
	return f :: Folder
end

local function teamOf(character: Model): string?
	local kit = character:GetAttribute("Kit")
	return if type(kit) == "string" then kit else nil
end

local function holdsShovel(character: Model): boolean
	local tool = character:FindFirstChildOfClass("Tool")
	local name = tool and tool:GetAttribute("Weapon")
	return type(name) == "string" and W[name] ~= nil and W[name].class == "Shovel"
end

local function refuse(player: Player, reason: string)
	Net.event("Build"):FireClient(player, "Refused", reason)
end

-- the trench line's ends (on the ground) and its unit direction, flat
local function ends(r: Rec): (Vector3, Vector3)
	local half = T.length / 2
	local a = r.frame.Position - r.frame.RightVector * half
	local b = r.frame.Position + r.frame.RightVector * half
	return Vector3.new(a.X, r.floorA or a.Y, a.Z), Vector3.new(b.X, r.floorB or b.Y, b.Z)
end

local function uses(id: number?): number
	local n = 0
	for _, r in recs do
		if id and (r.a == id or r.b == id) then
			n += 1
		end
	end
	return n
end

local function trenchSegment(r: Rec): Rules.Segment
	local share = if r.built then 1 else Rules.stageOf(r.work, r.need, T.stages) / T.stages
	return {
		length = T.length,
		depth = M.Trench.Depth * share,
		share = share,
		openA = uses(r.a) <= 1,
		openB = uses(r.b) <= 1,
		exit = r.piece.exit == true,
	}
end

local function publishEnds(r: Rec)
	local a, b = ends(r)
	r.model:SetAttribute("EndA", a)
	r.model:SetAttribute("EndB", b)
	r.model:SetAttribute("OpenA", uses(r.a) <= 1)
	r.model:SetAttribute("OpenB", uses(r.b) <= 1)
end

-- Reshapes the terrain round `centre` (within `reach`, flat) to the ground before any trench, cut and banked by every
-- live trench there. Only voxels some trench ever touched go back; the rest stay as they are (craters, other digs).
local function reshape(centre: Vector3, reach: number)
	local terrain = workspace.Terrain
	local half = Vector3.new(reach, M.Trench.Depth + T.parapet.height + VOXEL * 4, reach)
	local region = Region3.new(centre - half, centre + half):ExpandToGrid(VOXEL)
	local ok, mats, occs = pcall(terrain.ReadVoxels, terrain, region, VOXEL)
	if not ok then
		return
	end
	local size = mats.Size
	local corner = region.CFrame.Position - region.Size / 2
	-- (whole voxel numbers: the region is on the grid)
	local gx, gy, gz = math.round(corner.X / VOXEL), math.round(corner.Y / VOXEL), math.round(corner.Z / VOXEL)
	-- the live trenches that can reach this region
	local near = {}
	for _, r in recs do
		if r.piece.kind == "Trench" and (r.frame.Position - centre).Magnitude <= reach + T.length + T.ramp.length then
			local a, b = ends(r)
			table.insert(near, { r = r, seg = trenchSegment(r), a = a, b = b })
		end
	end
	local fw = M.Trench.FirestepWidth
	for ix = 1, size.X do
		for iz = 1, size.Z do
			local x, z = corner.X + (ix - 0.5) * VOXEL, corner.Z + (iz - 0.5) * VOXEL
			-- the column back to the ground before any trench (where one touched it)
			local column = table.create(size.Y, 0)
			for iy = 1, size.Y do
				local key = `{gx + ix - 1},{gy + iy - 1},{gz + iz - 1}`
				local o = original[key]
				if o then
					occs[ix][iy][iz] = o.o
					mats[ix][iy][iz] = o.m
				end
				column[iy] = occs[ix][iy][iz]
			end
			-- what the trenches want here: the deepest cut wins, else the highest bank
			local cut: number? = nil
			local bank: number? = nil
			local top = Rules.columnTop(column, corner.Y, VOXEL)
			for _, n in near do
				local r: Rec = n.r
				local p = Vector3.new(x, 0, z)
				local rel = p - Vector3.new(n.a.X, 0, n.a.Z)
				local u = rel:Dot(r.frame.RightVector)
				local v = rel:Dot(r.frame.LookVector)
				local caved = false
				for _, cv in r.caved or {} do
					if Vector3.new(x - cv.at.X, 0, z - cv.at.Z).Magnitude <= cv.r then
						caved = true
					end
				end
				local h, _cutOnly = Rules.trenchAt(u, v, n.seg, T, fw)
				if h and not caved then
					-- the ground line between the ends (on past them for ramps and joins)
					local line = n.a.Y + (n.b.Y - n.a.Y) * math.clamp(u / T.length, -1, 2)
					if h < 0 then
						local want = line + h
						cut = if cut then math.min(cut, want) else want
					elseif top then
						local want = top + h
						bank = if bank then math.max(bank, want) else want
					end
				end
			end
			if cut or bank then
				-- keep the ground as it was before we change it
				for iy = 1, size.Y do
					local key = `{gx + ix - 1},{gy + iy - 1},{gz + iz - 1}`
					if not original[key] then
						original[key] = { o = occs[ix][iy][iz], m = mats[ix][iy][iz] }
					end
				end
				if cut then
					local out = Rules.shapeColumn(column, corner.Y, VOXEL, cut, true)
					for iy = 1, size.Y do
						if out[iy] < occs[ix][iy][iz] then
							occs[ix][iy][iz] = out[iy]
							mats[ix][iy][iz] = if out[iy] <= 0 then Enum.Material.Air else Enum.Material.Mud
						end
					end
				elseif bank then
					local out = Rules.shapeColumn(column, corner.Y, VOXEL, bank, false)
					for iy = 1, size.Y do
						if out[iy] > occs[ix][iy][iz] then
							occs[ix][iy][iz] = out[iy]
							if mats[ix][iy][iz] == Enum.Material.Air then
								mats[ix][iy][iz] = Enum.Material.Ground
							end
						end
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, VOXEL, mats, occs)
	Net.event("GroundDug"):FireAllClients(centre, reach)
end

local function reshapeTrench(r: Rec)
	reshape(r.frame.Position + r.frame.LookVector * ((T.back + T.front) / 2), T.length / 2 + T.ramp.length + VOXEL)
end

local function newPart(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.CastShadow = true
	p.Parent = model
	return p
end

local function section(parent: Instance, name: string, kind: string, class: string, hp: number): Model
	local s = Instance.new("Model")
	s.Name = name
	s:SetAttribute("Kind", kind)
	s:SetAttribute("Class", class)
	s:SetAttribute("Story", 0)
	s:SetAttribute("MaxHP", hp)
	s:SetAttribute("HP", hp)
	s.Parent = parent
	CollectionService:AddTag(s, D.SectionTag)
	return s
end

-- a trench's revetments and firestep (once it stands; again after a cave-in if they were broken)
local function revet(r: Rec)
	if r.model:FindFirstChild("Revetment") then
		return
	end
	local holder = Instance.new("Folder")
	holder.Name = "Revetment"
	holder.Parent = r.model
	local a, b = ends(r)
	local depth = M.Trench.Depth
	local fw = M.Trench.FirestepWidth
	local th = T.plankThickness
	local along = b - a
	local front = r.frame.LookVector
	local function plank(name: string, v: number, from: number, height: number, width: number)
		-- a board along the trench between its floor ends, `v` across, from `from` over the floor, `height` tall
		local mid = (a + b) / 2 + front * v + Vector3.new(0, -depth + from + height / 2, 0)
		local cf = CFrame.lookAt(mid, mid + along, Vector3.yAxis)
		local s = section(holder, name, "Revetment", "Wood", T.plankHP)
		newPart(s, name, Vector3.new(width, height, along.Magnitude), cf, rgb(Palette.Build.Plank))
	end
	local exitGap = r.piece.exit == true
	if exitGap then
		-- the back wall in two boards either side of the exit's ramp
		local gap = T.ramp.width
		local len = (along.Magnitude - gap) / 2
		for i, sign in { -1, 1 } do
			local centre = (a + b) / 2 + along.Unit * sign * (gap / 2 + len / 2)
			local mid = centre + front * (T.back - th / 2) + Vector3.new(0, -depth / 2 + 0.15, 0)
			local s = section(holder, "Back" .. i, "Revetment", "Wood", T.plankHP)
			newPart(
				s,
				"Back" .. i,
				Vector3.new(th, depth + 0.3, len),
				CFrame.lookAt(mid, mid + along, Vector3.yAxis),
				rgb(Palette.Build.Plank)
			)
		end
	else
		plank("Back", T.back - th / 2, 0, depth + 0.3, th)
	end
	plank("Firestep", T.front + fw / 2, 0, M.Trench.FirestepHeight, fw)
	plank("Front", T.front + fw + th / 2, 0, depth + 0.3, th)
end

-- the bags of a sandbag wall: the rows up to `stage` stand, the rest ghosted
local function showSandbags(r: Rec, stage: number)
	for _, s in r.model:GetChildren() do
		for _, p in s:GetChildren() do
			if p:IsA("BasePart") then
				local row = p:GetAttribute("Row") :: number
				local up = row <= stage
				p.Transparency = if up then 0 else C.GhostTransparency
				p.CanCollide = up
				p.CanQuery = up -- (bullets pass through the ghost)
			end
		end
	end
end

local function layoutSandbags(r: Rec, ground: number)
	local p = r.piece
	local base = CFrame.new(r.frame.Position.X, ground - 0.2, r.frame.Position.Z) * r.frame.Rotation
	local cols: { [number]: Model } = {}
	for c = 1, p.columns do
		cols[c] = section(r.model, "Column" .. c, "Sandbags", "Sandbag", C.Sandbags.columnHP)
	end
	for i, bag in Rules.sandbags(p) do
		local jitter = ((i * 37) % 7 / 6 - 0.5) * 2 * C.Sandbags.shade
		local part = newPart(
			cols[bag.column],
			"Bag",
			-- a little narrower and lower than its slot: the seams between bags show
			Vector3.new(bag.width - 0.08, bag.height - 0.06, p.depth - (bag.row - 1) * 0.06),
			base * CFrame.new(bag.x, bag.y, 0),
			rgb(Palette.Build.Sandbag, jitter)
		)
		part:SetAttribute("Row", bag.row)
	end
end

local function layoutWire(r: Rec, ground: number)
	local p = r.piece
	local base = CFrame.new(r.frame.Position.X, ground, r.frame.Position.Z) * r.frame.Rotation
	local holder = Instance.new("Folder")
	holder.Name = "Wire"
	holder.Parent = r.model
	local function thin(name: string, a: Vector3, b: Vector3, width: number, color: Color3)
		local mid = (a + b) / 2
		local part = newPart(
			holder,
			name,
			Vector3.new(width, width, (b - a).Magnitude),
			CFrame.lookAt(mid, b, Vector3.yAxis),
			color
		)
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
	local n = p.pickets
	local picket = rgb(Palette.Build.Picket)
	local wire = rgb(Palette.Build.Wire)
	local function at(i: number, y: number, z: number): Vector3
		local x = -p.width / 2 + (i - 1) / (n - 1) * p.width
		return base:PointToWorldSpace(Vector3.new(x, y, z))
	end
	for i = 1, n do
		-- pickets in two staggered lines, front and back
		local z = if i % 2 == 0 then p.depth / 3 else -p.depth / 3
		thin("Picket", at(i, -0.6, z), at(i, p.height + 0.2, z), 0.22, picket)
	end
	for i = 1, n - 1 do
		local z1 = if i % 2 == 0 then p.depth / 3 else -p.depth / 3
		local z2 = -z1
		-- the coil, as crossing strands between the pickets: low, high, and two diagonals
		thin("Strand", at(i, 0.4, z1), at(i + 1, 0.5, z2), 0.08, wire)
		thin("Strand", at(i, p.height, z1), at(i + 1, p.height * 0.9, z2), 0.08, wire)
		thin("Strand", at(i, 0.3, z1), at(i + 1, p.height, z2), 0.08, wire)
		thin("Strand", at(i, p.height * 0.95, z2), at(i + 1, 0.3, z1), 0.08, wire)
		thin("Strand", at(i, p.height * 0.55, z1), at(i + 1, p.height * 0.6, z2), 0.08, wire)
	end
end

-- the wire's look: ghosted until it stands
local function showWire(r: Rec)
	local holder = r.model:FindFirstChild("Wire")
	if not holder then
		return
	end
	for _, p in holder:GetChildren() do
		if p:IsA("BasePart") then
			p.Transparency = if r.built then 0 else C.GhostTransparency
		end
	end
	r.model:SetAttribute("Armed", r.built)
end

-- the outline of a trench still to be dug: a flat band on the ground
local function outline(r: Rec, ground: number)
	local size = Survey.footprint(r.piece)
	local across = T.front + M.Trench.FirestepWidth - T.back
	local p = newPart(
		r.model,
		"Outline",
		Vector3.new(size.X, 0.2, across),
		CFrame.new(r.frame.Position.X, ground + 0.1, r.frame.Position.Z)
			* r.frame.Rotation
			* CFrame.new(0, 0, -((T.back + T.front + M.Trench.FirestepWidth) / 2)),
		rgb(Palette.Build.Plank)
	)
	p.Transparency = C.GhostTransparency
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
end

-- shows a piece as its work stands now
local function apply(r: Rec)
	r.model:SetAttribute("Work", r.work)
	r.model:SetAttribute("Built", r.built)
	local kind = r.piece.kind
	if kind == "Trench" then
		reshapeTrench(r)
		local outlined = r.model:FindFirstChild("Outline")
		if r.built then
			if outlined then
				outlined:Destroy()
			end
			if r.work >= r.need then
				-- (after a cave-in, boards the blast broke go back in)
				local old = r.model:FindFirstChild("Revetment")
				if old and #old:GetChildren() < (if r.piece.exit then 4 else 3) then
					old:Destroy()
				end
				revet(r)
			end
		end
	elseif kind == "Sandbags" then
		showSandbags(
			r,
			if r.built and r.work >= r.need then r.piece.rows else Rules.stageOf(r.work, r.need, r.piece.rows)
		)
	elseif kind == "Wire" then
		showWire(r)
	end
end

local function remove(r: Rec, debris: boolean)
	if not recs[r.model] then
		return
	end
	recs[r.model] = nil
	if debris then
		local pieces = {}
		for _, d in r.model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "Outline" then
				table.insert(pieces, { cf = d.CFrame, size = d.Size, color = d.Color, t = d.Transparency })
			end
		end
		if #pieces > 0 then
			Net.event("SectionBroken"):FireAllClients(pieces, r.frame.Position)
		end
	end
	r.model:Destroy()
	if r.piece.kind == "Trench" then
		-- the trench filled in; the trenches it was joined to get their open ends back
		reshapeTrench(r)
		for _, o in recs do
			if o.piece.kind == "Trench" and (o.a == r.a or o.a == r.b or o.b == r.a or o.b == r.b) then
				publishEnds(o)
				reshapeTrench(o)
			end
		end
	end
end

local function count(team: string, owner: number?): number
	local n = 0
	for _, r in recs do
		if r.team == team and (owner == nil or r.owner == owner) then
			n += 1
		end
	end
	return n
end

-- the team's trench lines with a new segment between nodes `a` and `b`, for the exit rule
local function exitsOk(team: string, a: number, b: number, exit: boolean): boolean
	local segs = {}
	for _, r in recs do
		if r.team == team and r.piece.kind == "Trench" and r.a and r.b then
			table.insert(segs, { a = r.a, b = r.b, length = T.length, exit = r.piece.exit == true })
		end
	end
	table.insert(segs, { a = a, b = b, length = T.length, exit = exit })
	return Rules.farthestFromExit(segs) <= M.Trench.MaxExitSpacing
end

local function nodeAt(at: Vector3): number
	nextNode += 1
	nodes[nextNode] = { at = at }
	return nextNode
end

local function nodeOf(join: any): number?
	local r = join and recs[join.model]
	if not r then
		return nil
	end
	return if join.which == "A" then r.a else r.b
end

-- Lays a blueprint (Net "Build" "Place")
local function place(player: Player, key: any, at: any)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local piece = Rules.piece(key, C.Pieces)
	if not character or not root or not piece or typeof(at) ~= "CFrame" then
		return
	end
	if not holdsShovel(character) then
		return
	end
	local team = teamOf(character)
	if not team then
		return
	end
	local frame = Survey.frame(at.Position, at.LookVector)
	local f = folder()
	local joins: { [string]: any } = {}
	if piece.kind == "Trench" then
		frame, joins = Survey.snap(f, team, frame)
	end
	local report = Survey.ground(piece, frame, f)
	frame = CFrame.new(frame.Position.X, report.centre, frame.Position.Z) * frame.Rotation
	local ok, reason = Rules.canPlace({
		piece = piece,
		distance = (root.Position - frame.Position).Magnitude,
		reach = C.Reach + 2, -- (the client's ghost checks C.Reach; slack for movement since)
		slope = report.slope,
		maxSlope = piece.maxSlope or T.maxSlope,
		ground = report.ground,
		water = report.water,
		overlap = Survey.blocked(piece, frame, report.low, f, joins),
		mine = count(team, player.UserId),
		team = count(team, nil),
		perPlayer = C.PerPlayer,
		perTeam = C.PerTeam,
	})
	if not ok then
		refuse(player, reason or "Can't build here")
		return
	end
	local model = Instance.new("Model")
	model.Name = piece.key
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local now = os.clock()
	local r: Rec = {
		model = model,
		piece = piece,
		team = team,
		owner = player.UserId,
		work = 0,
		need = piece.work,
		built = false,
		born = now,
		worked = now,
		frame = frame,
	}
	if piece.kind == "Trench" then
		local half = T.length / 2
		local pa = frame.Position - frame.RightVector * half
		local pb = frame.Position + frame.RightVector * half
		local a = nodeOf(joins.A)
		local b = nodeOf(joins.B)
		local function groundAt(p: Vector3): number
			return Survey.dugGround(f, p.X, p.Z) or Survey.groundAt(p.X, p.Z, frame.Position.Y) or frame.Position.Y
		end
		local ga = if a then nodes[a].at.Y else groundAt(pa)
		local gb = if b then nodes[b].at.Y else groundAt(pb)
		local na = a or nodeAt(Vector3.new(pa.X, ga, pa.Z))
		local nb = b or nodeAt(Vector3.new(pb.X, gb, pb.Z))
		if not exitsOk(team, na, nb, piece.exit == true) then
			if not a then
				nodes[na] = nil
			end
			if not b then
				nodes[nb] = nil
			end
			refuse(player, `Needs a way out every {M.Trench.MaxExitSpacing} studs: lay a trench exit`)
			return
		end
		r.a, r.b, r.floorA, r.floorB = na, nb, ga, gb
		r.caved = {}
		outline(r, report.centre)
	elseif piece.kind == "Sandbags" then
		layoutSandbags(r, report.low)
	else
		layoutWire(r, report.low)
	end
	local size, _ = Survey.footprint(piece)
	model:SetAttribute("Piece", piece.key)
	model:SetAttribute("Team", team)
	model:SetAttribute("Need", r.need)
	model:SetAttribute("Frame", frame)
	model:SetAttribute("Size", size)
	recs[model] = r
	model.Parent = f
	if piece.kind == "Trench" then
		publishEnds(r)
		-- the trenches it joined lose their open ends there
		for _, j in joins do
			local o = recs[j.model]
			if o then
				publishEnds(o)
				reshapeTrench(o)
			end
		end
	end
	apply(r)
	-- a sandbag wall goes when its last column is broken
	if piece.kind == "Sandbags" then
		model.ChildRemoved:Connect(function()
			for _, c in model:GetChildren() do
				if CollectionService:HasTag(c, D.SectionTag) then
					return
				end
			end
			remove(r, false)
		end)
	end
end

-- A shovel swing at a piece (Net "Build" "Work")
local function work(player: Player, model: any)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root or typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local r = recs[model]
	local team = teamOf(character)
	if not r or not team or not holdsShovel(character) then
		return
	end
	local now = os.clock()
	if Rules.tooSoon(now, lastSwing[player], ShovelCfg.Dig.length, C.SwingSlack) then
		return
	end
	if Survey.distanceTo(model, root.Position) > C.SwingReach then
		return
	end
	lastSwing[player] = now
	local own = team == r.team
	if own and r.work >= r.need then
		return -- (repairs come later)
	end
	local was = r.work
	local left, gone = Rules.swing(r.work, r.need, own)
	if gone then
		remove(r, r.built)
		return
	end
	r.work = left
	r.worked = now
	if r.work >= r.need then
		r.built = true
		if r.caved and #r.caved > 0 then
			r.caved = {} -- dug out again
		end
	end
	local stages = if r.piece.kind == "Sandbags" then r.piece.rows else T.stages
	if Rules.stageOf(was, r.need, stages) ~= Rules.stageOf(r.work, r.need, stages) or r.work >= r.need then
		apply(r)
	else
		r.model:SetAttribute("Work", r.work)
	end
end

-- A blast at `position` (src/server/Damage.blast, after the crater): `kpaAt(studs)` its overpressure, `reachOf(kpa)`
-- how far it reaches that. Trenches cave in round it, wire within reach of Wire.failKPa is cut.
function Build.blast(position: Vector3, kpaAt: (number) -> number, reachOf: (number) -> number)
	local caveR = reachOf(T.caveKPa)
	local wireR = reachOf(C.Wire.failKPa)
	for _, r in recs do
		local kind = r.piece.kind
		if kind == "Trench" and r.work > 0 then
			local a, b = ends(r)
			local d = Survey.toSegment(position, a, b)
			if d <= caveR and kpaAt(d) >= T.caveKPa then
				-- the chord of the cave-in's circle along this segment only (Studio round 1: a blast at a joint
				-- took both whole segments)
				local rel = Vector3.new(position.X - a.X, 0, position.Z - a.Z)
				local along = rel:Dot(r.frame.RightVector)
				local off = math.abs(rel:Dot(r.frame.LookVector) - (T.back + T.front + M.Trench.FirestepWidth) / 2)
				local caved = Rules.caveSpan(along, off, caveR, T.length)
				r.work = Rules.caveWork(r.work, r.need, caved, T.length)
				r.caved = r.caved or {}
				table.insert(r.caved :: any, { at = position, r = caveR })
				if r.work <= 0 then
					remove(r, false)
				else
					apply(r)
				end
			end
		elseif kind == "Wire" then
			local frame = r.model:GetAttribute("Frame") :: CFrame
			local l = frame:PointToObjectSpace(position)
			local dx = math.max(math.abs(l.X) - r.piece.width / 2, 0)
			local d = math.sqrt(dx * dx + l.Z * l.Z + math.max(l.Y - r.piece.height, 0) ^ 2)
			if d <= wireR then
				remove(r, true)
			end
		end
	end
end

-- the barbed wire that stands: its box (centre frame and size) for src/server/Wire
function Build.wires(): { { frame: CFrame, size: Vector3 } }
	local out = {}
	for _, r in recs do
		if r.piece.kind == "Wire" and r.built then
			local p = r.piece
			local frame = r.model:GetAttribute("Frame") :: CFrame
			table.insert(
				out,
				{ frame = frame * CFrame.new(0, p.height / 2, 0), size = Vector3.new(p.width, p.height + 3, p.depth) }
			)
		end
	end
	return out
end

-- Removes every piece (dev: the admin panel's undo); the trenches filled in
function Build.clear()
	local list = {}
	for _, r in recs do
		table.insert(list, r)
	end
	for _, r in list do
		remove(r, false)
	end
end

function Build.start()
	folder()
	Net.event("Build").OnServerEvent:Connect(function(player: Player, kind: any, a: any, b: any)
		if kind == "Place" then
			place(player, a, b)
		elseif kind == "Work" then
			work(player, a)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastSwing[player] = nil
	end)
	-- blueprints nobody worked on
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			local stale = {}
			for _, r in recs do
				if r.work <= 0 and not r.built and now - r.worked > C.BlueprintLife then
					table.insert(stale, r)
				end
			end
			for _, r in stale do
				remove(r, false)
			end
		end
	end)
end

return Build
