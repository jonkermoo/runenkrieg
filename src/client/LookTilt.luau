--!strict
-- Tilts the local soldier's torso with the camera's pitch (Config/Locomotion.LookTilt): look up and the torso
-- leans back a little, look down and it leans forward. Only the torso (head and arms ride on it) tilts: it turns
-- about the waist, the hip line where the legs join, and the hips turn back by the same angle so the legs stay
-- planted. Applied on top of the animations through the RootJoint and hip C0s. Local only for now.
-- With a weapon in the hands (Config/Camera.Follow): the arms and the gun turn about the shoulder line for the rest
-- of the pitch, so the weapon points where the camera looks, and the head follows part of the way. (In first person
-- the player sees the viewmodel instead, src/client/Viewmodel.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion)
local CameraCfg = require(Shared.Config.Camera)
local Held = require(script.Parent.Held)

local LookTilt = {}

local WAIST = Vector3.new(0, -1, 0) -- the hip line, in the torso's own space (R6 torso is 2 tall)
local SHOULDERS = Vector3.new(0, 0.5, 0) -- a point on the shoulder line (through both shoulder joints, along X)
-- after Roblox's camera (Free mode and no weapon) and before src/client/WeaponCamera places the camera
LookTilt.Priority = Enum.RenderPriority.Camera.Value + 1

-- c0 turned by `angle` (radians, + tips the top back) about `pivot`, in the parent part's axes
local function turned(c0: CFrame, pivot: Vector3, angle: number): CFrame
	return CFrame.new(pivot) * CFrame.Angles(angle, 0, 0) * CFrame.new(-pivot) * c0
end

local function ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

local count = 0

local function attach(character: Model)
	local cfg = Cfg.LookTilt
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart")
	local torso = character:WaitForChild("Torso")
	local rootJoint = root:WaitForChild("RootJoint") :: Motor6D
	local hips = { torso:WaitForChild("Left Hip") :: Motor6D, torso:WaitForChild("Right Hip") :: Motor6D }
	local arms = { torso:WaitForChild("Right Shoulder") :: Motor6D, torso:WaitForChild("Left Shoulder") :: Motor6D }
	local neck = torso:WaitForChild("Neck") :: Motor6D
	local rootC0 = rootJoint.C0
	local hipC0 = { hips[1].C0, hips[2].C0 }
	local armC0 = { arms[1].C0, arms[2].C0 }
	local neckC0 = neck.C0
	local angle = 0

	count += 1
	local name = "LookTilt" .. count
	RunService:BindToRenderStep(name, LookTilt.Priority, function(dt)
		local camera = workspace.CurrentCamera
		local pitch = if camera and humanoid.Health > 0
			then math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1)))
			else 0
		local target = math.clamp(pitch * cfg.Torso, -cfg.TorsoMax, cfg.TorsoMax)
		angle += (target - angle) * ease(cfg.Smoothing, dt)
		local a = math.rad(angle)
		-- the waist where the animation currently puts it, in the root's space
		local waist = (rootC0 * rootJoint.Transform * rootJoint.C1:Inverse()) * WAIST
		rootJoint.C0 = turned(rootC0, waist, a)
		for i, hip in hips do
			hip.C0 = turned(hipC0[i], hipC0[i].Position, -a)
		end

		-- the weapon: the rest of the pitch about the shoulder line
		local weapon = Held.weapon(character)
		local state = character:GetAttribute("Hold")
		local turn = if weapon and type(state) == "string" then (CameraCfg.Follow[state] or 0) * pitch - angle else 0
		local swing = CFrame.new(SHOULDERS) * CFrame.Angles(math.rad(turn), 0, 0) * CFrame.new(-SHOULDERS)
		for i, arm in arms do
			arm.C0 = swing * armC0[i]
		end
		if weapon then
			weapon.hold.C0 = swing
		end
		neck.C0 = turned(neckC0, neckC0.Position, math.rad(turn * CameraCfg.HeadFollow))
	end)
	character.Destroying:Connect(function()
		RunService:UnbindFromRenderStep(name)
	end)
	humanoid.Died:Connect(function()
		RunService:UnbindFromRenderStep(name)
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
