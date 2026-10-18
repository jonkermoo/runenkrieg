--!strict
-- Trees with HP (Config/Damage.Trees, Rules/Trees; user 2026-10-17). Bullets chip a trunk; a blast hurts every tree by
-- the overpressure at its trunk base (Config/Damage.Blast.Tree). A tree at 0 HP falls:
-- - felled by a bullet: along the shot, leaving a stump;
-- - felled by a blast: whole, away from it, no stump (the crater is there).
-- The fall costs the server nothing: it tags the tree FallingTag with where it will lie ("FallTo") and every client
-- animates it (src/client/TreeFall); then the server places it there, anchored, as cover (FallenTag). Lying, it has
-- Fallen.share x its MaxHP again, and bullets and blasts wear that down too. It lies for Fall.lifetime s, at most
-- Fall.maxFallen at once (the oldest goes first), or until destroyed: tagged SinkingTag, it sinks and fades on the
-- clients and is removed.
-- The leaves have HP of their own (Trees.Leaves): staff beams through or near the canopy and blasts take it; bullets
-- never do. Every beam that reaches a canopy is shown to the clients (Net "LeavesHit": a shake and falling leaves). At
-- 0, or when the tree falls, the canopy is tagged ShedTag: it sheds on the clients over Leaves.shedTime s, then goes.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Cfg = require(Shared.Config.Damage)
local TreeCfg = require(Shared.Config.TreeSway)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.Trees)

local Trees = {}

local T = Cfg.Trees
local L = T.Leaves
local fallen: { Model } = {} -- oldest first

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.xAxis
end

local function standing(model: Instance): boolean
	return CollectionService:HasTag(model, TreeCfg.Tag)
end

local function lying(model: Instance): boolean
	return CollectionService:HasTag(model, TreeCfg.FallenTag)
		and not CollectionService:HasTag(model, TreeCfg.SinkingTag)
end

-- a tree a part belongs to (standing, or lying and not yet going), or nil
local function treeOf(part: Instance?): Model?
	local model = part and part.Parent
	if model and model:IsA("Model") and (standing(model) or lying(model)) then
		return model
	end
	return nil
end

-- its scale against its kind's height, measured while it stands (kept as "Scale")
local function scale(tree: Model): number
	local s = tree:GetAttribute("Scale")
	if type(s) == "number" then
		return s
	end
	local _, size = tree:GetBoundingBox()
	local target = (Assets.TreeTargetHeight :: any)[tree.Name]
	s = if type(target) == "number" then size.Y / target else 1
	tree:SetAttribute("Scale", s)
	return s :: number
end

-- its HP and MaxHP, set to full the first time it is hurt
local function hp(tree: Model): (number, number)
	local full = tree:GetAttribute("MaxHP")
	if type(full) ~= "number" then
		full = Rules.maxHP(tree.Name, scale(tree), T)
		tree:SetAttribute("MaxHP", full)
	end
	local now = tree:GetAttribute("HP")
	return if type(now) == "number" then now else full :: number, full :: number
end

local function leafHP(tree: Model): (number, number)
	local full = tree:GetAttribute("LeafMaxHP")
	if type(full) ~= "number" then
		full = Rules.maxHP(tree.Name, scale(tree), L)
		tree:SetAttribute("LeafMaxHP", full)
	end
	local now = tree:GetAttribute("LeafHP")
	return if type(now) == "number" then now else full :: number, full :: number
end

-- the canopy sheds on the clients, then is removed
local function shed(tree: Model)
	local canopy = tree:FindFirstChild("Canopy")
	if not canopy or CollectionService:HasTag(tree, TreeCfg.ShedTag) then
		return
	end
	tree:SetAttribute("LeafHP", 0)
	tree:SetAttribute("ShedTime", L.shedTime)
	CollectionService:AddTag(tree, TreeCfg.ShedTag)
	task.delay(L.shedTime, function()
		canopy:Destroy()
	end)
end

local function hurtLeaves(tree: Model, amount: number)
	if amount <= 0 or not tree:FindFirstChild("Canopy") or CollectionService:HasTag(tree, TreeCfg.ShedTag) then
		return
	end
	local left = Rules.after((leafHP(tree)), amount)
	tree:SetAttribute("LeafHP", left)
	if left <= 0 then
		shed(tree)
	end
end

local function sink(tree: Model)
	if not tree.Parent or CollectionService:HasTag(tree, TreeCfg.SinkingTag) then
		return
	end
	local i = table.find(fallen, tree)
	if i then
		table.remove(fallen, i)
	end
	tree:SetAttribute("SinkDepth", T.Fall.sinkDepth)
	tree:SetAttribute("SinkTime", T.Fall.sinkTime)
	CollectionService:AddTag(tree, TreeCfg.SinkingTag)
	task.delay(T.Fall.sinkTime, function()
		tree:Destroy()
	end)
end

-- the ground's height at a tree's base (its pivot is sunk under the lowest ground round the trunk)
local function groundAt(base: Vector3): number
	local hit = workspace:Raycast(base + Vector3.yAxis * 30, Vector3.yAxis * -60, terrainOnly)
	return if hit then math.max(hit.Position.Y, base.Y) else base.Y
end

-- from the sunk base up to `Stump.height` over the ground
local function stump(tree: Model, trunk: BasePart, base: Vector3)
	local S = T.Stump
	local w = math.min(trunk.Size.X, trunk.Size.Z) * S.widthShare
	local top = groundAt(base) + S.height
	local p = Instance.new("Part")
	p.Name = "Stump"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(top - base.Y, w, w)
	p.CFrame = CFrame.new(Vector3.new(base.X, (base.Y + top) / 2, base.Z)) * CFrame.Angles(0, 0, math.pi / 2)
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = trunk.Color
	p.Parent = tree.Parent
end

-- `away`: the way it falls; `leaveStump`: felled by a bullet
local function fell(tree: Model, away: Vector3, leaveStump: boolean)
	local trunk = tree:FindFirstChild("Trunk") :: BasePart?
	if not trunk then
		return
	end
	local _, full = hp(tree)
	CollectionService:RemoveTag(tree, TreeCfg.Tag) -- no more sway (src/client/TreeSway)
	local F = T.Fall
	local dir = flat(away)
	local pivot = tree:GetPivot()
	local hinge = if leaveStump
		then Vector3.new(pivot.X, groundAt(pivot.Position) + T.Stump.height, pivot.Z)
		else pivot.Position
	local _, size = tree:GetBoundingBox()
	local h = size.Y
	-- the ground under where its top comes down
	local reach = h * F.tipShare
	local tip = hinge + dir * reach
	local hit = workspace:Raycast(tip + Vector3.yAxis * 60, Vector3.yAxis * -160, terrainOnly)
	local rise = if hit then hit.Position.Y - hinge.Y else 0
	local tilt = math.rad(Rules.fallTilt(reach, rise, F.minTilt, F.maxTilt))
	local turn = CFrame.new(hinge) * CFrame.fromAxisAngle(Vector3.new(0, 1, 0):Cross(dir), tilt) * CFrame.new(-hinge)
	-- the butt rests on the stump top: slide it out along the fallen trunk by what sat under the hinge
	local under = hinge.Y - pivot.Y
	local lie = CFrame.new(turn:VectorToWorldSpace(Vector3.yAxis) * under) * turn * pivot
	if leaveStump then
		stump(tree, trunk, pivot.Position)
	end
	tree:SetAttribute("FallTo", lie)
	tree:SetAttribute("FallTime", F.time)
	tree:SetAttribute("FallLength", h)
	tree:SetAttribute("HP", full * T.Fallen.share) -- it lies with HP again (user: "continue HP")
	CollectionService:AddTag(tree, TreeCfg.FallingTag)
	task.delay(F.time, function()
		if tree.Parent then
			tree:PivotTo(lie)
			CollectionService:AddTag(tree, TreeCfg.FallenTag)
			shed(tree) -- a felled tree's leaves go to 0 (user)
		end
	end)
	table.insert(fallen, tree)
	while #fallen > F.maxFallen do
		sink(fallen[1])
	end
	task.delay(F.time + F.lifetime, sink, tree)
end

local function hurt(tree: Model, amount: number, away: Vector3, byBullet: boolean, whole: boolean?)
	local now = hp(tree)
	local left, gone = Rules.after(now, amount)
	if lying(tree) then
		tree:SetAttribute("HP", left)
		if gone or whole then
			sink(tree) -- destroyed where it lies
		end
	elseif standing(tree) then
		tree:SetAttribute("HP", left)
		if gone or whole then
			fell(tree, away, byBullet and not whole)
		end
	end
end

-- a bullet (or one pellet) of weapon `class` hitting `part` along `direction`
function Trees.shot(part: Instance?, class: string?, direction: Vector3)
	local tree = treeOf(part)
	if tree and part and part.Name == "Trunk" then
		local amount = Rules.shotDamage(class, T)
		if amount > 0 then
			hurt(tree, amount, direction, true)
		end
	end
end

local function trees(): { Model }
	local out = {}
	for _, tag in { TreeCfg.Tag, TreeCfg.FallenTag } do
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsA("Model") and m:IsDescendantOf(workspace) and treeOf(m:FindFirstChild("Trunk")) then
				table.insert(out, m)
			end
		end
	end
	return out
end

-- a blast at `position` reaching `reach` studs; `kpaAt(distance)` its overpressure. A standing tree by its trunk base,
-- a lying one by its trunk, the leaves by the canopy.
function Trees.blast(position: Vector3, reach: number, kpaAt: (number) -> number)
	local B = Cfg.Blast
	for _, tree in trees() do
		local trunk = tree:FindFirstChild("Trunk") :: BasePart
		local at = if standing(tree) then tree:GetPivot().Position else trunk.Position
		local d = (at - position).Magnitude
		local canopy = tree:FindFirstChild("Canopy") :: BasePart?
		if canopy and standing(tree) and (canopy.Position - position).Magnitude <= reach then
			local _, full = leafHP(tree)
			local kpa = kpaAt((canopy.Position - position).Magnitude)
			hurtLeaves(tree, (Rules.blastDamage(kpa, L.blastFail, full, L.blastWeaken)))
		end
		if d <= reach then
			local _, full = hp(tree)
			local amount, whole = Rules.blastDamage(kpaAt(d), B.Tree.fail, full, B.Tree.weaken)
			if amount > 0 then
				hurt(tree, amount, at - position, false, whole)
			end
		end
	end
end

-- A staff beam of `stage` from `origin` to where it landed: the leaves it passes through or near lose HP, and every
-- client shakes them and drops leaves there (scaled by the stage, Leaves.react).
function Trees.beam(origin: Vector3, landed: Vector3, stage: number)
	local line = landed - origin
	local length = line.Magnitude
	local near = L.nearDistance[stage]
	if length < 1e-3 or not near then
		return
	end
	local d = line / length
	local mid = (origin + landed) / 2
	local hits = {}
	for _, tree in CollectionService:GetTagged(TreeCfg.Tag) do
		local canopy = tree:IsA("Model") and tree:FindFirstChild("Canopy") :: BasePart?
		if canopy and not CollectionService:HasTag(tree, TreeCfg.ShedTag) then
			local half = canopy.Size / 2
			if (canopy.Position - mid).Magnitude <= length / 2 + half.Magnitude + near then
				local o = canopy.CFrame:PointToObjectSpace(origin)
				local v = canopy.CFrame:VectorToObjectSpace(d)
				local t = Rules.enterBox(o.X, o.Y, o.Z, v.X, v.Y, v.Z, length, half.X, half.Y, half.Z)
				local through = t ~= nil
				if not t then
					local h = half + Vector3.one * near
					t = Rules.enterBox(o.X, o.Y, o.Z, v.X, v.Y, v.Z, length, h.X, h.Y, h.Z)
				end
				if t then
					local react = (L.react[stage] or 1) * (if through then 1 else L.nearReact)
					table.insert(hits, { tree, origin + d * t, react })
					hurtLeaves(tree :: Model, Rules.beamLeafDamage(stage, through, L))
				end
			end
		end
	end
	if #hits > 0 then
		Net.event("LeavesHit"):FireAllClients(hits)
	end
end

return Trees
