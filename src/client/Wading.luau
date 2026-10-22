--!strict
-- Water (Config/Locomotion.Wading, Rules/Wading; user 2026-10-22: "remove swimming. just slow players down when they
-- are submerged hip below in water"). The local soldier never swims: Roblox's Swimming state is off on its Humanoid
-- (the client owns its character's physics), and a downward force on the root cancels the water's lift so it walks on
-- the bottom instead of floating up. The water's depth over the feet is read from the terrain voxels under the root
-- every frame; from hip-deep the soldier slows, the share eased in and out and written to the character's "WadeScale"
-- attribute, which src/client/Stance multiplies into the walk speed. Ragdolled or dead: no force (the body floats).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion).Wading
local M = require(Shared.Config.Metrics)
local Rules = require(Shared.Rules.Wading)

local RES = 4 -- terrain voxel size
local WATER_DENSITY = 1 -- Roblox's water, in the units of part density

local Wading = {}

-- the water's surface over the feet at `x, z` (nil: no water at the feet)
local function surfaceAt(x: number, z: number, feetY: number): number?
	local base = math.floor(feetY / RES) * RES - RES
	local region = Region3.new(Vector3.new(x - 0.1, base, z - 0.1), Vector3.new(x + 0.1, base + RES * 4, z + 0.1))
		:ExpandToGrid(RES)
	local mats, occs = workspace.Terrain:ReadVoxels(region, RES)
	local size = mats.Size
	local y0 = region.CFrame.Position.Y - region.Size.Y / 2
	local water, occ = {}, {}
	for iy = 1, size.Y do
		water[iy] = mats[1][iy][1] == Enum.Material.Water
		occ[iy] = occs[1][iy][1]
	end
	return Rules.surface(water, occ, y0, RES, feetY)
end

function Wading.start()
	local player = Players.LocalPlayer
	local scale = 1
	local force: VectorForce? = nil

	local function hook(character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		local root = character:WaitForChild("HumanoidRootPart") :: BasePart
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
		scale = 1
		local attachment = Instance.new("Attachment")
		attachment.Name = "WadeSinkAttachment"
		attachment.Parent = root
		local f = Instance.new("VectorForce")
		f.Name = "WadeSink"
		f.Attachment0 = attachment
		f.RelativeTo = Enum.ActuatorRelativeTo.World
		f.ApplyAtCenterOfMass = true
		f.Force = Vector3.zero
		f.Parent = root
		force = f
	end
	player.CharacterAdded:Connect(hook)
	if player.Character then
		task.spawn(hook, player.Character)
	end

	RunService.Heartbeat:Connect(function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not character or not humanoid or not root or not force or force.Parent ~= root then
			return
		end
		local feet = root.Position.Y - root.Size.Y / 2 - M.Character.LegLength
		local surface = surfaceAt(root.Position.X, root.Position.Z, feet)
		local depth = Rules.depth(surface, feet)
		local target = Rules.scale(depth, Cfg.From, Cfg.Full, Cfg.Slow)
		scale = Rules.ease(scale, target, Cfg.Rate, dt)
		if math.abs(scale - target) < 1e-3 then
			scale = target -- (the ease never quite arrives)
		end
		-- written when it has moved enough to matter, or arrived (Stance re-applies the speed on every write)
		local written = character:GetAttribute("WadeScale")
		local shown = if type(written) == "number" then written else 1
		if math.abs(scale - shown) > 1e-2 or (scale == target and scale ~= shown) then
			character:SetAttribute("WadeScale", if scale == 1 then nil else scale)
		end
		-- the water's lift on every part (body, gear, weapon), pushed back down while the soldier stands in it
		local lift = 0
		local limp = character:GetAttribute("Ragdolled") == true or humanoid.Health <= 0
		if surface and not limp then
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") then
					local s = part.Size
					local height = math.abs(part.CFrame.UpVector.Y) * s.Y
						+ math.abs(part.CFrame.RightVector.Y) * s.X
						+ math.abs(part.CFrame.LookVector.Y) * s.Z
					lift += Rules.submerged(s.X * s.Y * s.Z, part.Position.Y, height, surface)
				end
			end
		end
		force.Force = Vector3.new(0, -lift * WATER_DENSITY * workspace.Gravity * Cfg.Sink, 0)
	end)
end

return Wading
