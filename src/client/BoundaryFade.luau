--!strict
-- Fades out-of-bounds panels in as the local player approaches. Each panel fades on its own,
-- so only the stretch of wall near the player lights up.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Boundary)
local Rule = require(Shared.Rules.Boundary)

local BoundaryFade = {}

function BoundaryFade.start()
	local player = Players.LocalPlayer
	local panels: { BasePart } = {}

	local function add(inst: Instance)
		if inst:IsA("BasePart") then
			inst.LocalTransparencyModifier = 1
			table.insert(panels, inst)
		end
	end
	local function remove(inst: Instance)
		local i = table.find(panels, inst :: any)
		if i then
			table.remove(panels, i)
		end
	end
	for _, inst in CollectionService:GetTagged(Cfg.Tag) do
		add(inst)
	end
	CollectionService:GetInstanceAddedSignal(Cfg.Tag):Connect(add)
	CollectionService:GetInstanceRemovedSignal(Cfg.Tag):Connect(remove)

	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 1 / Cfg.UpdateHz then
			return
		end
		acc = 0
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return
		end
		local pos = root.Position
		for _, p in panels do
			local right = p.CFrame.RightVector
			local d = Rule.distanceToPanel(pos.X, pos.Z, p.Position.X, p.Position.Z, right.X, right.Z, p.Size.X)
			-- Panel base transparency is 1 - MaxOpacity; the modifier scales it toward fully invisible.
			p.LocalTransparencyModifier = 1 - Rule.fade(d, Cfg.FadeNear, Cfg.FadeFar)
		end
	end)
end

return BoundaryFade
