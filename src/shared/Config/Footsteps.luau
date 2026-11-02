--!strict
-- Footstep sounds (src/client/Footsteps, Rules/Footsteps; user 2026-11-01: "add footsteps to the game"): every
-- soldier's walk / sprint / crouch tracks carry "Footstep" markers on the foot plants; on each client, for every
-- character near enough (its own, other players', bots), a marker plays one step for the ground under it. Quiet
-- background (user 2026-11-01: "it shouldnt be way too loud, it should just be background noise"); sprinting is the
-- loudest and carries furthest, so you hear someone running at you; crouching is hushed. No network.
-- Data only (Lune tests read it).

local Footsteps = {
	-- One sound holds every step (assets/audio/footsteps/make_sheet.py; CC0: Fantozzi, TinyWorlds; ASSETS_LICENSES.md),
	-- each in its own `Slot` seconds, the surfaces one after another in `Order` with `Count` steps each. A step plays
	-- its slot's first `Length` seconds (Sound.PlaybackRegion).
	Sheet = 97413442276762,
	Slot = 0.5,
	Length = 0.45,
	Order = { "grass", "leaves", "mud", "gravel", "wood", "stone" },
	Count = { grass = 6, leaves = 2, mud = 1, gravel = 1, wood = 3, stone = 6 },

	Volume = 0.3, -- a walking step on grass, heard from right beside it
	Own = 0.7, -- this player's own steps (heard from the camera, right over them) a little under everyone else's
	-- by gait (the track the marker came from)
	Gait = { walk = 1, sprint = 1.8, crouch = 0.35 },
	-- by surface: what the recordings need to sit level with each other
	Surface = { grass = 1, leaves = 1, mud = 1, gravel = 0.8, wood = 0.9, stone = 0.9 },
	Pitch = 1,
	PitchJitter = 0.06, -- each step varies by up to this much either way (single-recording surfaces most of all)
	-- studs from the camera past which a step isn't played at all (the falloff, Config/Audio.Profiles.Footstep, has it
	-- nearly silent there anyway); sprinting carries furthest
	Range = { walk = 70, sprint = 120, crouch = 30 },

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
