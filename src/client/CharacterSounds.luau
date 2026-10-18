--!strict
-- Sets the volume of Roblox's built-in character sounds listed in Config/Locomotion.SoundVolumes (0 mutes) on every
-- character. RbxCharacterSounds creates them on each client inside the HumanoidRootPart and keeps playing them, so
-- they are held at that volume rather than destroyed. They play in the Effects group (src/client/Audio).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Locomotion)
local Audio = require(script.Parent.Audio)

local CharacterSounds = {}

local function set(inst: Instance)
	local volume = Cfg.SoundVolumes[inst.Name]
	if inst:IsA("Sound") and volume then
		inst.SoundGroup = Audio.effects() -- the player's volume settings
		inst.Volume = volume
		inst:GetPropertyChangedSignal("Volume"):Connect(function()
			if inst.Volume ~= volume then
				inst.Volume = volume
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
		set(c)
	end
	root.ChildAdded:Connect(set)
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
