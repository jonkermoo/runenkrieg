--!strict
-- Camera while a weapon is in the hands (src/client/WeaponCamera; user 2026-10-11). Data only.
-- Equipping a weapon locks the camera over the right shoulder (Metrics.Camera: offset and distance); the mouse
-- wheel steps between first person, the shoulder camera and a free third-person orbit. Aiming down the sights
-- (hold right mouse) is always first person. In first person the camera is the eye and the player sees their
-- first-person holds on a viewmodel (src/client/Viewmodel), not the body. Without a weapon Roblox's own camera runs.

local Camera = {
	Modes = { "First", "Shoulder", "Free" }, -- wheel forward steps left, back steps right
	DefaultMode = "Shoulder", -- on every equip

	Sensitivity = 0.4, -- degrees of turn per pixel of mouse movement
	AimSensitivity = 0.6, -- share of that while aiming down the sights
	PitchLimit = 80, -- degrees up and down

	Fov = 70,
	AimFov = 50,
	Ease = 14, -- how fast the camera moves between modes, the FOV and the first-person hold (per second)

	-- First person: the eye in the Head's space (the R6 head is 1.25 big; front face at -0.6). The viewmodel's torso
	-- sits where the eye is (0, 1.65, -0.45) from it, as in tools/animation/rifle.luau EYE.
	Eye = { 0, 0.15, -0.45 },
	-- Free orbit: distance from the head (studs), wheel steps, nearest before it hands back to the shoulder camera.
	FreeDistance = 10,
	FreeMin = 7,
	FreeMax = 20,
	FreeStep = 2,

	CollisionMargin = 0.4, -- the camera stops this far in front of a wall between it and the head

	-- Third person, local only: the weapon follows the camera's pitch. The torso tilts a little
	-- (Config/Locomotion.LookTilt) and the arms with the gun turn about the shoulder line for the rest: share of the
	-- pitch the gun follows per hold, and the head's share.
	Follow = { ready = 1, carry = 0.3, aim = 1 },
	HeadFollow = 0.6,
}

return table.freeze(Camera)
