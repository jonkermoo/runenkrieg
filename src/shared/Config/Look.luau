--!strict
-- The screen look per graphics level (src/client/Look, Rules/Grade; the "Effects" option in Config/Settings): Roblox's
-- built-in post effects, no shaders. They only grade colour and light, so the flat-colour, faceted art stays as it is
-- (docs/ART_STYLE.md). Client only: each player sees their own level.
-- Per level:
--   grade: a ColorCorrection for the day and one for the night, blended by the sun's height (Rules/Grade.mix):
--     saturation / contrast / brightness (-1..1, 0 = unchanged) and tint (RGB, white = none).
--   bloom: intensity, size, threshold. The threshold stays 2 at every level: only HDR-bright magic and flashes glow
--     (Config/Vfx), never the flat colours.
--   sunRays: intensity by day (fades to 0 at night), spread. nil = no rays.
--   diffuse / specular: Lighting.EnvironmentDiffuseScale / EnvironmentSpecularScale (sky light on the shaded side of
--     each facet / sky reflections; nearly free).
--   quality: Lighting.PrioritizeLightingQuality (softer, better shadows; costs GPU).
-- Off keeps the place's own Lighting (its Bloom keeps the magic glowing) and adds nothing.
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
			quality = false,
		},
		-- Kept close to neutral: the Beautiful setting's own cinematic layer (src/client/Cinematic) adds its film look.
		Beautiful = {
			grade = {
				day = { saturation = 0.1, contrast = 0.08, brightness = 0, tint = { 255, 248, 238 } },
				night = { saturation = -0.08, contrast = 0.06, brightness = 0, tint = { 228, 236, 255 } },
			},
			bloom = { intensity = 1, size = 32, threshold = 2 },
			sunRays = { intensity = 0.06, spread = 0.6 },
			diffuse = 1,
			specular = 0.15,
			quality = true,
		},
	},
}

return table.freeze(Look)
