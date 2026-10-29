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
		-- the same from this player's own gun (src/client/GunFx): heard from the camera, which in third person sits 3.5 to
		-- 9.3 studs off the gun, so it stays full over the near third-person views and only a little quieter (~0.6) scrolled
		-- all the way out (user 2026-10-22: a reload kicked out of first person dropped to ~a fifth and seemed cut off)
		OwnMechanism = { ref = 5.5, max = 60 },
		-- a shovel biting into the ground or tossing its dirt (Config/Shovel.Sounds): full within ~1.4 m, heard to ~40 m
		Dig = { ref = 4, max = 120 },
		-- barbed wire rattled by someone pushing through (Config/Build.Wire.sounds): full within ~1.4 m, heard to ~35 m
		Rattle = { ref = 4, max = 100 },
		-- footsteps (src/client/Footsteps): full within ~1 m, heard to ~20 m
		Footstep = { ref = 3, max = 60 },
		-- a spent case landing (Config/Firing.Cases): a small clink, full within ~0.7 m, heard to ~15 m
		Casing = { ref = 2, max = 45 },
		-- a thrown grenade's thunk where it lands (Config/Grenades.Thunk): full within ~4 m, heard to ~110 m, so one that
		-- lands a full throw off (~80-100 studs) is still heard, quietly (on Footstep it was silent past 60 studs, user
		-- 2026-10-25: "i dont hear it")
		Thunk = { ref = 12, max = 300 },
		-- magic (Config/Vfx.Sounds): a cast and its shot, full within ~2 m, heard to ~140 m
		Spell = { ref = 6, max = 400 },
		-- the full-charge blast and where a beam lands: full within ~5 m, carrying like a gunshot
		SpellBig = { ref = 14, max = 1800 },
		-- hums and handling (the charge, the laser, floating, drawing the staff): close by only
		Hum = { ref = 3, max = 60 },
		-- a grenade going off (Config/Grenades.Sound): full within ~7 m, then 1/d, heard right across the map
		Explosion = { ref = 20, max = 2400 },
		-- a far report (Config/Firing.Sounds.Far): the recording already sounds far off, so it plays fuller for longer
		Report = { ref = 80, max = 2400 },
	},

	-- Someone else's shot as this listener hears it (src/client/ShotAudio, Rules/ShotAudio). Studs and seconds.
	Heard = {
		speed = 960, -- sound travels 343 m/s = 960 studs/s at 0.357 m per stud: a shot 480 studs off arrives 0.5 s late
		-- the shot's own sound alone up to `near`, crossfading (equal power) into the far report by `far`
		near = 60,
		far = 300,
		min = 0.01, -- a part mixed in at less than this share isn't played
		-- air and ground take the highs first: dB per stud beyond `from` on the equalizer's low / mid / high bands, never
		-- below `floor`
		air = { from = 60, low = 0, mid = -0.012, high = -0.04, floor = { 0, -10, -30 } },
		-- a bullet passing close by: heard within `radius` of its path, not within `clear` of the muzzle (the report
		-- covers it there); rifles crack (~700 m/s), a shotgun's pellets whiz (~400 m/s). Volume from 1 on the path to
		-- `edge` at the radius.
		pass = { radius = 15, clear = 40, bullet = 1960, pellet = 1120, edge = 0.3 },
		-- echoes: `rays` level rays from the listener out to `range` find walls and hillsides; the strongest `count`
		-- reflections at least `extra` studs longer than the direct path (0.1 s later: closer ones only thicken the shot, the
		-- 2026-10-16 test) play the far report from the wall at `gain` (what the reflection keeps; the falloff counts the
		-- whole path), a further `dull` dB down on the highs. They grow with the shot's distance like the far report:
		-- silent within `from` studs of the gun, full from `full` (user 2026-10-28: "the shot keeps ringing a distant echo
		-- when we are right next to the gun")
		echo = { rays = 8, range = 500, count = 2, extra = 100, gain = 0.5, dull = -8, from = 60, full = 300 },
	},
}

return table.freeze(Audio)
