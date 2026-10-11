--!strict
-- The soldier's stance controls (Config/Locomotion keys; speeds from Config/Metrics.Movement):
-- - hold Shift to sprint, unlimited stamina (user 2026-10-11), only while moving forward relative to the camera
--   (user reference video: strafing or backing up with Shift stays a walk; Config/Locomotion.SprintCone);
-- - hold right mouse to aim down the sights while a weapon is in the hands; never while sprinting (Shift wins).
-- Sets the local character's Humanoid.WalkSpeed (the client owns its character's physics) and the "Sprinting" /
-- "Aiming" attributes that the animations, the camera and the weapon code read (local only).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion)
local M = require(Shared.Config.Metrics)
local Held = require(script.Parent.Held)

local Stance = {}

local function keys(names: { string }): { Enum.KeyCode | Enum.UserInputType }
	local out = {}
	for _, k in names do
		-- a key ("LeftShift") or a button ("MouseButton2"); indexing an enum with a name it lacks throws
		local ok, key = pcall(function()
			return (Enum.KeyCode :: any)[k]
		end)
		table.insert(out, if ok then key else (Enum.UserInputType :: any)[k])
	end
	return out
end

function Stance.start()
	local player = Players.LocalPlayer
	local sprintHeld, aimHeld = false, false

	local cone = math.cos(math.rad(Cfg.SprintCone))
	-- moving within the cone around where the camera looks (flat), or standing still (Shift down, about to go)
	local function forward(humanoid: Humanoid): boolean
		local move = humanoid.MoveDirection
		if move.Magnitude < 0.1 then
			return true
		end
		local look = workspace.CurrentCamera.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		return flat.Magnitude > 1e-3 and flat.Unit:Dot(move.Unit) >= cone
	end

	local function apply()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not character or not humanoid then
			return
		end
		local sprinting = sprintHeld and forward(humanoid)
		local aiming = aimHeld and not sprinting and Held.weapon(character) ~= nil
		humanoid.WalkSpeed = if sprinting
			then M.Movement.SprintSpeed
			elseif aiming then M.Movement.AimWalkSpeed
			else M.Movement.WalkSpeed
		character:SetAttribute("Sprinting", sprinting)
		character:SetAttribute("Aiming", aiming)
	end

	local function held(flag: (boolean) -> ()): (string, Enum.UserInputState, InputObject) -> Enum.ContextActionResult
		return function(_, state)
			if state == Enum.UserInputState.Begin then
				flag(true)
			elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
				flag(false)
			end
			apply()
			return Enum.ContextActionResult.Pass
		end
	end
	ContextActionService:BindAction(
		"Sprint",
		held(function(on)
			sprintHeld = on
		end),
		false,
		table.unpack(keys(Cfg.SprintKeys))
	)
	ContextActionService:BindAction(
		"Aim",
		held(function(on)
			aimHeld = on
		end),
		false,
		table.unpack(keys(Cfg.AimKeys))
	)

	local function hook(character: Model)
		character:WaitForChild("Humanoid")
		apply()
		-- equipping or putting away a weapon starts or ends aiming while the button stays held
		character.ChildAdded:Connect(apply)
		character.ChildRemoved:Connect(apply)
	end
	player.CharacterAdded:Connect(hook)
	if player.Character then
		task.spawn(hook, player.Character)
	end
	-- the direction changes without any key event (turning the camera, letting go of W)
	RunService.Heartbeat:Connect(function()
		if sprintHeld then
			apply()
		end
	end)
end

return Stance
