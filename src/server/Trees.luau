--!strict
-- Trees with HP (Config/Damage.Trees, Rules/Trees; user 2026-10-17). Bullets chip a trunk; a blast hurts every tree by
-- the overpressure at its trunk base (Config/Damage.Blast.Tree). A tree at 0 HP falls:
-- - felled by a bullet: along the shot, leaving a stump;
-- - felled by a blast: whole, away from it, no stump (the crater is there).
-- The fall costs the server nothing: it tags the tree "FallingTree" with where it will lie ("FallTo") and every client
-- animates it (src/client/TreeFall); then the server places it there, anchored, as cover. It lies for Fall.lifetime s,
-- at most Fall.maxFallen at once (the oldest goes first): tagged "SinkingTree", it sinks on the clients and is removed.
-- Fallen trees take no more damage.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Cfg = require(Shared.Config.Damage)
local TreeCfg = require(Shared.Config.TreeSway)
local Rules = require(Shared.Rules.Trees)

local Trees = {}

local T = Cfg.Trees
local fallen: { Model } = {} -- oldest first

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.xAxis
end

-- a standing tree a part belongs to, or nil
local function treeOf(part: Instance?): Model?
	local model = part and part.Parent
	if model and model:IsA("Model") and CollectionService:HasTag(model, TreeCfg.Tag) then
		return model
	end
	return nil
end

local function height(tree: Model): number
	local _, size = tree:GetBoundingBox()
	return size.Y
end

-- its HP, set to full the first time it is hurt
local function hp(tree: Model): number
	local now = tree:GetAttribute("HP")
	if type(now) == "number" then
		return now
	end
	local target = (Assets.TreeTargetHeight :: any)[tree.Name]
	local scale = if type(target) == "number" then height(tree) / target else 1
	local full = Rules.maxHP(tree.Name, scale, T)
	tree:SetAttribute("MaxHP", full)
	return full
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

local function stump(tree: Model, trunk: BasePart, base: Vector3)
	local S = T.Stump
	local w = math.min(trunk.Size.X, trunk.Size.Z) * S.widthShare
	local p = Instance.new("Part")
	p.Name = "Stump"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(S.height, w, w)
	p.CFrame = CFrame.new(base + Vector3.yAxis * S.height / 2) * CFrame.Angles(0, 0, math.pi / 2)
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
	CollectionService:RemoveTag(tree, TreeCfg.Tag) -- no more sway (src/client/TreeSway) or damage
	local F = T.Fall
	local dir = flat(away)
	local pivot = tree:GetPivot()
	local hinge = pivot.Position + if leaveStump then Vector3.yAxis * T.Stump.height else Vector3.zero
	local h = height(tree)
	-- the ground under where its top comes down
	local reach = h * F.tipShare
	local tip = hinge + dir * reach
	local hit = workspace:Raycast(tip + Vector3.yAxis * 60, Vector3.yAxis * -160, terrainOnly)
	local rise = if hit then hit.Position.Y - hinge.Y else 0
	local tilt = math.rad(Rules.fallTilt(reach, rise, F.minTilt, F.maxTilt))
	local turn = CFrame.new(hinge) * CFrame.fromAxisAngle(Vector3.new(0, 1, 0):Cross(dir), tilt) * CFrame.new(-hinge)
	local lie = turn * pivot
	if leaveStump then
		stump(tree, trunk, pivot.Position)
	end
	tree:SetAttribute("FallTo", lie)
	tree:SetAttribute("FallTime", F.time)
	CollectionService:AddTag(tree, TreeCfg.FallingTag)
	task.delay(F.time, function()
		if tree.Parent then
			tree:PivotTo(lie)
		end
	end)
	table.insert(fallen, tree)
	while #fallen > F.maxFallen do
		sink(fallen[1])
	end
	task.delay(F.time + F.lifetime, sink, tree)
end

local function hurt(tree: Model, amount: number, away: Vector3, byBullet: boolean, whole: boolean?)
	local left, felled = Rules.after(hp(tree), amount)
	tree:SetAttribute("HP", left)
	if felled or whole then
		fell(tree, away, byBullet and not whole)
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

-- a blast at `position` reaching `reach` studs; `kpaAt(distance)` its overpressure
function Trees.blast(position: Vector3, reach: number, kpaAt: (number) -> number)
	local B = Cfg.Blast
	for _, tree in CollectionService:GetTagged(TreeCfg.Tag) do
		if tree:IsA("Model") and tree:IsDescendantOf(workspace) then
			local base = tree:GetPivot().Position
			local d = (base - position).Magnitude
			if d <= reach then
				hp(tree) -- (sets MaxHP the first time)
				local full = tree:GetAttribute("MaxHP") :: number
				local amount, whole = Rules.blastDamage(kpaAt(d), B.Tree.fail, full, B.Weaken)
				if amount > 0 then
					hurt(tree, amount, base - position, false, whole)
				end
			end
		end
	end
end

return Trees
