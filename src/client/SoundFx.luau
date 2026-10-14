--!strict
-- Plays the game's effect sounds from their Config entries (Config/Vfx.Sounds and the like): `{ id, volume, start?,
-- stop?, fade?, pitch?, loop?, profile }`, where volume / pitch may be per-stage lists (picked by `stage`) and a list
-- of entries plays them all at once (layers). Every sound is positional on its falloff profile (src/client/Audio):
-- on a part or an attachment, or at a point in the world. A ready copy of each sound is made once and cloned per
-- play (a Sound made at the moment it's needed starts ~0.33 s late, KNOWN_TRAPS), all preloaded up front.
-- play(entry, at, stage?) a one shot; loop(entry, at) a loop with a handle (set volume / pitch, stop with a fade).

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Audio = require(script.Parent.Audio)

local SoundFx = {}

export type Entry = { [string]: any }
export type Loop = { set: (volume: number?, pitch: number?) -> (), stop: (fade: number?) -> () }

local templates: { [string]: Sound } = {}
local holder = Instance.new("Folder")
holder.Name = "SoundFxTemplates"

local function pick(v: any, stage: number?): number?
	if type(v) == "table" then
		return v[stage or 1] or v[#v]
	end
	return v
end

-- the ready copy for an entry (keyed by its file and trim)
local function template(e: Entry): Sound
	local key = `{e.id}:{e.start or 0}:{e.stop or 0}:{e.profile}:{e.loop == true}`
	local s = templates[key]
	if not s then
		local made = Instance.new("Sound")
		made.SoundId = "rbxassetid://" .. e.id
		made.Looped = e.loop == true
		Audio.spatial(made, e.profile or "Spell")
		if e.start or e.stop then
			made.PlaybackRegionsEnabled = true
			made.PlaybackRegion = NumberRange.new(e.start or 0, e.stop or 600)
			if made.Looped then
				made.LoopRegion = made.PlaybackRegion
			end
		end
		made.Parent = holder
		templates[key] = made
		s = made
	end
	return s
end

-- where a sound sits: on a part / attachment, or at a point (an attachment of its own, gone with the sound)
local function place(sound: Sound, at: Instance | Vector3, life: number?)
	if typeof(at) == "Vector3" then
		local a = Instance.new("Attachment")
		a.Name = "SoundFx"
		a.WorldPosition = at
		a.Parent = workspace.Terrain
		sound.Parent = a
		Debris:AddItem(a, life or 10)
	else
		sound.Parent = at :: Instance
	end
end

local function one(e: Entry, at: Instance | Vector3, stage: number?)
	local s = template(e):Clone()
	local volume, pitch = pick(e.volume, stage) or 1, pick(e.pitch, stage) or 1
	s.Volume = volume
	s.PlaybackSpeed = pitch
	s.TimePosition = e.start or 0
	local length = if s.TimeLength > 0 then s.TimeLength else 8 -- (not known yet: a generous guess)
	local span = ((e.stop or length) - (e.start or 0)) / pitch
	place(s, at, span + 1)
	s:Play()
	if e.stop and e.fade then
		task.delay(math.max(0, span - e.fade), function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(e.fade, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
			end
		end)
	end
	s.Ended:Once(function()
		s:Destroy()
	end)
	Debris:AddItem(s, math.max(span, 0.5) + 1)
end

-- A one shot (or each layer of a list) at `at`; `stage` picks per-stage volumes and pitches.
function SoundFx.play(entry: Entry | { Entry }?, at: Instance | Vector3, stage: number?)
	if not entry then
		return
	end
	if (entry :: any).id then
		one(entry :: Entry, at, stage)
	else
		for _, e in entry :: { Entry } do
			one(e, at, stage)
		end
	end
end

-- A looping sound at `at` until stopped: set(volume, pitch) changes it (volume as a share of the entry's), stop(fade)
-- fades it out and ends it.
function SoundFx.loop(entry: Entry, at: Instance | Vector3): Loop
	local s = template(entry):Clone()
	local base = pick(entry.volume, 1) or 1
	s.Volume = if entry.fadeIn then 0 else base
	s.PlaybackSpeed = pick(entry.pitch, 1) or 1
	s.TimePosition = entry.start or 0
	place(s, at, 3600)
	s:Play()
	if entry.fadeIn then
		TweenService:Create(s, TweenInfo.new(entry.fadeIn), { Volume = base }):Play()
	end
	local stopped = false
	return {
		set = function(volume: number?, pitch: number?)
			if stopped then
				return
			end
			if volume then
				s.Volume = base * volume
			end
			if pitch then
				s.PlaybackSpeed = pitch
			end
		end,
		stop = function(fade: number?)
			if stopped then
				return
			end
			stopped = true
			local f = fade or entry.fadeOut or 0
			if f > 0 then
				TweenService:Create(s, TweenInfo.new(f), { Volume = 0 }):Play()
				Debris:AddItem(s, f + 0.1)
			else
				s:Destroy()
			end
		end,
	}
end

-- Loads every sound in these Config tables now, so the first play starts on time.
function SoundFx.preload(...: { [string]: any })
	local list = {}
	local function walk(t: any)
		if type(t) ~= "table" then
			return
		end
		if t.id then
			table.insert(list, template(t))
		else
			for _, v in t do
				walk(v)
			end
		end
	end
	for _, t in { ... } do
		walk(t)
	end
	holder.Parent = game:GetService("SoundService")
	task.spawn(function()
		ContentProvider:PreloadAsync(list)
	end)
end

return SoundFx
