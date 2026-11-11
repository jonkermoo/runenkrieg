--!strict
-- The looks a map can wear (user 2026-11-11: "remove this highly saturated look... make this look more dark and
-- foggy"; "give me an option of looks"): each a clear-sky haze, a colour grade every player sees whatever their
-- Effects level, the sun's strength and the least cloud. A map names its own (`mood` in Config/Maps); the admin
-- panel's Look row tries the others live (src/client/DevAdminMenu: the client's own Workspace attribute
-- `Attribute`). src/client/Environment draws it; the day, the night, fog and rain still come and go over it.
--   haze: Atmosphere density / haze / color / decay at noon in clear weather
--   saturation / contrast / brightness: ColorCorrection, -1..1 (0 = unchanged); tint: RGB (white = none)
--   light: x the sun's brightness; cloudCover: the sky at least this overcast; cloudColor: the clouds' colour
--   fog: distance fog from `start` to `finish` studs in the haze's colour (src/client/Environment): the far points fade
-- Daytime stays daytime (user 2026-11-11: "i still want the day time to still look like day time"): the sun kept
-- near full, the fog pale; the mood is the colour, the cloud and the distance, not darkness.
-- Data only.

local Moods = {
	Attribute = "DevMood", -- (a dev's own pick, client only: it never leaves their screen)
	Order = { "Bright", "Overcast", "Mist", "Grim", "Dusk" },

	Presets = {
		-- the look before (2026-11-10): the place's own haze, full colour, a fair-weather sky
		Bright = {
			haze = { density = 0.38, haze = 0.8, color = { 206, 218, 226 }, decay = { 126, 146, 160 } },
			saturation = 0,
			contrast = 0,
			brightness = 0,
			tint = { 255, 255, 255 },
			light = 1,
			cloudCover = 0,
			cloudColor = { 230, 232, 236 },
		},
		-- muted and grey-skied: colour pulled back, a cool grey haze, the sun behind cloud
		Overcast = {
			haze = { density = 0.56, haze = 2.4, color = { 182, 188, 192 }, decay = { 112, 118, 124 } },
			saturation = -0.3,
			contrast = 0.08,
			brightness = 0,
			tint = { 236, 240, 244 },
			light = 0.92,
			cloudCover = 0.62,
			cloudColor = { 214, 218, 222 },
			fog = { start = 160, finish = 1100 },
		},
		-- a morning mist: thick pale fog that swallows the far points, soft light
		Mist = {
			haze = { density = 0.68, haze = 3.2, color = { 220, 226, 230 }, decay = { 160, 168, 174 } },
			saturation = -0.36,
			contrast = 0.02,
			brightness = 0.03,
			tint = { 238, 244, 248 },
			light = 0.88,
			cloudCover = 0.8,
			cloudColor = { 224, 228, 232 },
			fog = { start = 60, finish = 600 },
		},
		-- war-torn: drained, dark and heavy, a sooty brown-grey haze, a low leaden sky
		Grim = {
			haze = { density = 0.6, haze = 2.8, color = { 176, 172, 164 }, decay = { 110, 104, 96 } },
			saturation = -0.5,
			contrast = 0.16,
			brightness = -0.03,
			tint = { 238, 232, 220 },
			light = 0.8,
			cloudCover = 0.88,
			cloudColor = { 168, 170, 174 },
			fog = { start = 100, finish = 800 },
		},
		-- late and gloomy: a low warm light through a dusty haze, colour muted
		Dusk = {
			haze = { density = 0.54, haze = 2.2, color = { 222, 196, 170 }, decay = { 140, 104, 88 } },
			saturation = -0.22,
			contrast = 0.1,
			brightness = -0.02,
			tint = { 255, 232, 208 },
			light = 0.82,
			cloudCover = 0.55,
			cloudColor = { 228, 204, 184 },
			fog = { start = 140, finish = 950 },
		},
	},
}

return table.freeze(Moods)
