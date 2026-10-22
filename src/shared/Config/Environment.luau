--!strict
-- Time of day and weather (user 2026-10-22: "add cycling time and random environment events (fog and rain)").
-- The server owns the clock and the weather (src/server/Environment: Workspace attributes below); every client works
-- out the same light, haze and rain from them and the server time (Rules/Environment, src/client/Environment), so
-- nothing is sent per frame. Times in seconds, clock in hours (0-24), colors 0-255. Data only.

local Environment = {
	-- Workspace attributes written by the server
	Attributes = {
		dayStart = "EnvDayStart", -- server time at which the clock read `Day.startClock`
		weather = "EnvWeather", -- "Clear" / "Fog" / "Rain"
		from = "EnvWeatherFrom", -- server time the event starts fading in
		to = "EnvWeatherTo", -- server time it has faded out
	},

	-- One full day in 20 min (user 2026-10-22): 14 min from sunrise to sunset, 6 min of night.
	Day = {
		length = 1200,
		dayShare = 0.7, -- of the real time, spent between sunrise and sunset
		sunrise = 6,
		sunset = 18,
		startClock = 9, -- the clock when a server starts
		twilight = 1, -- hours either side of sunrise / sunset over which the light eases between day and night
	},

	-- Lighting at full day and at night. Night is moonlit: about 35% of the day's light (user 2026-10-22), bluer.
	Light = {
		day = {
			brightness = 2,
			ambient = { 70, 70, 74 },
			outdoorAmbient = { 128, 128, 132 },
			exposure = 0,
		},
		night = {
			brightness = 1.2, -- the moon is far weaker than the sun at the same Brightness
			ambient = { 26, 30, 44 },
			outdoorAmbient = { 46, 52, 76 },
			exposure = -0.35,
		},
		-- the map's haze (Greybox/Features.atmosphere: Config/Palette.Atmosphere) darkens to these at night
		nightHaze = { color = { 48, 56, 78 }, decay = { 30, 36, 54 } },
	},

	-- Rare weather (user 2026-10-22): a roll every 8-15 min of clear sky; each event lasts 3-6 min, fading in and out.
	Weather = {
		clear = { min = 480, max = 900 },
		odds = { Fog = 0.25, Rain = 0.15 }, -- the rest stays clear
		duration = { min = 180, max = 360 }, -- including both fades
		fade = 45,

		-- what each event does at full strength; the map's own Atmosphere is the clear sky
		Fog = {
			density = 0.6,
			haze = 2.6,
			color = { 200, 204, 206 },
			decay = { 150, 156, 160 },
			brightness = 0.8, -- x the sun
			clouds = 0.8,
		},
		Rain = {
			density = 0.48,
			haze = 1.8,
			color = { 150, 158, 166 },
			decay = { 104, 112, 122 },
			brightness = 0.6,
			clouds = 0.95,
			wet = 0.78, -- terrain colors x this (darker, wet ground)
		},
		clouds = { cover = 0.45, density = 0.6, color = { 230, 232, 236 }, rainColor = { 120, 124, 130 } },
	},

	-- The rain near the camera (src/client/Environment): one pooled emitter that follows the camera
	Rain = {
		area = 90, -- studs, the square the drops fall in
		height = 45, -- studs above the camera they start
		lead = 0.6, -- s: the area moves ahead of the camera by its velocity x this
		rate = 1400, -- drops per second at full rain
		speed = 110, -- studs/s, falling
		wind = 0.4, -- x workspace.GlobalWind, the slant
		texture = "rbxasset://textures/particles/sparkles_main.dds", -- Roblox's own; squashed into a thin streak
		size = 0.06,
		length = 2.2, -- the drop's stretch (ParticleEmitter.Squash)
		transparency = 0.45,
		color = { 196, 206, 216 },
		lifetime = 0.7,
		-- under a roof (a part straight above the camera within `roof` studs) the drops stop and the sound dulls
		roof = 60,
		-- the rain loop, Roblox-licensed (Pro Sound Effects "Rain Heavy Rainfall Grass Wooden Roof 1", 46 s loop)
		sound = { id = 9112853422, volume = 0.7, covered = 0.45, coveredHigh = -18 },
	},

	UpdateHz = 30, -- light and haze updates per second
}

return table.freeze(Environment)
