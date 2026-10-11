--!strict
-- The asset library registry. One entry per uploaded asset, grouped by category. Each category
-- mirrors three places:
--   repo:    assets/<category>/...                      (sources + generator scripts)
--   Studio:  ReplicatedStorage.Assets.<Category>.<Sub>   (synced by src/dev/Library from this table)
--   gallery: Workspace.DevGallery                       (dev-only showroom, src/dev/Library)
-- Conventions: assets/README.md. Uploads: tools/opencloud/upload_asset.py (creator 180563380).

export type Entry = {
	id: number?, -- Open Cloud asset id (uploaded assets: a Model containing the meshes)
	template: string?, -- procedural assets: Config/Buildings.Templates key, built by `generator`
	prop: string?, -- procedural props: Config/Props.Kinds entry, built by `generator`
	category: string, -- top-level library folder
	folder: string, -- subfolder inside the category
	source: string?, -- repo path of the uploaded file (uploaded assets)
	generator: string?, -- script that regenerates the source
	description: string,
	variants: { [string]: { string } }?, -- named mesh groups inside the kit
	-- gear worn as a rigid Accessory: which character attachment it hangs on, its color (a team's helmet in that
	-- team's color; light white-grey while it has no team), and `brim`, the height of its bottom edge above the
	-- head's center (studs). `parts` colors extra meshes welded to the handle (one flat color each). `attach` is the
	-- exact HatAttachment position in the handle when the mesh isn't front/back symmetric (its bounding-box center
	-- is off the axis; tools/blender/gear/helmet.py prints it)
	fit: {
		attachment: string,
		color: { number },
		brim: number,
		parts: { [string]: { number } }?,
		attach: { number }?,
	}?,
}

local Assets = {
	Categories = { "Foliage", "Buildings", "Props", "Vehicles", "Weapons", "Characters", "VFX" },

	Entries = {
		rifle_m91 = {
			id = 124122824797146, -- v2: inside-out faces fixed (v1 117583297352653)
			category = "Weapons",
			folder = "Rifles",
			source = "assets/weapons/rifle_m91.fbx",
			generator = "tools/blender/weapons/export_blend.py",
			description = "Carcano M91 long rifle, the olive team's default (master: assets/weapons/rifle_m91.blend). Rigged from Config/Weapons.",
		},
		rig1 = {
			id = 84046347370958,
			category = "Characters",
			folder = "Gear",
			source = "assets/characters/gear/shared/rigs/rig1.fbx",
			generator = "tools/blender/gear/rig.py",
			description = "Rig (pouches only): shoulder bands + belt, two big pouches on the torso's sides under the arms, a wide front pouch.",
			-- welded to the Torso at each part's offset from the export's Origin marker (variant `rig1`)
			fit = {
				attachment = "Torso",
				color = { 150, 104, 80 },
				brim = 0,
				parts = { Leather = { 150, 104, 80 }, Pouch = { 192, 158, 116 }, Metal = { 70, 66, 60 } },
			},
		},
		rig2 = {
			id = 82520824821944,
			category = "Characters",
			folder = "Gear",
			source = "assets/characters/gear/shared/rigs/rig2.fbx",
			generator = "tools/blender/gear/rig.py",
			description = "Rig: tab-pouch model - two tall pouches on the bands at chest height, one wide pouch on the front left.",
			-- welded to the Torso at each part's offset from the export's Origin marker (variant `rig2`)
			fit = {
				attachment = "Torso",
				color = { 150, 104, 80 },
				brim = 0,
				parts = { Leather = { 150, 104, 80 }, Pouch = { 192, 158, 116 }, Metal = { 70, 66, 60 } },
			},
		},
		rig3 = {
			id = 104179782361178,
			category = "Characters",
			folder = "Gear",
			source = "assets/characters/gear/shared/rigs/rig3.fbx",
			generator = "tools/blender/gear/rig.py",
			description = "Rig: strap-pouch model - two medium pouches out to the torso edges, one big extra-bulky center pouch.",
			-- welded to the Torso at each part's offset from the export's Origin marker (variant `rig3`)
			fit = {
				attachment = "Torso",
				color = { 150, 104, 80 },
				brim = 0,
				parts = { Leather = { 150, 104, 80 }, Pouch = { 192, 158, 116 }, Metal = { 70, 66, 60 } },
			},
		},
		helmet_stahl = {
			id = 116385902519252,
			category = "Characters",
			folder = "Gear",
			source = "assets/characters/gear/grey/helmets/default/helmet_stahl.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "Stahlhelm-style helmet, grey team: deep dome, small forward visor peak, skirt flaring over the ears and "
				.. "neck; 12 flat sides (216 tris). No national decal (fictional nations).",
			-- rim baseline 0.15 below the head center; the back of the skirt is the lowest point
			fit = { attachment = "HatAttachment", color = { 80, 82, 86 }, brim = -0.27, attach = { 0, 0.31, 0.005 } },
		},
		helmet_m33_goggles = {
			id = 89737787734153,
			category = "Characters",
			folder = "Gear",
			source = "assets/characters/gear/olive/helmets/variants/helmet_m33_goggles.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "helmet_m33 with a leather strap and big aviator goggles riding on the front slope; flat blue lenses. Olive team.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.18,
				parts = { Strap = { 106, 72, 46 }, Lens = { 86, 150, 214 } },
			},
		},
		helmet_m33_ammo = {
			id = 136009347680449,
			category = "Characters",
			folder = "Gear",
			source = "assets/characters/gear/olive/helmets/variants/helmet_m33_ammo.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_m33 (unchanged) with a leather band low round the dome and five red shotgun "
				.. "shells on brass heads in a loop strip at the front. Olive team.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.18,
				parts = { Band = { 106, 72, 46 }, Hull = { 150, 54, 44 }, Brass = { 176, 146, 80 } },
			},
		},
		helmet_m33 = {
			id = 96856831451407,
			category = "Characters",
			folder = "Gear",
			source = "assets/characters/gear/olive/helmets/default/helmet_m33.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "M33-style helmet, olive team: rounded dome worn low, rim raised at the front, arched over the ears, "
				.. "lower at the back; tuck above the rim, sloped sides, rounded crown, 12 sides (216 tris).",
			-- color = uniform2 cloth; brim = the lowest rim point (the back)
			fit = { attachment = "HatAttachment", color = { 116, 114, 72 }, brim = -0.18 },
		},
		helmet_brodie = {
			id = 91232491229419,
			category = "Characters",
			folder = "Gear",
			source = "assets/characters/gear/shared/helmets/helmet_brodie.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "WW1 Brodie helmet: 10 flat sides, short down-sloping brim (158 tris), 1.76 studs across.",
			fit = { attachment = "HatAttachment", color = { 214, 214, 210 }, brim = 0.16 },
		},
		TreeKit = {
			id = 78828564935129,
			category = "Foliage",
			folder = "Trees",
			source = "assets/foliage/trees/tree_kit.fbx",
			generator = "tools/blender/trees.py",
			description = "Low-poly trees: 3 pines, 3 broadleaf, 2 birch. Meshes <Variant>_Trunk/_Canopy.",
			variants = {
				Pine = { "PineA", "PineB", "PineC" },
				Broadleaf = { "BroadleafA", "BroadleafB", "BroadleafC" },
				Birch = { "BirchA", "BirchB" },
			},
		},
		GrassKit = {
			id = 84469552965997,
			category = "Foliage",
			folder = "Grass",
			source = "assets/foliage/grass/grass_kit.fbx",
			generator = "tools/blender/grass.py",
			description = "Low-poly grass tufts GrassA..D for the client grass system (Config/Foliage).",
			variants = { Tuft = { "GrassA", "GrassB", "GrassC", "GrassD" } },
		},
		-- Procedural buildings (no upload): generated by src/dev/Buildings from Config/Buildings.Templates.
		ThatchCottage = {
			category = "Buildings",
			folder = "Houses",
			template = "ThatchCottage",
			generator = "src/dev/Buildings/init.luau",
			description = "Thatched one-story cottage",
		},
		TileCottage = {
			category = "Buildings",
			folder = "Houses",
			template = "TileCottage",
			generator = "src/dev/Buildings/init.luau",
			description = "Brick tile-roof cottage",
		},
		TwoStoryHouse = {
			category = "Buildings",
			folder = "Houses",
			template = "TwoStoryHouse",
			generator = "src/dev/Buildings/init.luau",
			description = "Two-story house / farmhouse",
		},
		LongCottage = {
			category = "Buildings",
			folder = "Houses",
			template = "LongCottage",
			generator = "src/dev/Buildings/init.luau",
			description = "Long thatched pair of cottages",
		},
		Barn = {
			category = "Buildings",
			folder = "Farm",
			template = "Barn",
			generator = "src/dev/Buildings/init.luau",
			description = "Board barn",
		},
		Shed = {
			category = "Buildings",
			folder = "Farm",
			template = "Shed",
			generator = "src/dev/Buildings/init.luau",
			description = "Small board shed",
		},
		-- Procedural village props: generated by src/dev/Props (dimensions in Config/Props).
		StoneWall = {
			category = "Props",
			folder = "Village",
			prop = "StoneWall",
			generator = "src/dev/Props/init.luau",
			description = "Dry-stone garden wall (hoppable)",
		},
		PicketFence = {
			category = "Props",
			folder = "Village",
			prop = "PicketFence",
			generator = "src/dev/Props/init.luau",
			description = "Painted picket fence (hoppable)",
		},
		RailFence = {
			category = "Props",
			folder = "Village",
			prop = "RailFence",
			generator = "src/dev/Props/init.luau",
			description = "Post-and-rail fence (hoppable)",
		},
		Hedge = {
			category = "Props",
			folder = "Village",
			prop = "Hedge",
			generator = "src/dev/Props/init.luau",
			description = "Hedge (blocks movement and sight)",
		},
		Pole = {
			category = "Props",
			folder = "Village",
			prop = "Pole",
			generator = "src/dev/Props/init.luau",
			description = "Telegraph pole with crossarm",
		},
		Signpost = {
			category = "Props",
			folder = "Village",
			prop = "Signpost",
			generator = "src/dev/Props/init.luau",
			description = "Fingerpost signpost",
		},
		Well = {
			category = "Props",
			folder = "Village",
			prop = "Well",
			generator = "src/dev/Props/init.luau",
			description = "Stone well with a little roof",
		},
		Trough = {
			category = "Props",
			folder = "Village",
			prop = "Trough",
			generator = "src/dev/Props/init.luau",
			description = "Stone water trough",
		},
		Barrels = {
			category = "Props",
			folder = "Village",
			prop = "Barrels",
			generator = "src/dev/Props/init.luau",
			description = "Cluster of barrels",
		},
		Woodpile = {
			category = "Props",
			folder = "Village",
			prop = "Woodpile",
			generator = "src/dev/Props/init.luau",
			description = "Stacked firewood",
		},
		Haystack = {
			category = "Props",
			folder = "Village",
			prop = "Haystack",
			generator = "src/dev/Props/init.luau",
			description = "Haystack",
		},
		Cart = {
			category = "Props",
			folder = "Village",
			prop = "Cart",
			generator = "src/dev/Props/init.luau",
			description = "Wooden hand cart",
		},
		Car = {
			category = "Props",
			folder = "Village",
			prop = "Car",
			generator = "src/dev/Props/init.luau",
			description = "Parked 1930s car",
		},
	} :: { [string]: Entry },

	-- Tree placement: height in studs (trunk base to canopy top) at scale 1.
	TreeTargetHeight = { Pine = 40, Broadleaf = 30, Birch = 27 },
}

return table.freeze(Assets)
