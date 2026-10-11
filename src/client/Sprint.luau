--!strict
-- Hold Shift to sprint (Config/Locomotion, speeds from Config/Metrics.Movement). Unlimited stamina.
-- Sets the local character's Humanoid.WalkSpeed (the client owns its character's physics) and a "Sprinting"
-- attribute on the character for systems that must block during a sprint (firing, aiming: later).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Locomotion)
local M = require(Shared.Config.Metrics)

local Sprint = {}

function Sprint.start()
	local player = Players.LocalPlayer
	local held = false

	local function apply()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		humanoid.WalkSpeed = if held then M.Movement.SprintSpeed else M.Movement.WalkSpeed
		character:SetAttribute("Sprinting", held)
	end

	local keys = {}
	for _, k in Cfg.SprintKeys do
		table.insert(keys, (Enum.KeyCode :: any)[k])
	end
	ContextActionService:BindAction("Sprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			held = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			held = false
		end
		apply()
		return Enum.ContextActionResult.Pass
	end, false, table.unpack(keys))

	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Humanoid")
		apply()
	end)
end

return Sprint
