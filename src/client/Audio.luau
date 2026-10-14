--!strict
-- Puts a positional Sound on its realistic distance falloff (Config/Audio): 1 / distance from the profile's reference
-- distance (InverseTapered), silent at its maximum range. Every 3D sound the game makes goes through here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg = require(ReplicatedStorage:WaitForChild("Shared").Config.Audio)

local Audio = {}

function Audio.spatial(sound: Sound, profile: string)
	local p = (Cfg.Profiles :: any)[profile]
	assert(p, `unknown audio profile {profile}`)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = p.ref
	sound.RollOffMaxDistance = p.max
end

return Audio
