--!strict
-- Puts a positional Sound on its realistic distance falloff (Config/Audio): 1 / distance from the profile's reference
-- distance (InverseTapered), silent at its maximum range. Every 3D sound the game makes goes through here, and into
-- the "Effects" sound group, played at the player's Master x Effects volume (src/client/Settings, Rules/Settings).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Audio)
local SettingsRules = require(Shared.Rules.Settings)
local Settings = require(script.Parent.Settings)

local Audio = {}

local effects: SoundGroup? = nil

-- The group every game sound plays in (made on first use; local to this client).
function Audio.effects(): SoundGroup
	if not effects then
		local g = Instance.new("SoundGroup")
		g.Name = "Effects"
		local function apply()
			-- (a SoundGroup's own default is 0.5: 1 here keeps every sound at the level it was tuned at)
			g.Volume = SettingsRules.volume(Settings.get("MasterVolume"), Settings.get("EffectsVolume"))
		end
		apply()
		Settings.changed("MasterVolume", apply)
		Settings.changed("EffectsVolume", apply)
		g.Parent = SoundService
		effects = g
	end
	return effects :: SoundGroup
end

function Audio.spatial(sound: Sound, profile: string)
	sound.SoundGroup = Audio.effects()
	local p = (Cfg.Profiles :: any)[profile]
	assert(p, `unknown audio profile {profile}`)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = p.ref
	sound.RollOffMaxDistance = p.max
end

return Audio
