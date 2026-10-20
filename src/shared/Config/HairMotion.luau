--!strict
-- Hair sway (user 2026-10-20: "slight animation like the animal ears and tails", "not laggy"; docs/HAIRS.md). Each
-- hair is skinned to a few bones (tools/hair/rig_hair.py): Root holds the crown and fringe still, Back1..BackN run
-- down the back hair (a ponytail's too), SideL / SideR hold the locks beside the face. Every client moves every near
-- soldier's hair itself (src/client/HairMotion, Rules/HairMotion), through the bones' Transform, so nothing replicates.
-- Degrees, seconds, studs, studs/s. A chain's angles are shared out over its bones, so a long ponytail bends no more
-- in all than a short back. Once dead the hair settles and holds still.

local HairMotion = {
	-- the CollectionService tag src/server/Helmets puts on every worn Hair model with bones
	Tag = "HairSway",
	-- soldiers farther than this from the camera, or off screen, hold still
	Range = 60,
	-- at most this many soldiers' hair moves per frame; the rest wait their turn (each gets its own time step)
	PerFrame = 24,
	-- under a helmet only what hangs below the brim moves (the rig keeps the shaved edge still): this share of it
	HelmetOn = 0.6,
	Back = {
		swayDeg = 3, -- an idle side to side sway (in all, down the chain), travelling down it
		swayHz = 0.35,
		phasePerBone = 0.7, -- radians later per bone
		liftPerSpeed = 0.9, -- moving forward the hair trails back, up to `liftMax`
		liftMax = 14,
		lagPerSpeed = 1.2, -- moving sideways it swings the other way, up to `lagMax`
		lagMax = 12,
		turnLag = 4, -- turning, it swings against the turn (per rad/s), up to `turnMax`
		turnMax = 12,
		bobDeg = 2.5, -- a bounce with the stride while moving (full at `bobSpeed`)
		bobHz = 2.6,
		bobSpeed = 16,
		fallPerSpeed = 0.6, -- falling lifts it (per stud/s down), up to `fallMax`
		fallMax = 10,
	},
	Side = {
		swayDeg = 2,
		swayHz = 0.5,
		liftPerSpeed = 0.5,
		liftMax = 7,
		lagPerSpeed = 0.6,
		lagMax = 6,
		turnLag = 2.5,
		turnMax = 7,
		bobDeg = 1.5,
		fallPerSpeed = 0.4,
		fallMax = 6,
	},
	-- a spring per angle: hair overshoots a little and settles (stiffness per s^2, damping per s)
	Spring = { stiffness = 90, damping = 11 },
	-- each bone turns at most this much (degrees, the spring's overshoot included)
	MaxDeg = 16,
}

return HairMotion
