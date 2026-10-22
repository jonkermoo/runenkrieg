--!strict
-- The cinematic layer of the "Beautiful" graphics level (src/client/Cinematic, Rules/Cinematic): depth of field that
-- focuses on what the player looks at, and a soft vignette. Client only, on top of the per-level look (Config/Look,
-- whose Beautiful grade and sun rays are the "Golden" look the user picked, 2026-10-22); it adds its own "Cinematic_*"
-- instances and never edits anyone else's. Colours are RGB 0-255. Data only.

local Cinematic = {
	-- Depth of field: the focus follows what the screen centre looks at (a ray up to `maxDistance` studs; the sky or
	-- nothing focuses at `maxDistance`), easing toward it at `focusRate` per second. The in-focus radius is the focus
	-- distance x `radius`, at least `minRadius` studs, so whatever is aimed at stays sharp and only the far background
	-- softens. No near blur: the weapon in the hands stays sharp. Roblox caps the focus distance at 200 studs and the
	-- radius at 50.
	Dof = { far = 0.25, radius = 0.6, minRadius = 40 },
	Focus = { maxDistance = 200, maxRadius = 50, focusRate = 6, updateHz = 30 },
	-- aiming down the sights keeps this share of the far blur (a sharper view to shoot through)
	AimFarShare = 0.4,

	-- The vignette: a ScreenGui of four edge gradients, dark at the edge (`transparency`) and clear `size` of the
	-- screen height inward, under every other UI.
	Vignette = { size = 0.22, transparency = 0.55, color = { 18, 12, 6 } },
	VignetteOrder = -10,
}

return table.freeze(Cinematic)
