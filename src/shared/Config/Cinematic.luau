--!strict
-- The cinematic layer of the "Beautiful" graphics level (src/client/Cinematic, Rules/Cinematic): a film grade, depth
-- of field that focuses on what the player looks at, sun rays and a soft vignette. Client only, on top of the
-- per-level effects (src/client/Look); it adds its own "Cinematic_*" instances and never edits anyone else's.
-- The grade blends from `day` to `night` as the sun goes down (Rules/Cinematic.daylight), so the look holds at night.
-- Colours are RGB 0-255. Data only.

local Cinematic = {
	-- The look in use, and the candidates shown to the user (2026-10-22).
	Look = "Golden",
	Looks = {
		-- warm late-afternoon light, gently richer colour, soft background
		Golden = {
			day = { tint = { 255, 240, 220 }, brightness = 0.02, contrast = 0.12, saturation = 0.08 },
			night = { tint = { 214, 224, 255 }, brightness = 0, contrast = 0.1, saturation = -0.15 },
			dof = { far = 0.25, radius = 0.6, minRadius = 40 },
			sunRays = { intensity = 0.06, spread = 0.75 },
			vignette = { size = 0.22, transparency = 0.55, color = { 18, 12, 6 } },
		},
		-- a faded war photograph: muted, warm, harder contrast, heavier vignette
		Archive = {
			day = { tint = { 255, 236, 205 }, brightness = 0, contrast = 0.2, saturation = -0.35 },
			night = { tint = { 220, 220, 235 }, brightness = 0, contrast = 0.18, saturation = -0.45 },
			dof = { far = 0.3, radius = 0.5, minRadius = 35 },
			sunRays = { intensity = 0.04, spread = 0.6 },
			vignette = { size = 0.28, transparency = 0.4, color = { 20, 14, 8 } },
		},
		-- cold front-line morning: cool, washed-out, high contrast
		Frontline = {
			day = { tint = { 228, 238, 250 }, brightness = -0.02, contrast = 0.22, saturation = -0.25 },
			night = { tint = { 205, 218, 245 }, brightness = 0, contrast = 0.15, saturation = -0.4 },
			dof = { far = 0.2, radius = 0.6, minRadius = 45 },
			sunRays = { intensity = 0.03, spread = 0.5 },
			vignette = { size = 0.24, transparency = 0.5, color = { 6, 10, 16 } },
		},
		-- storybook: bright, saturated, strong background blur (a miniature feel that suits the flat art)
		Storybook = {
			day = { tint = { 255, 246, 232 }, brightness = 0.04, contrast = 0.08, saturation = 0.2 },
			night = { tint = { 210, 222, 255 }, brightness = 0.02, contrast = 0.08, saturation = 0 },
			dof = { far = 0.45, radius = 0.45, minRadius = 30 },
			sunRays = { intensity = 0.1, spread = 0.9 },
			vignette = { size = 0.18, transparency = 0.65, color = { 24, 16, 8 } },
		},
	},

	-- Day / night: the grade is all `day` with the sun this high (the y of Lighting:GetSunDirection()) or higher, all
	-- `night` at `nightBelow` or lower, blended between.
	DayAbove = 0.15,
	NightBelow = -0.05,

	-- Depth of field: the focus follows what the screen centre looks at (a ray up to `maxDistance` studs; the sky or
	-- nothing focuses at `maxDistance`), easing toward it at `focusRate` per second. The in-focus radius is the focus
	-- distance x the look's `radius`, at least its `minRadius` studs, so whatever is aimed at stays sharp and only the
	-- far background softens. No near blur: the weapon in the hands stays sharp. Roblox caps the focus distance at 200
	-- studs and the radius at 50.
	Focus = { maxDistance = 200, maxRadius = 50, focusRate = 6, updateHz = 30 },
	-- aiming down the sights keeps this share of the far blur (a sharper view to shoot through)
	AimFarShare = 0.4,

	-- The vignette: a ScreenGui of four edge gradients under every other UI.
	VignetteOrder = -10,
}

return table.freeze(Cinematic)
