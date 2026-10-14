--!strict
-- The animation showcase (src/server/Showcase; user 2026-10-12: "a showcase of npc's/dummies performing each type of
-- animation (third person pov), updated as we add more animations"). In every play test of the DEV place, dummies in
-- the soldier's uniform stand off the map, one per animation, each playing it on a loop as other players see it:
-- the movement cycles, then a row per weapon with each hold over the cycle it rides on and the weapon's actions
-- (a shot and the bolt worked, a reload) repeating. It is built from Config/Locomotion and Config/Weapons, so a new
-- animation or weapon shows up by itself. Teleport: "Animation showcase" (Config/DevTools). Data only.

local Showcase = {
	PlaceId = 103459731368962, -- only the DEV place builds it
	Origin = { 600, 0, -2640 }, -- world position of the first dummy of the first row (the floor top is y 0)
	Spacing = 6, -- studs between dummies in a row (x)
	RowGap = 16, -- studs between rows (rows go -z, away from the viewer)
	LabelRange = 24, -- a dummy's label shows within this distance (walk along the rows to read them)
	-- the movement row, in this order (any other Config/Locomotion animation is added after them)
	Movement = { "idle", "walk", "sprint", "crouchIdle", "crouchWalk", "climb" },
	Skip = { toolnone = true }, -- Roblox's stock tool hold: not ours
	-- each weapon hold over the movement cycle it plays on in game (src/client/Locomotion); `once` holds replay every
	-- Replay seconds over `over`
	Holds = {
		{ hold = "ready", base = "idle" },
		{ hold = "walk", base = "walk" },
		{ hold = "carry", base = "sprint" },
		{ hold = "aim", base = "idle" },
		{ hold = "crouchReady", base = "crouchIdle" },
		{ hold = "crouchWalk", base = "crouchWalk" },
		{ hold = "crouchAim", base = "crouchIdle" },
		{ hold = "equip", base = "idle", over = "ready", once = true },
		{ hold = "unequip", base = "idle", over = "ready", once = true }, -- put away onto the back (user 2026-10-14)
	},
	Replay = 2.5,
	-- the weapon's actions on a loop (src/client/GunFx shows them on every client): a shot and the bolt worked over
	-- the aim hold, a reload over the ready hold. These dummies stand side-on (right side to the viewer, firing
	-- along +x away from the rows).
	Actions = {
		{ action = "Bolt", over = "aim", every = 3, shotFirst = 0.5 }, -- fire, then work the bolt after shotFirst s
		{ action = "Reload", over = "ready", every = 4.5 },
		-- single rounds (stripper-clip rifles only): `rounds` thumbed in, then the bolt closes
		{ action = "Load", over = "ready", every = 4, rounds = 2 },
	},
	Tracer = 40, -- studs a showcase shot's tracer runs (it hits nothing)
	-- the staff's attack as others see it (user 2026-10-13: "show what the attack looks like in third person on an
	-- NPC ... the animations along with the visuals", no ragdoll): a dummy per entry. `hip`: the quick fire without
	-- aiming, every `rest` seconds. Otherwise it aims (the first circle held `ready` seconds), charges for `held`
	-- seconds (Config/Spells stages: under 0.45 is a click), fires that stage, rests `rest` seconds, again. Side-on
	-- like the actions; the spells (circles, orbits, laser, beam) drawn by src/client/CastShow.
	CastWeapon = "staff_grey", -- the attack is shown with one staff (the others' rows show their holds)
	Casts = {
		{ stage = 1, hip = true, rest = 1.6 },
		{ stage = 1, ready = 0.8, held = 0.15, rest = 1.4 },
		{ stage = 2, ready = 0.6, held = 1.1, rest = 3 },
		{ stage = 3, ready = 0.6, held = 3.0, rest = 4.5 },
		-- floating (user 2026-10-13: "show me the floating air animation in third person too"): hovering `AirLift`
		-- studs up on the float cycle, charging with the lean back (airCharge)
		{ stage = 3, ready = 1.2, held = 3.4, rest = 4.5, air = true },
	},
	AirLift = 3.2, -- a floating caster's height over the floor (about the hover: Config/Spells.Staff.Float)

	Colors = {
		Floor = { 120, 118, 112 },
		Label = { 236, 232, 220 },
	},
}

return table.freeze(Showcase)
