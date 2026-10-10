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
		DoorWidth = 5.0,
		DoorHeight = 7.5,
		WindowSill = 3.5,
		WindowTop = 6.5,
		StoryHeight = 12.0, -- floor to floor
		StairRise = 0.8,
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
