--!strict
-- Tilts the local soldier's torso with the camera's pitch (Config/Locomotion.LookTilt): look up and the torso
-- leans back a little, look down and it leans forward. Only the torso (head and arms ride on it) tilts: it turns
-- about the waist, the hip line where the legs join, and the hips turn back by the same angle so the legs stay
-- planted. Applied on top of the animations through the RootJoint and hip C0s. Local only for now.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Locomotion)

local LookTilt = {}

local WAIST = Vector3.new(0, -1, 0) -- the hip line, in the torso's own space (R6 torso is 2 tall)

-- c0 turned by `angle` (radians, + tips the top back) about `pivot`, in the parent part's axes
local function turned(c0: CFrame, pivot: Vector3, angle: number): CFrame
	return CFrame.new(pivot) * CFrame.Angles(angle, 0, 0) * CFrame.new(-pivot) * c0
end

local function attach(character: Model)
	local cfg = Cfg.LookTilt
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart")
	local torso = character:WaitForChild("Torso")
	local rootJoint = root:WaitForChild("RootJoint") :: Motor6D
	local hips = { torso:WaitForChild("Left Hip") :: Motor6D, torso:WaitForChild("Right Hip") :: Motor6D }
	local rootC0 = rootJoint.C0
	local hipC0 = { hips[1].C0, hips[2].C0 }
	local angle = 0

	local step = RunService.RenderStepped:Connect(function(dt)
		local camera = workspace.CurrentCamera
		local pitch = if camera and humanoid.Health > 0
			then math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
			else 0
		local target = math.clamp(pitch * cfg.Torso, -cfg.TorsoMax, cfg.TorsoMax)
		angle += (target - angle) * (1 - math.exp(-cfg.Smoothing * dt))
		local a = math.rad(angle)
		-- the waist where the animation currently puts it, in the root's space
		local waist = (rootC0 * rootJoint.Transform * rootJoint.C1:Inverse()) * WAIST
		rootJoint.C0 = turned(rootC0, waist, a)
		for i, hip in hips do
			hip.C0 = turned(hipC0[i], hipC0[i].Position, -a)
		end
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
