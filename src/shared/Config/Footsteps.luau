--!strict
-- Footstep sounds (src/client/Footsteps): one short, soft, low thud on every Footstep marker of the walk / sprint
-- animations, the same on every surface (user 2026-10-11). Played on each client for every character; no network.
-- Data only (Lune tests read it).
--
-- PLACEHOLDER SOUNDS: community uploads from the Creator Store (soft dirt steps, origin unknown). Replace with a
-- licensed set before release.

local Footsteps = {
	Sounds = { 121613327190310, 75948132493425, 111154292786687, 119989047815622, 80708016987437 },

	Volume = 0.2, -- subtle
	SprintVolume = 0.28, -- sprint steps land a little harder
	Pitch = 0.8, -- deeper than the recordings
	PitchJitter = 0.04, -- each step varies by up to this much either way
	RollOffMin = 5, -- studs: full volume inside this
	RollOffMax = 50, -- studs: silent past this
	GroundProbe = 3.6, -- studs down from the root that count as standing (the root is 3 above the feet)
	MinInterval = 0.15, -- seconds between two steps of one character (crossfades fire both cycles' markers)
}

return table.freeze(Footsteps)
