--!strict
-- Gameplay metrics: the shared contract between code, maps and characters.
-- Rationale and sources for every value: docs/METRICS.md. Units are studs, seconds, degrees.
-- Data only (no Instances) so Lune tests and the map checker can read it.

local Metrics = {
	-- Scale: a 5.19-stud soldier reads as ~1.8 m, so 1 stud ~= 0.35 m for real-world conversions.
	MetersPerStud = 0.35,

	Character = {
		-- Measured: default blocky R6 (2026-10-10). Legs 2, torso 2, head 1 (mesh scale 1.25).
		-- User decision 2026-10-10: R6 for everyone (matches the Pordier references), uniform body.
		Height = 5.13, -- feet to top of the head mesh
		Width = 4.0, -- arms included
		ShoulderWidth = 2.0,
		Depth = 1.0,
		HeadCenterHeight = 4.5,
		ShoulderHeight = 4.0,
		EyeHeight = 4.5, -- FaceCenterAttachment
		AimMuzzleHeight = 4.3, -- estimate: shouldered rifle, sights at eye
		LegLength = 2.0,
		MaxStepUp = 1.0, -- estimate: tallest ledge an R6 humanoid walks up without jumping
	},

	Movement = {
		WalkSpeed = 10, -- user 2026-10-11 (was 12)
		SprintSpeed = 16, -- user 2026-10-11 (was 18)
		AimWalkSpeed = 7,
		CrouchSpeed = 6, -- C toggles crouch (user 2026-10-11, moderate crouch from the reference video)
		-- Low hop only, no vault yet. JumpHeight is the take-off (Humanoid); near the top the client cuts gravity
		-- (src/client/Jump) so the peak hangs, which adds ~0.25: the real apex is ~2.95 (user 2026-10-11: higher
		-- than 2.5 twice, slower peak). tests/metrics.spec.luau keeps it under low cover (3.0).
		JumpHeight = 2.7,
		JumpApexSpeed = 8, -- the float applies while |vertical speed| is under this (studs/s)
		JumpApexGravityCut = 0.6, -- share of gravity removed during the float
		JumpCooldown = 0.4, -- seconds after landing before the next jump
		MaxSlopeAngle = 50, -- Studio default is 89, which lets players walk up trench walls
		Gravity = 196.2,
	},

	Cover = {
		HopableLedgeMax = 2.0, -- anything at or below this can be hopped onto
		LowCoverMin = 3.0, -- blocks movement; the crouched (idle) head top is ~3.7 (open: raise this to cover a crouch?)
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
