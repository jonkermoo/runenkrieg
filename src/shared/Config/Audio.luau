--!strict
-- How every positional sound falls off with distance (user 2026-10-12: "realistic distance to volume at all times";
-- src/client/Audio applies it). Sound pressure falls as 1 / distance: -6 dB each time the distance doubles, from a
-- reference distance where the recording plays at its full level (inside it the sound stays full: for a rifle shot
-- that is the ears' own limit). Roblox's InverseTapered rolloff is exactly that law, easing to silence at the
-- maximum range instead of cutting off. 1 stud ~ 0.357 m (Metrics). Every 3D sound in the game picks a profile here.
-- Data only.

local Audio = {
	Profiles = {
		-- a rifle shot: full inside ~7 m, 1/d beyond; carries far past the fog (600) as a faint report
		Gunshot = { ref = 20, max = 2400 },
		-- the action worked by hand (bolt, clip, an empty click): full within ~0.7 m, heard to ~20 m
		Mechanism = { ref = 2, max = 60 },
		-- footsteps (src/client/Footsteps): full within ~1 m, heard to ~20 m
		Footstep = { ref = 3, max = 60 },
		-- magic (Config/Vfx.Sounds): a cast and its shot, full within ~2 m, heard to ~140 m
		Spell = { ref = 6, max = 400 },
		-- the full-charge blast and where a beam lands: full within ~5 m, carrying like a gunshot
		SpellBig = { ref = 14, max = 1800 },
		-- hums and handling (the charge, the laser, floating, drawing the staff): close by only
		Hum = { ref = 3, max = 60 },
	},
}

return table.freeze(Audio)
