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
local ducked = 1 -- (src/client/Concussion: a share of the volume for a moment)
local reapply = function() end

-- The group every game sound plays in (made on first use; local to this client).
function Audio.effects(): SoundGroup
	if not effects then
		local g = Instance.new("SoundGroup")
		g.Name = "Effects"
		local function apply()
			-- (a SoundGroup's own default is 0.5: 1 here keeps every sound at the level it was tuned at)
			g.Volume = SettingsRules.volume(Settings.get("MasterVolume"), Settings.get("EffectsVolume")) * ducked
		end
		apply()
		Settings.changed("MasterVolume", apply)
		Settings.changed("EffectsVolume", apply)
		reapply = apply
		g.Parent = SoundService
		effects = g
	end
	return effects :: SoundGroup
end

-- Every game sound at `share` of its volume (1: back to normal), on top of the player's settings.
function Audio.duck(share: number)
	if share ~= ducked then
		ducked = share
		Audio.effects()
		reapply()
	end
end

-- Every game sound muffled: `high`, `mid`, `low` dB on the group's equalizer bands (all 0: clear), set by `source`
-- (src/client/Concussion's own when none; src/client/SuppressionScreen "Suppression"). With more than one source on,
-- each band takes the strongest (the farthest from 0).
local muffler: EqualizerSoundEffect? = nil
local muffles: { [string]: { number } } = {}
function Audio.muffle(high: number, mid: number, low: number, source: string?)
	local key = source or "Concussion"
	if high == 0 and mid == 0 and low == 0 then
		if not muffles[key] then
			return
		end
		muffles[key] = nil
	else
		muffles[key] = { high, mid, low }
	end
	local h, m, l = 0, 0, 0
	for _, b in muffles do
		h = if math.abs(b[1]) > math.abs(h) then b[1] else h
		m = if math.abs(b[2]) > math.abs(m) then b[2] else m
		l = if math.abs(b[3]) > math.abs(l) then b[3] else l
	end
	if not muffler then
		if h == 0 and m == 0 and l == 0 then
			return
		end
		local e = Instance.new("EqualizerSoundEffect")
		e.Name = "Muffle"
		e.HighGain, e.MidGain, e.LowGain = 0, 0, 0
		e.Parent = Audio.effects()
		muffler = e
	end
	local e = muffler :: EqualizerSoundEffect
	e.HighGain, e.MidGain, e.LowGain = h, m, l
	e.Enabled = h ~= 0 or m ~= 0 or l ~= 0
end

-- The player's Master x Effects volume, not ducked (for a sound outside the group).
function Audio.volume(): number
	return SettingsRules.volume(Settings.get("MasterVolume"), Settings.get("EffectsVolume"))
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
