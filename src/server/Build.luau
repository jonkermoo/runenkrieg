--!strict
-- Player building on the server (phase 4.4; Config/Build, Rules/Build, shared/BuildSurvey). The client lays a
-- blueprint (Net "Build" "Place": the piece and where); the server surveys the ground, checks the rules and the caps,
-- and lays it in Workspace[Config/Build.Folder]. Trenches are planned and dug in src/server/Trenches (Net "Build"
-- "Plan": start and end).
-- Every shovel swing (Net "Build" "Work", the target and the shovel's mode, user 2026-10-23):
-- - Build at your team's piece adds a unit of work; it rises in stages and stands at full work;
-- - Destroy at any piece, any team's, takes one off; at 0 it is torn down; at a tree it chops it (src/server/Trees).
-- - Sandbag walls: a section of class "Sandbag" per column of bags, the rows filling in as it is worked.
-- - Barbed wire: pickets and strands nothing queries (bullets pass); src/server/Wire slows and hurts soldiers in it.
-- Build.blast (from src/server/Damage.blast): a big enough blast caves trenches in and cuts wire.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local C = require(Shared.Config.Build)
local D = require(Shared.Config.Destruction)
local Palette = require(Shared.Config.Palette)
local ShovelCfg = require(Shared.Config.Shovel)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Build)
local Survey = require(Shared.BuildSurvey)
local Net = require(Shared.Net)
local Trees = require(script.Parent.Trees)
local Trenches = require(script.Parent.Trenches)

local Build = {}

type Rec = {
	model: Model,
	piece: Rules.Piece,
	team: string,
	owner: number,
	work: number,
	need: number,
	built: boolean, -- has stood once
	born: number,
	worked: number,
	frame: CFrame,
}

local recs: { [Model]: Rec } = {}
local lastSwing: { [Player]: number } = {}

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

-- shows a piece as its work stands now
local function apply(r: Rec)
	r.model:SetAttribute("Work", r.work)
	r.model:SetAttribute("Built", r.built)
	local kind = r.piece.kind
	if kind == "Sandbags" then
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
			if d:IsA("BasePart") and d.Transparency < 1 then
				table.insert(pieces, { cf = d.CFrame, size = d.Size, color = d.Color, t = d.Transparency })
			end
		end
		if #pieces > 0 then
			Net.event("SectionBroken"):FireAllClients(pieces, r.frame.Position)
		end
	end
	r.model:Destroy()
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

-- the soldier's character, root and team when they hold the shovel
local function digger(player: Player): (Model?, BasePart?, string?)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root or not holdsShovel(character) then
		return nil, nil, nil
	end
	return character, root, teamOf(character)
end

-- Lays a blueprint (Net "Build" "Place")
local function place(player: Player, key: any, at: any)
	local character, root, team = digger(player)
	local piece = Rules.piece(key, C.Pieces)
	if not character or not root or not team or not piece or typeof(at) ~= "CFrame" or piece.kind == "Trench" then
		return
	end
	local frame = Survey.frame(at.Position, at.LookVector)
	local report = Survey.ground(piece, frame)
	frame = CFrame.new(frame.Position.X, report.centre, frame.Position.Z) * frame.Rotation
	local ok, reason = Rules.canPlace({
		piece = piece,
		distance = (root.Position - frame.Position).Magnitude,
		reach = C.Reach + 2, -- (the client's ghost checks C.Reach; slack for movement since)
		slope = report.slope,
		maxSlope = piece.maxSlope or C.Trench.maxSlope,
		ground = report.ground,
		water = report.water,
		overlap = Survey.blocked(piece, frame, report.low),
		mine = count(team, player.UserId),
		team = count(team, nil),
		perPlayer = C.PerPlayer,
		perTeam = C.PerTeam,
	})
	if not ok then
		refuse(player, reason or "Can't build here")
		return
	end
	local f = folder()
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
	if piece.kind == "Sandbags" then
		layoutSandbags(r, report.low)
	else
		layoutWire(r, report.low)
	end
	model:SetAttribute("Piece", piece.key)
	model:SetAttribute("Team", team)
	model:SetAttribute("Need", r.need)
	model:SetAttribute("Frame", frame)
	model:SetAttribute("Size", Survey.footprint(piece))
	recs[model] = r
	model.Parent = f
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

-- Plans a trench (Net "Build" "Plan": its start and end on the ground)
local function plan(player: Player, a: any, b: any)
	local character, root, team = digger(player)
	if not character or not root or not team or typeof(a) ~= "Vector3" or typeof(b) ~= "Vector3" then
		return
	end
	local reason = Trenches.plan(player, team, root, a, b)
	if reason then
		refuse(player, reason)
	end
end

-- A shovel swing (Net "Build" "Work"): at a piece, a trench block or a tree, in the shovel's mode
local function work(player: Player, target: any, mode: any)
	local character, root, team = digger(player)
	if not character or not root or not team or typeof(target) ~= "Instance" then
		return
	end
	if mode ~= "Build" and mode ~= "Destroy" then
		return
	end
	local now = os.clock()
	if Rules.tooSoon(now, lastSwing[player], ShovelCfg.Dig.length, C.SwingSlack) then
		return
	end
	-- a trench block
	local blk = Trenches.blockOf(target)
	if blk then
		if Trenches.distance(blk, root.Position) <= C.Trench.swingReach then
			lastSwing[player] = now
			Trenches.work(blk, team, mode)
		end
		return
	end
	-- a tree (Destroy only)
	if
		mode == "Destroy"
		and target:IsA("BasePart")
		and (target.Position - root.Position).Magnitude <= C.SwingReach + 4
	then
		if Trees.chop(target, root.Position) then
			lastSwing[player] = now
		end
		return
	end
	-- a piece
	local r = if target:IsA("Model") then recs[target] else nil
	if not r or Survey.distanceTo(target, root.Position) > C.SwingReach then
		return
	end
	local own = team == r.team
	if mode == "Build" and (not own or r.work >= r.need) then
		return -- (repairs come later)
	end
	lastSwing[player] = now
	local was = r.work
	local left, gone = Rules.swing(r.work, r.need, mode == "Build")
	if gone then
		remove(r, r.built)
		return
	end
	r.work = left
	r.worked = now
	if r.work >= r.need then
		r.built = true
	end
	local stages = if r.piece.kind == "Sandbags" then r.piece.rows else 1
	if Rules.stageOf(was, r.need, stages) ~= Rules.stageOf(r.work, r.need, stages) or r.work >= r.need then
		apply(r)
	else
		r.model:SetAttribute("Work", r.work)
	end
end

-- A blast at `position` (src/server/Damage.blast, after the crater): `kpaAt(studs)` its overpressure, `reachOf(kpa)`
-- how far it reaches that. Trenches cave in round it (src/server/Trenches), wire within reach of Wire.failKPa is cut.
function Build.blast(position: Vector3, kpaAt: (number) -> number, reachOf: (number) -> number)
	Trenches.blast(position, kpaAt, reachOf)
	local wireR = reachOf(C.Wire.failKPa)
	local cut = {}
	for _, r in recs do
		if r.piece.kind == "Wire" then
			local frame = r.model:GetAttribute("Frame") :: CFrame
			local l = frame:PointToObjectSpace(position)
			local dx = math.max(math.abs(l.X) - r.piece.width / 2, 0)
			local d = math.sqrt(dx * dx + l.Z * l.Z + math.max(l.Y - r.piece.height, 0) ^ 2)
			if d <= wireR then
				table.insert(cut, r)
			end
		end
	end
	for _, r in cut do
		remove(r, true)
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

-- Removes every piece and trench (dev: the admin panel's undo)
function Build.clear()
	local list = {}
	for _, r in recs do
		table.insert(list, r)
	end
	for _, r in list do
		remove(r, false)
	end
	Trenches.clear()
end

function Build.start()
	folder()
	Trenches.start()
	Net.event("Build").OnServerEvent:Connect(function(player: Player, kind: any, a: any, b: any)
		if kind == "Place" then
			place(player, a, b)
		elseif kind == "Plan" then
			plan(player, a, b)
		elseif kind == "Work" then
			work(player, a, b)
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
