--!strict
-- Trees with HP (Config/Damage.Trees, Rules/Trees; user 2026-10-17). Bullets chip a trunk; a blast hurts every tree by
-- the overpressure at its trunk base (Config/Damage.Blast.Tree). A tree at 0 HP falls:
-- - felled by a bullet: along the shot, leaving a stump;
-- - felled by a blast: whole, away from it, no stump (the crater is there).
-- The fall costs the server nothing: it tags the tree FallingTag with where it will lie ("FallTo", clear of the ground
-- all along it) and every client animates it (src/client/TreeFall); then the server places it there, anchored, as cover
-- (FallenTag): soldiers it lands on are hurt and knocked aside (Damage.crush; the trunk lets them through a moment), it
-- presses an even imprint into the ground it lies on, and an uprooted one leaves a pit and a root ball of mud
-- (src/server/Ground). A full beam straight on a trunk destroys it instead: it falls and fades out (a stump left); a blast
-- of Blast.Tree.splinter at it blows it away (a puff of splinters, nothing left). Lying, it has
-- Fallen.share x its MaxHP again, and bullets and blasts wear that down too. It lies for Fall.lifetime s, at most
-- Fall.maxFallen at once (the oldest goes first), or until destroyed: tagged SinkingTag, it sinks and fades on the
-- clients and is removed.
-- The leaves have HP of their own (Trees.Leaves): staff beams through or near the canopy and blasts take it; bullets
-- never do. Every beam that reaches a canopy is shown to the clients (Net "LeavesHit": a shake and falling leaves). At
-- 0, or when the tree falls, the canopy is tagged ShedTag: it sheds on the clients over Leaves.shedTime s, then goes.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Assets = require(Shared.Config.Assets)
local Cfg = require(Shared.Config.Damage)
local TreeCfg = require(Shared.Config.TreeSway)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.Trees)
local BlastRules = require(Shared.Rules.Blast)
local Ground = require(script.Parent.Ground)

local Trees = {}

local T = Cfg.Trees
local L = T.Leaves
local fallen: { Model } = {} -- oldest first
local crush: ((Vector3, Vector3, number, number, string) -> ())? = nil -- src/server/Damage.crush

-- a landing trunk lets characters through for a moment (Fall.Crush.ghost), so nobody is pushed into the ground or flung
local GHOST = "LandingTree"
PhysicsService:RegisterCollisionGroup(GHOST)
PhysicsService:RegisterCollisionGroup("Characters")
PhysicsService:CollisionGroupSetCollidable(GHOST, "Characters", false)

-- what hurts soldiers a tree lands on (Damage registers itself; Trees can't require Damage, which requires Trees)
function Trees.onCrush(fn: (Vector3, Vector3, number, number, string) -> ())
	crush = fn
end

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

-- the ground's height at a tree's base, as it is now (its pivot is sunk under the lowest ground round the trunk, but a
-- crater can take the ground below that: user 2026-10-24, trees felled into a howitzer crater lay floating over it)
local function groundAt(base: Vector3): number
	local hit = workspace:Raycast(base + Vector3.yAxis * 30, Vector3.yAxis * -60, terrainOnly)
	return if hit then hit.Position.Y else base.Y
end

local stumps: { BasePart } = {}

-- from under the ground (the sunk base, or deeper where a crater took the ground away) up to `Stump.height` over it
local function stump(tree: Model, trunk: BasePart, base: Vector3)
	local S = T.Stump
	local w = math.min(trunk.Size.X, trunk.Size.Z) * S.widthShare
	local ground = groundAt(base)
	local top = ground + S.height
	local bottom = math.min(base.Y, ground - 1)
	local p = Instance.new("Part")
	p.Name = "Stump"
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(top - bottom, w, w)
	p.CFrame = CFrame.new(Vector3.new(base.X, (bottom + top) / 2, base.Z)) * CFrame.Angles(0, 0, math.pi / 2)
	p.Anchored = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = trunk.Color
	p.Parent = tree.Parent
	table.insert(stumps, p)
end

local function thickness(trunk: BasePart): number
	return math.min(trunk.Size.X, trunk.Size.Z)
end

-- the trunk lets characters through until none is inside it (at least Crush.ghost s, at most ghostMax)
local function ghostWhileInside(trunk: BasePart)
	local C = T.Fall.Crush
	trunk.CollisionGroup = GHOST
	task.delay(C.ghost, function()
		local waited = C.ghost
		while trunk.Parent and waited < C.ghostMax do
			local inside = false
			for _, p in workspace:GetPartsInPart(trunk) do
				if p.CollisionGroup == "Characters" then
					inside = true
					break
				end
			end
			if not inside then
				break
			end
			task.wait(0.25)
			waited += 0.25
		end
		if trunk.Parent then
			trunk.CollisionGroup = "Default"
		end
	end)
end

-- `away`: the way it falls; `leaveStump`: felled by a bullet or a beam (snapped above a stump); else uprooted whole.
-- `fadeAway`: destroyed (a full beam on the trunk): it falls and fades out as it lands, leaving nothing but its stump.
local function fell(tree: Model, away: Vector3, leaveStump: boolean, fadeAway: boolean?)
	local trunk = tree:FindFirstChild("Trunk") :: BasePart?
	if not trunk then
		return
	end
	local _, full = hp(tree)
	local sc = scale(tree)
	CollectionService:RemoveTag(tree, TreeCfg.Tag) -- no more sway (src/client/TreeSway)
	local F = T.Fall
	local dir = flat(away)
	local pivot = tree:GetPivot()
	local base = pivot.Position
	local ground = groundAt(base)
	local half = thickness(trunk) / 2
	-- its butt lies pressed into the ground (Fall.Imprint): uprooted, where it stood; snapped, slid off its stump beside
	-- it (on the stump top it floated over slopes, Studio 2026-10-18)
	local off = if leaveStump then thickness(trunk) * T.Stump.widthShare / 2 + half else 0
	local foot = base + dir * off
	local hinge = Vector3.new(foot.X, groundAt(Vector3.new(foot.X, base.Y, foot.Z)) + half - F.Imprint.depth, foot.Z)
	local _, size = tree:GetBoundingBox()
	local h = size.Y
	-- lie clear of the ground all along it (user 2026-10-17: it "often appears below the map")
	local reach = h * F.tipShare
	local samples = {}
	for k = 1, F.samples do
		local x = reach * k / F.samples
		local at = hinge + dir * x
		local y = Ground.heightAt(at.X, at.Z, hinge.Y + h, h * 2 + 60)
		if y then
			-- its underside down in its imprint (Fall.Imprint.depth under the ground), tapering toward the top
			local clear = half * (1 - (1 - F.tipClear) * k / F.samples) - F.Imprint.depth
			table.insert(samples, { x, y - hinge.Y + clear })
		end
	end
	local tilt = math.rad(Rules.clearTilt(samples, F.minTilt, F.maxTilt))
	local axis = Vector3.new(0, 1, 0):Cross(dir)
	-- turned about its own axis at the hinge's height, then moved over to the hinge
	local pin = Vector3.new(base.X, hinge.Y, base.Z)
	local turn = CFrame.new(pin) * CFrame.fromAxisAngle(axis, tilt) * CFrame.new(-pin)
	-- the butt rests on the hinge: slide it out along the fallen trunk by what sat under the hinge
	local under = hinge.Y - pivot.Y
	local lie = CFrame.new(turn:VectorToWorldSpace(Vector3.yAxis) * under + dir * off) * turn * pivot
	if leaveStump then
		stump(tree, trunk, base)
	else
		-- uprooted: a pit where the roots were
		local R = F.Roots
		local r = math.clamp(thickness(trunk) * R.radius, R.min, R.max)
		Ground.ball(
			Vector3.new(base.X, ground - r * R.pitSink, base.Z) - dir * r * R.pitBack,
			r * R.pit,
			Enum.Material.Air
		)
	end
	tree:SetAttribute("FallTo", lie)
	tree:SetAttribute("FallTime", F.time)
	tree:SetAttribute("FallLength", h)
	tree:SetAttribute("FallHinge", hinge)
	tree:SetAttribute("FallAxis", axis)
	tree:SetAttribute("Thickness", thickness(trunk))
	tree:SetAttribute("HP", full * T.Fallen.share) -- it lies with HP again (user: "continue HP")
	CollectionService:AddTag(tree, TreeCfg.FallingTag)
	task.delay(F.time, function()
		if not tree.Parent then
			return
		end
		ghostWhileInside(trunk)
		tree:PivotTo(lie)
		if fadeAway then
			if crush then
				crush(hinge, hinge + lie.UpVector * reach, F.Crush.radius * sc, F.Crush.damage, F.Crush.knock)
			end
			sink(tree) -- fades out where it landed
			return
		end
		CollectionService:AddTag(tree, TreeCfg.FallenTag)
		shed(tree) -- a felled tree's leaves go to 0 (user)
		-- who it lands on
		if crush then
			crush(hinge, hinge + lie.UpVector * reach, F.Crush.radius * sc, F.Crush.damage, F.Crush.knock)
		end
		-- its imprint: it lies pressed into the ground (above); the ground round it churned to mud where it lies on it
		local I = F.Imprint
		local cot = 1 / math.tan(tilt)
		local x = 0
		while x <= reach do
			local at = hinge + dir * x
			local y = Ground.heightAt(at.X, at.Z, hinge.Y + h, h * 2 + 60)
			local bottom = hinge.Y + x * cot - half -- the trunk's underside here
			if y and bottom - y <= I.touch then
				Ground.churn(Vector3.new(at.X, y, at.Z), I.churnRadius, I.churnDepth, I)
			end
			x += I.step
		end
		if not leaveStump then
			local R = F.Roots
			local r = math.clamp(thickness(trunk) * R.radius, R.min, R.max)
			Ground.ball(
				Vector3.new(hinge.X, ground + r * (R.rise - 1) + half, hinge.Z),
				r,
				(Enum.Material :: any)[R.material]
			)
			Ground.churn(base, r * 1.5, r, F.Imprint)
		end
	end)
	table.insert(fallen, tree)
	while #fallen > F.maxFallen do
		sink(fallen[1])
	end
	task.delay(F.time + F.lifetime, sink, tree)
end

-- A trunk destroyed outright (a direct full beam; user 2026-10-18: "they should just fall down but fade away"): a
-- standing tree falls along the beam above its stump and fades out as it lands; a fallen one fades out where it lies.
-- No debris.
local function shatter(tree: Model, direction: Vector3)
	if standing(tree) then
		fell(tree, direction, true, true)
	elseif lying(tree) then
		sink(tree)
	end
end

-- A tree blown apart by a blast at `origin` (Config/Damage.Blast.Tree.splinter; user 2026-10-23: extreme damage
-- destroys, like the building sections; 2026-10-24: "a direct hit from a howitzer should destroy the trees hit directly
-- from the blast"): it is gone, no trunk and no stump, only a puff of splinters (pulverised debris, "dust", on every
-- client: Net "SectionBroken").
local function splinter(tree: Model, origin: Vector3)
	local trunk = tree:FindFirstChild("Trunk") :: BasePart?
	if not trunk then
		return
	end
	local pieces = {}
	for _, d in tree:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(pieces, { cf = d.CFrame, size = d.Size, color = d.Color, t = 0, m = "dust" })
		end
	end
	if #pieces > 0 then
		Net.event("SectionBroken"):FireAllClients(pieces, origin)
	end
	local i = table.find(fallen, tree)
	if i then
		table.remove(fallen, i)
	end
	tree:Destroy()
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

-- a shovel's Destroy swing at the tree `part` belongs to, from `from` (src/server/Build): a share of its MaxHP
-- (Config/Damage.Trees.Chop.swings fell it), falling away from the swing and leaving a stump. Whether it was a tree.
function Trees.chop(part: Instance?, from: Vector3): boolean
	local tree = treeOf(part)
	if not tree or not standing(tree) then
		return false
	end
	local trunk = tree:FindFirstChild("Trunk")
	if not trunk or not trunk:IsA("BasePart") then
		return false
	end
	local _, max = hp(tree)
	hurt(tree, max / T.Chop.swings + 1e-6, flat(trunk.Position - from), true)
	return true
end

-- a staff beam of `stage` hitting `part` straight on along `direction` (Trees.Direct): a trunk loses HP, enough fells it
-- along the beam above a stump; a full beam shatters it
function Trees.direct(part: Instance?, stage: number, direction: Vector3)
	local tree = treeOf(part)
	if not tree or not part or part.Name ~= "Trunk" then
		return
	end
	local amount, blown = Rules.directHit(stage, T.Direct)
	if blown then
		shatter(tree, direction)
	elseif amount > 0 then
		hurt(tree, amount, direction, true)
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
-- felling = false: only the leaves are hurt (a grenade's, Config/Grenades: user 2026-10-18 "a grenade should only strip it
-- leaves and shake it, no falling"); every client shakes the trees from the blast's "Explosion" anyway.
function Trees.blast(position: Vector3, reach: number, kpaAt: (number) -> number, felling: boolean?)
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
		if d <= reach and felling ~= false then
			local _, full = hp(tree)
			local kpa = kpaAt(d)
			local amount, whole = Rules.blastDamage(kpa, B.Tree.fail, full, B.Tree.weaken)
			if BlastRules.band(kpa, B.Tree.fail, B.Tree.splinter) == "destroy" then
				splinter(tree, position)
			elseif amount > 0 then
				hurt(tree, amount, at - position, false, whole)
			end
		end
	end
	-- stumps the blast's crater left standing over nothing go too
	for i = #stumps, 1, -1 do
		local p = stumps[i]
		if not p.Parent then
			table.remove(stumps, i)
		elseif (p.Position - position).Magnitude <= reach then
			local bottom = p.Position.Y - p.Size.X / 2
			if groundAt(p.Position) < bottom + T.Stump.floatTolerance then
				table.remove(stumps, i)
				p:Destroy()
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
