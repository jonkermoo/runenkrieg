--!strict
-- Footstep sounds (src/client/Footsteps, Rules/Footsteps; user 2026-11-01: "add footsteps to the game"): every
-- soldier's walk / sprint / crouch tracks carry "Footstep" markers on the foot plants; on each client, for every
-- character near enough (its own, other players', bots), a marker plays one step for the ground under it. Quiet
-- background (user 2026-11-01: "it shouldnt be way too loud, it should just be background noise"); sprinting is the
-- loudest and carries furthest, so you hear someone running at you; crouching is hushed. No network.
-- Data only (Lune tests read it).

local Footsteps = {
	-- One sound holds every step (assets/audio/footsteps/make_sheet_leather.py; CC0: HaelDB; ASSETS_LICENSES.md), each
	-- in its own `Slot` seconds, the recordings one group after another in `Order` with `Count` steps each. A step plays
	-- its slot's first `Length` seconds (Sound.PlaybackRegion). Every surface plays the soft leather steps (user
	-- 2026-11-02: "i hate the footstep noise. lets find something more subtle", then picked soft leather, whole, quieter,
	-- ~10% higher; the pitch is in the sheet); `Recordings` says which group a surface plays.
	Sheet = 109260086411382,
	Slot = 0.5,
	Length = 0.3,
	Order = { "leather" },
	Count = { leather = 4 },
	Recordings = {
		grass = "leather",
		leaves = "leather",
		mud = "leather",
		gravel = "leather",
		wood = "leather",
		stone = "leather",
	},

	Volume = 0.042, -- a walking step, heard from right beside it (the sheet peaks at 0.9: ~a quarter of the first set's)
	Own = 0.7, -- this player's own steps (heard from the camera, right over them) a little under everyone else's
	-- by gait (the track the marker came from)
	Gait = { walk = 1, sprint = 1.8, crouch = 0.35 },
	-- by surface: one recording for all of them for now
	Surface = { grass = 1, leaves = 1, mud = 1, gravel = 1, wood = 1, stone = 1 },
	Pitch = 1,
	PitchJitter = 0.04, -- each step varies by up to this much either way
	-- studs from the camera past which a step isn't played at all (the falloff, Config/Audio.Profiles.Footstep, has it
	-- nearly silent there anyway); sprinting carries furthest
	Range = { walk = 40, sprint = 80, crouch = 20 },

	-- the ground under a step: terrain by material (anything not listed is TerrainDefault) ...
	Terrain = {
		Grass = "grass",
		LeafyGrass = "leaves",
		Ground = "mud",
		Mud = "mud",
		Water = "mud", -- (wading: src/client/Wading)
		Sand = "gravel",
		Salt = "gravel",
		Snow = "grass",
		Rock = "stone",
		Slate = "stone",
		Basalt = "stone",
		Cobblestone = "stone",
		Pavement = "stone",
		Concrete = "stone",
		Asphalt = "stone",
		Brick = "stone",
		Limestone = "stone",
		Sandstone = "stone",
		Glacier = "stone",
		Ice = "stone",
		WoodPlanks = "wood",
	},
	TerrainDefault = "mud",
	-- ... a part by its building section's "Class" attribute (src/dev/Buildings; Config/Destruction.Materials) ...
	Class = {
		Wood = "wood",
		Door = "wood",
		Thatch = "leaves",
		Stone = "stone",
		Brick = "stone",
		Plaster = "stone",
		Tile = "stone",
	},
	-- ... else by the first of these found in its name (trench pieces: Wall5Planks, Floor2Chunks, ...), else PartDefault
	Names = {
		{ "Plank", "wood" },
		{ "Board", "wood" },
		{ "Crate", "wood" },
		{ "Sleeper", "wood" },
		{ "Stair", "wood" },
		{ "Step", "wood" },
		{ "Sandbag", "mud" },
		{ "Sack", "mud" },
		{ "Floor", "mud" }, -- a trench's floor (a building's floor has Class Wood)
		{ "Wall", "mud" },
		{ "Parapet", "mud" },
		{ "Apron", "mud" },
		{ "Patch", "mud" },
	},
	PartDefault = "stone",

	GroundProbe = 3.6, -- studs down from the root that count as standing (the root is 3 above the feet)
	MinInterval = 0.15, -- seconds between two steps of one character (crossfades fire both cycles' markers)
}

return table.freeze(Footsteps)
