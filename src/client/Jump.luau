--!strict
-- The soldier's hop (Config/Metrics.Movement): near the top of a jump a VectorForce cancels part of gravity so the
-- peak hangs, and after landing jumping is switched off for a short cooldown. The client owns its character's
-- physics, so both act on the local character only.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local M = require(ReplicatedStorage:WaitForChild("Shared").Config.Metrics)

local Jump = {}

local function attach(character: Model)
	local mv = M.Movement
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local root = character:WaitForChild("HumanoidRootPart") :: BasePart

	local att = Instance.new("Attachment")
	att.Name = "JumpFloat"
	att.Parent = root
	local float = Instance.new("VectorForce")
	float.Name = "JumpFloat"
	float.Attachment0 = att
	float.RelativeTo = Enum.ActuatorRelativeTo.World
	float.ApplyAtCenterOfMass = true
	float.Force = Vector3.zero
	float.Parent = root

	local jumping = false
	humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			jumping = true
		elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
			if jumping then
				humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
				task.delay(mv.JumpCooldown, function()
					if humanoid.Parent then
						humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
					end
				end)
			end
			jumping = false
		elseif new ~= Enum.HumanoidStateType.Freefall then
			jumping = false -- climbing, swimming, dead...
		end
	end)

	local step = RunService.Heartbeat:Connect(function()
		local hang = jumping and math.abs(root.AssemblyLinearVelocity.Y) < mv.JumpApexSpeed
		float.Force = if hang
			then Vector3.new(0, root.AssemblyMass * workspace.Gravity * mv.JumpApexGravityCut, 0)
			else Vector3.zero
	end)
	character.Destroying:Connect(function()
		step:Disconnect()
	end)
end

function Jump.start()
	local player = Players.LocalPlayer
	player.CharacterAdded:Connect(attach)
	if player.Character then
		task.spawn(attach, player.Character)
	end
end

return Jump
