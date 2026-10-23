--!strict
-- The screen look per graphics level (src/client/Look, Rules/Grade; the "Effects" option in Config/Settings): Roblox's
-- built-in post effects, no shaders. They only grade colour and light, so the flat-colour, faceted art stays as it is
-- (docs/ART_STYLE.md). Client only: each player sees their own level.
-- Per level:
--   grade: a ColorCorrection for the day and one for the night, blended by the sun's height (Rules/Grade.mix):
--     saturation / contrast / brightness (-1..1, 0 = unchanged) and tint (RGB, white = none).
--   bloom: intensity, size, threshold. The threshold stays 2 at every level: only HDR-bright magic and flashes glow
--     (Config/Vfx), never the flat colours.
--   sunRays: intensity by day (fades to 0 at night), spread; they replace the place's own SunRays. nil = the place's
--     rays stay as they are.
--   diffuse / specular: Lighting.EnvironmentDiffuseScale / EnvironmentSpecularScale (sky light on the shaded side of
--     each facet / sky reflections; nearly free).
-- Off keeps the place's own Lighting (its Bloom keeps the magic glowing) and adds nothing.
-- (Lighting.PrioritizeLightingQuality and LightingStyle can't be set by a game script, only on the place in Studio.)
-- Data only.

local Look = {
	-- The sun's height (Lighting:GetSunDirection().Y) at which the grade is all night / all day; blended between.
	NightAt = -0.05,
	DayAt = 0.25,

	Levels = {
		Normal = {
			grade = {
				day = { saturation = 0.08, contrast = 0.06, brightness = 0, tint = { 255, 250, 242 } },
				night = { saturation = -0.05, contrast = 0.04, brightness = 0, tint = { 236, 241, 255 } },
			},
			bloom = { intensity = 0.6, size = 24, threshold = 2 },
			sunRays = nil,
			diffuse = 0.5,
			specular = 0,
		},
		-- The "Golden" cinematic grade (user 2026-10-22): warm late-afternoon light and gently richer colour by day,
		-- cool moonlight at night. No blur or vignette (user 2026-10-23: Beautiful is shaders and effects only).
		Beautiful = {
			grade = {
				day = { saturation = 0.12, contrast = 0.14, brightness = 0.02, tint = { 255, 232, 204 } },
				night = { saturation = -0.12, contrast = 0.1, brightness = 0, tint = { 218, 226, 255 } },
			},
			bloom = { intensity = 1, size = 32, threshold = 2 },
			sunRays = { intensity = 0.07, spread = 0.75 },
			diffuse = 1,
			specular = 0.15,
		},
	},
}

return table.freeze(Look)
