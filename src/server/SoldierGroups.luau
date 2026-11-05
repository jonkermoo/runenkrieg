--!strict
-- The soldiers' collision groups (Config/Collision, Rules/Collision; user 2026-11-04, teammates only): every soldier's
-- parts (players, bots, dev dummies) are in its team's group, whose soldiers pass through each other and bump into the
-- other teams'. In a free-for-all match, or before a soldier has a kit, it is in the shared "Characters" group, which
-- collides with itself. A soldier's group follows its "Kit" and the workspace's FreeForAll attribute. Also the camera
-- sweep's group (src/client/WeaponCamera): through every soldier.
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Collision)
local U = require(Shared.Config.Uniforms)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local Rules = require(Shared.Rules.Collision)

local SoldierGroups = {}

local ALL = Rules.groups(U.Kits, Cfg)
local tracked: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function ensure(name: string)
	if not PhysicsService:IsCollisionGroupRegistered(name) then
		PhysicsService:RegisterCollisionGroup(name)
	end
end

-- Registers every soldier group and how they meet, then the camera's group (against every group registered so far,
-- as Default: so call it once the groups it should pass, Config/Collision.Through, are registered).
function SoldierGroups.register()
	for _, g in ALL do
		ensure(g)
	end
	for _, a in ALL do
		for _, b in ALL do
			PhysicsService:CollisionGroupSetCollidable(a, b, Rules.collides(a, b, Cfg))
		end
	end
	ensure(Cfg.Camera)
	for _, g in PhysicsService:GetRegisteredCollisionGroups() do
		local hits = Rules.cameraHits(g.name, PhysicsService:CollisionGroupsAreCollidable("Default", g.name), Cfg)
		PhysicsService:CollisionGroupSetCollidable(Cfg.Camera, g.name, hits)
	end
end

-- Sets group `other` against every soldier group alike (as it was set against "Characters").
function SoldierGroups.setWith(other: string, collides: boolean)
	ensure(other)
	for _, g in ALL do
		PhysicsService:CollisionGroupSetCollidable(other, g, collides)
	end
end

-- Whether a part's group is a soldier group (so a regroup leaves the drag's and the ragdoll's own groups alone).
function SoldierGroups.isSoldier(name: string): boolean
	return Rules.isSoldier(name, Cfg)
end

local function groupOf(model: Model): string
	return Rules.groupOf(
		model:GetAttribute("Kit"),
		workspace:GetAttribute(ZoneCfg.FreeForAllAttribute) == true,
		U.Kits,
		Cfg
	)
end

local function regroup(model: Model)
	local g = groupOf(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.CollisionGroup ~= g and Rules.isSoldier(d.CollisionGroup, Cfg) then
			d.CollisionGroup = g
		end
	end
end

-- Puts soldier `model`'s parts, and every part added to it later, in its group, and keeps them there as its kit or
-- the match's free-for-all changes.
function SoldierGroups.track(model: Model)
	local g = groupOf(model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = g
		end
	end
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = groupOf(model)
		end
	end)
	model:GetAttributeChangedSignal("Kit"):Connect(function()
		regroup(model)
	end)
	tracked[model] = true
end

workspace:GetAttributeChangedSignal(ZoneCfg.FreeForAllAttribute):Connect(function()
	for model in tracked do
		if model.Parent then
			regroup(model)
		end
	end
end)

return SoldierGroups
