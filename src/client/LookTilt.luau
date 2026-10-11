--!strict
-- Tilts the local soldier with the camera's pitch (Config/Locomotion.LookTilt): look up and the body leans back a
-- little and the head tips up; look down and both lean forward. Applied on top of the animations by rotating the
-- RootJoint and Neck C0 about their pivots. Local only for now: other players see the plain animations.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Locomotion)

local LookTilt = {}

-- c0 rotated by `angle` (radians, + tips the top back) about the joint's pivot, in the parent part's axes
local function tilted(c0: CFrame, angle: number): CFrame
	return CFrame.new(c0.Position) * CFrame.Angles(angle, 0, 0) * c0.Rotation
end

local function attach(character: Model)
	local cfg = Cfg.LookTilt
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart")
	local torso = character:WaitForChild("Torso")
	local rootJoint = root:WaitForChild("RootJoint") :: Motor6D
	local neck = torso:WaitForChild("Neck") :: Motor6D
	local rootC0, neckC0 = rootJoint.C0, neck.C0
	local torsoAngle, headAngle = 0, 0

	local step = RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		local pitch = if camera and humanoid.Health > 0
			then math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
			else 0
		local k = 1 - math.exp(-cfg.Smoothing * dt)
		torsoAngle += (math.clamp(pitch * cfg.Torso, -cfg.TorsoMax, cfg.TorsoMax) - torsoAngle) * k
		headAngle += (math.clamp(pitch * cfg.Head, -cfg.HeadMax, cfg.HeadMax) - headAngle) * k
		rootJoint.C0 = tilted(rootC0, math.rad(torsoAngle))
		neck.C0 = tilted(neckC0, math.rad(headAngle))
	end)
	character.Destroying:Connect(function()
		step:Disconnect()
	end)
end

function LookTilt.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(attach)
	if player.Character then
		task.spawn(attach, player.Character)
	end
end

return LookTilt
