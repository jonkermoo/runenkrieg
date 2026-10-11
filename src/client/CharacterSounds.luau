--!strict
-- Mutes Roblox's built-in character sounds listed in Config/Locomotion.MutedSounds (footsteps, jump, landing) on
-- every character. RbxCharacterSounds creates them on each client inside the HumanoidRootPart; it keeps playing
-- them, so they are silenced (volume 0, held there) rather than destroyed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Locomotion)

local CharacterSounds = {}

local function mute(inst: Instance)
	if inst:IsA("Sound") and table.find(Cfg.MutedSounds, inst.Name) then
		inst.Volume = 0
		inst:GetPropertyChangedSignal("Volume"):Connect(function()
			if inst.Volume ~= 0 then
				inst.Volume = 0
			end
		end)
	end
end

local function watch(character: Model)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not root then
		return
	end
	for _, c in root:GetChildren() do
		mute(c)
	end
	root.ChildAdded:Connect(mute)
end

function CharacterSounds.start()
	local function hook(player: Player)
		player.CharacterAdded:Connect(watch)
		if player.Character then
			task.spawn(watch, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return CharacterSounds
