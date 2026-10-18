--!strict
-- Fades the out-of-bounds walls in as the local player approaches: each side as one wall, by the distance to that side
-- (its pieces carry the whole side as "SideFrom" / "SideTo"; a panel without them fades on its own).

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
			local a, b = p:GetAttribute("SideFrom"), p:GetAttribute("SideTo")
			local d
			if typeof(a) == "Vector3" and typeof(b) == "Vector3" and (b - a).Magnitude > 0 then
				local mid, dir = (a + b) / 2, (b - a).Unit
				d = Rule.distanceToPanel(pos.X, pos.Z, mid.X, mid.Z, dir.X, dir.Z, (b - a).Magnitude)
			else
				local right = p.CFrame.RightVector
				d = Rule.distanceToPanel(pos.X, pos.Z, p.Position.X, p.Position.Z, right.X, right.Z, p.Size.X)
			end
			-- Panel base transparency is 1 - MaxOpacity; the modifier scales it toward fully invisible.
			p.LocalTransparencyModifier = 1 - Rule.fade(d, Cfg.FadeNear, Cfg.FadeFar)
		end
	end)
end

return BoundaryFade
