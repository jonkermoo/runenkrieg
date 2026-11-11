--!strict
-- The looks a map can wear (user 2026-11-11: "remove this highly saturated look... make this look more dark and
-- foggy"; "give me an option of looks"): each a clear-sky haze, a colour grade every player sees whatever their
-- Effects level, the sun's strength and the least cloud. A map names its own (`mood` in Config/Maps); the admin
-- panel's Look row tries the others live (src/client/DevAdminMenu: the client's own Workspace attribute
-- `Attribute`). src/client/Environment draws it; the day, the night, fog and rain still come and go over it.
--   haze: Atmosphere density / haze / color / decay at noon in clear weather
--   saturation / contrast / brightness: ColorCorrection, -1..1 (0 = unchanged); tint: RGB (white = none)
--   light: x the sun's brightness; cloudCover: the sky at least this overcast; cloudColor: the clouds' colour
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
			saturation = -0.32,
			contrast = 0.1,
			brightness = -0.03,
			tint = { 232, 236, 240 },
			light = 0.8,
			cloudCover = 0.72,
			cloudColor = { 196, 200, 206 },
		},
		-- a morning mist: thick pale fog that swallows the far points, soft light
		Mist = {
			haze = { density = 0.68, haze = 3.2, color = { 214, 220, 224 }, decay = { 160, 168, 174 } },
			saturation = -0.38,
			contrast = 0.04,
			brightness = 0.02,
			tint = { 236, 242, 246 },
			light = 0.72,
			cloudCover = 0.85,
			cloudColor = { 214, 218, 222 },
		},
		-- war-torn: drained, dark and heavy, a sooty brown-grey haze, a low leaden sky
		Grim = {
			haze = { density = 0.6, haze = 2.8, color = { 150, 146, 138 }, decay = { 96, 90, 82 } },
			saturation = -0.52,
			contrast = 0.18,
			brightness = -0.07,
			tint = { 236, 230, 216 },
			light = 0.62,
			cloudCover = 0.92,
			cloudColor = { 150, 152, 156 },
		},
		-- late and gloomy: a low warm light through a dusty haze, colour muted
		Dusk = {
			haze = { density = 0.54, haze = 2.2, color = { 214, 184, 156 }, decay = { 140, 104, 88 } },
			saturation = -0.22,
			contrast = 0.12,
			brightness = -0.05,
			tint = { 255, 226, 198 },
			light = 0.7,
			cloudCover = 0.6,
			cloudColor = { 220, 190, 170 },
		},
	},
}

return table.freeze(Moods)
