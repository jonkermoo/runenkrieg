--!strict
-- Turns the local soldier's body (Config/Camera.Turn; user 2026-10-20: "make movement always smooth and never snappy",
-- the head first and the body catching up). It owns the body's facing in place of Roblox's AutoRotate, each turn a
-- critically damped spring (Rules/Camera.spring), so the body never snaps round:
-- - first person, aiming, the staff, and a gun in third person ("CameraMode" "Third", src/client/WeaponCamera; user
--   2026-10-20: "make the gun always aim towards your general crosshair in third person"): the body faces the view,
--   fast, walking sideways or back included;
-- - nothing in the hands (Roblox's camera): the body turns to where it walks, or to the view in Roblox's first person
--   or mouse lock; standing still it stays. Healing someone (src/client/Healing), it faces the patient instead.
-- Ragdolled, seated, climbing, swimming, knocked down or dead: left alone (nor is it rewritten when nothing turns).

local FREE = {
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Seated] = true,
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Camera)
local Rules = require(Shared.Rules.Camera)

local BodyTurn = {}

local function yawOf(look: Vector3): number
	return math.deg(math.atan2(-look.X, -look.Z))
end

function BodyTurn.start()
	local player = Players.LocalPlayer
	local body: Model? = nil -- the body the state below belongs to
	local yaw, speed = 0, 0 -- the facing (degrees, unwrapped) and its turn rate

	-- after src/client/WeaponCamera has turned the view this frame
	RunService:BindToRenderStep("BodyTurn", Enum.RenderPriority.Input.Value + 2, function(dt)
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local camera = workspace.CurrentCamera
		if not character or not humanoid or not root or not camera then
			return
		end
		humanoid.AutoRotate = false
		if body ~= character then
			body, yaw, speed = character, yawOf(root.CFrame.LookVector), 0
		end
		if
			humanoid.Health <= 0
			or humanoid.Sit
			or humanoid.PlatformStand
			or FREE[humanoid:GetState()]
			or character:GetAttribute("Ragdolled") == true
		then
			yaw, speed = yawOf(root.CFrame.LookVector), 0
			return
		end
		yaw += Rules.wrap(yawOf(root.CFrame.LookVector) - yaw) -- (anything else that turned it: carry on from there)

		local T = Cfg.Turn
		local look = yawOf(camera.CFrame.LookVector)
		local mode = character:GetAttribute("CameraMode")
		local moving = humanoid.MoveDirection.Magnitude > T.Moving
		local target, rate = yaw, T.Walk
		if mode ~= nil then -- "Third", "First", "Aim", "ThirdAim"
			target, rate = yaw + Rules.wrap(look - yaw), T.Face
		else
			local first = (camera.CFrame.Position - camera.Focus.Position).Magnitude < T.FirstBelow
			-- healing someone (src/server/Healing "HealPatient"): out of first person, facing the patient
			local link = character:GetAttribute("Healing") ~= nil
				and character:FindFirstChild("HealPatient") :: ObjectValue?
			local patient = link and link.Value
			local theirs = patient and patient:FindFirstChild("HumanoidRootPart") :: BasePart?
			local to = theirs and (theirs.Position - root.Position) * Vector3.new(1, 0, 1)
			if not first and to and to.Magnitude > 1e-3 then
				target, rate = yaw + Rules.wrap(yawOf(to) - yaw), T.Face
			elseif first or UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
				target = yaw + Rules.wrap(look - yaw)
			elseif moving then
				target = yaw + Rules.wrap(yawOf(humanoid.MoveDirection) - yaw)
			end
		end
		if math.abs(target - yaw) < T.Still and math.abs(speed) < T.Still then
			speed = 0
			return -- nothing turning: leave the body to the physics
		end
		yaw, speed = Rules.spring(yaw, speed, target, rate, dt)
		root.CFrame = CFrame.new(root.Position) * CFrame.fromOrientation(0, math.rad(yaw), 0)
	end)
end

return BodyTurn
