--!strict
-- Gameplay metrics: the shared contract between code, maps and characters.
-- Rationale and sources for every value: docs/METRICS.md. Units are studs, seconds, degrees.
-- Data only (no Instances) so Lune tests and the map checker can read it.

local Metrics = {
	-- Scale: a 5.19-stud soldier reads as ~1.8 m, so 1 stud ~= 0.35 m for real-world conversions.
	MetersPerStud = 0.35,

	Character = {
		-- Measured: default R15, scales 1/1/1/1, BodyType 0, Proportion 0 (2026-10-09).
		Height = 5.19,
		Width = 4.0, -- arms included
		ShoulderWidth = 2.0,
		Depth = 1.2,
		HeadCenterHeight = 4.59,
		ShoulderHeight = 3.76,
		EyeHeight = 4.49, -- FaceCenterAttachment
		AimMuzzleHeight = 4.3, -- estimate: shouldered rifle, sights at eye
		HipHeight = 2.0,
		-- Uniform soldier body applied to every player on spawn (src/server/Bodies). User decision
		-- 2026-10-10: the standard R15 body for everyone, so hitboxes are fair and buildings fit.
		Scales = { Height = 1, Width = 1, Depth = 1, Head = 1, BodyType = 0, Proportion = 0 },
	},

	Movement = {
		WalkSpeed = 12,
		SprintSpeed = 18,
		AimWalkSpeed = 7,
		JumpHeight = 2.5, -- low hop only; no vault yet
		MaxSlopeAngle = 50, -- Studio default is 89, which lets players walk up trench walls
		Gravity = 196.2,
	},

	Cover = {
		HopableLedgeMax = 2.0, -- anything at or below this can be hopped onto
		LowCoverMin = 3.0, -- blocks movement and covers a crouched body (future crouch)
		FullCoverMin = 5.5, -- hides a standing soldier completely (head top 5.19)
	},

	Trench = {
		Depth = 5.5, -- floor to parapet top
		FloorWidth = 6.0,
		TopWidth = 8.0,
		FirestepHeight = 2.0, -- hoppable; on it the aimed muzzle clears the parapet
		FirestepWidth = 2.5,
		MaxExitSpacing = 30, -- a ladder/ramp/steps out at least this often
	},

	Building = {
		-- Openings are proportional to the soldier body (tests/metrics.spec.luau enforces the ratios):
		DoorWidth = 4.6, -- 1.15 x body width (4.0)
		DoorHeight = 6.8, -- 1.3 x body height (5.19)
		WindowWidth = 3.4, -- ~0.65 x body height
		WindowSill = 3.1, -- 0.6 x height: below the aimed muzzle, so you can shoot out standing
		WindowTop = 6.2, -- 1.2 x height: above eye level
		StoryHeight = 12.0, -- floor to floor
		StairRise = 0.8, -- max; actual = StoryHeight / ceil(StoryHeight / StairRise)
		StairRun = 1.2,
		StairWidthMin = 5.0,
	},

	Combat = {
		FogEnd = 600, -- full whiteout distance; per-map override allowed
		RifleEffectiveRange = 450,
		RespawnDelay = 10,
	},

	Sector = {
		Spacing = 300, -- center to center along the front
		CaptureRadius = 45,
	},

	Camera = {
		ShoulderOffset = { X = 1.75, Y = 1.0, Z = 0 }, -- right/up from head center
		Distance = 7.0,
		AimDistance = 0, -- first person when aiming down sights
	},
}

return table.freeze(Metrics)
