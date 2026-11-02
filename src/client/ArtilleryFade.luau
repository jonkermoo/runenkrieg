--!strict
-- Trees and buildings out of the gunner's way (Config/Artillery.ViewFade; user 2026-11-02: "make surrounding /
-- blocking trees/houses more transparent to prevent them from blocking the artys view"): while I'm on a field gun or
-- howitzer (its "Gunner" is me), rays from the camera through the screen (Rules/Artillery.sightPoints) find the trees
-- and buildings in the way, and those fade see-through on this client only (LocalTransparencyModifier); each comes back
-- a moment after no ray crosses it, and all of them once I'm off the gun.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local Rules = require(Shared.Rules.Artillery)

local ArtilleryFade = {}

local F = Cfg.ViewFade

type Faded = { parts: { BasePart }, now: number, seenAt: number }

-- the tree or building `part` is part of (a Model tagged one of F.tags), or nil
local function owner(part: Instance): Model?
	local m = part:FindFirstAncestorOfClass("Model")
	while m do
		for _, tag in F.tags do
			if CollectionService:HasTag(m, tag) then
				return m
			end
		end
		m = m:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function partsOf(model: Model): { BasePart }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

function ArtilleryFade.start()
	local player = Players.LocalPlayer
	local camera = workspace.CurrentCamera
	local faded: { [Model]: Faded } = {}
	local points = Rules.sightPoints(F.cols, F.rows, F.box)
	local castAt = 0

	-- my field gun or howitzer, if I'm on one
	local function mine(): Model?
		local f = workspace:FindFirstChild(Cfg.Folder)
		if not f then
			return nil
		end
		for _, m in f:GetChildren() do
			local gun = Cfg.Guns[m:GetAttribute("Gun") :: any]
			if m:IsA("Model") and m:GetAttribute("Gunner") == player.UserId and gun and not gun.mg then
				return m
			end
		end
		return nil
	end

	-- everything the sight crosses now, marked seen at `t`
	local function cast(gun: Model, t: number)
		local skip: { Instance } = { gun }
		if player.Character then
			table.insert(skip, player.Character)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.IgnoreWater = true
		local size = camera.ViewportSize
		for _, pt in points do
			local ray = camera:ViewportPointToRay(pt[1] * size.X, pt[2] * size.Y)
			local from, left = ray.Origin, F.far
			local passed = table.clone(skip)
			for _ = 1, F.depth do
				params.FilterDescendantsInstances = passed
				local hit = workspace:Raycast(from, ray.Direction * left, params)
				if not hit or hit.Instance == workspace.Terrain then
					break -- (open air or the ground: the sight ends here)
				end
				-- (anything else, a sandbag or a fence, is looked past)
				local m = owner(hit.Instance)
				if m then
					local f = faded[m]
					if not f then
						f = { parts = partsOf(m), now = 0, seenAt = t }
						faded[m] = f
					end
					f.seenAt = t
				end
				table.insert(passed, m or hit.Instance)
				left -= (hit.Position - from).Magnitude
				from = hit.Position
				if left <= 0 then
					break
				end
			end
		end
	end

	RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		local gun = mine()
		if gun and t - castAt >= F.every then
			castAt = t
			cast(gun, t)
		end
		for m, f in faded do
			local want = if gun and m.Parent and t - f.seenAt < F.hold then F.see else 0
			f.now = Rules.fadeStep(f.now, want, F.rate, dt)
			for _, p in f.parts do
				p.LocalTransparencyModifier = f.now
			end
			if f.now <= 0 and want <= 0 then
				faded[m] = nil
			end
		end
	end)
end

return ArtilleryFade
