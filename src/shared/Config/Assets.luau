--!strict
-- The asset library registry. One entry per uploaded asset, grouped by category. Each category
-- mirrors three places:
--   repo:    assets/<category>/...                      (sources + generator scripts)
-- Player gear is organized by team (user 2026-10-12: "completely reorganize all player asset stuff and just organize
-- it by teams"): category "Teams", folder "<Team>/<Kind>" (Olive, Grey, White, Shared), repo assets/teams/<team>/.
-- Weapons stay together in "Weapons", by team inside ("Olive/Rifles": the Carcano is the olive team's).
--   Studio:  ReplicatedStorage.Assets.<Category>.<Sub>   (synced by src/dev/Library from this table)
--   gallery: Workspace.DevGallery                       (dev-only showroom, src/dev/Library)
-- Conventions: assets/README.md. Uploads: tools/opencloud/upload_asset.py (creator 180563380).

export type Entry = {
	id: number?, -- Open Cloud asset id (uploaded assets: a Model containing the meshes)
	template: string?, -- procedural assets: Config/Buildings.Templates key, built by `generator`
	prop: string?, -- procedural props: Config/Props.Kinds entry, built by `generator`
	uniform: string?, -- a uniform: Config/Uniforms.Kits key; the library holds its Shirt + Pants (nothing uploaded here)
	category: string, -- top-level library folder
	folder: string, -- subfolder inside the category; "/" nests ("Olive/Helmets")
	source: string?, -- repo path of the uploaded file (uploaded assets)
	generator: string?, -- script that regenerates the source
	description: string,
	variants: { [string]: { string } }?, -- named mesh groups inside the kit
	-- gear worn as a rigid Accessory: which character attachment it hangs on, its color (a team's helmet in that
	-- team's color; light white-grey while it has no team), and `brim`, the height of its bottom edge above the
	-- head's center (studs). `parts` colors extra meshes welded to the handle (one flat color each). `attach` is the
	-- exact HatAttachment position in the handle when the mesh isn't front/back symmetric (its bounding-box center
	-- is off the axis; tools/blender/gear/helmet.py prints it). Helmets are sized to sit over hair
	-- (docs/HATS.md "Helmets fit over hair"; tools/blender/gear/hair_fit.json)
	fit: {
		attachment: string,
		color: { number },
		brim: number,
		parts: { [string]: { number } }?,
		attach: { number }?,
		-- helmets: `shell`, the helmet shape (its shaved preview hair: docs/HATS.md "Two head states"; variants share
		-- their default's), and `center`, where the shell part's center sits above its origin (the brim's center,
		-- Roblox axes; tools/blender/gear/helmet.py prints it as "BBOX center")
		shell: string?,
		center: { number }?,
	}?,
}

local Assets = {
	Categories = { "Teams", "Weapons", "Foliage", "Buildings", "Props", "Vehicles", "Characters", "VFX" },

	Entries = {
		rifle_m91 = {
			id = 124122824797146, -- v2: inside-out faces fixed (v1 117583297352653)
			category = "Weapons",
			folder = "Olive/Rifles",
			source = "assets/weapons/olive/rifle_m91.fbx",
			generator = "tools/blender/weapons/export_blend.py",
			description = "Carcano M91 long rifle, the olive team's default (master: assets/weapons/olive/rifle_m91.blend). Rigged from Config/Weapons.",
		},
		rifle_g98 = {
			id = 87306177976563, -- v2: sight line 0.057 over the bore (v1 78115054198721)
			category = "Weapons",
			folder = "Grey/Rifles",
			source = "assets/weapons/grey/rifle_g98.fbx",
			generator = "tools/blender/weapons/gewehr98.py",
			description = "Gewehr 98 rifle, the grey team's default (built from its trace: tools/blender/weapons/trace/gewehr98.py). Rigged from Config/Weapons.",
		},
		rifle_smle = {
			id = 113048279523913, -- v4: stock flat beside the action, the bridge on both walls (v1-v3 see-through in first person, user 2026-10-13)
			category = "Weapons",
			folder = "White/Rifles",
			source = "assets/weapons/white/rifle_smle.fbx",
			generator = "tools/blender/weapons/smle.py",
			description = "Lee-Enfield SMLE Mk III, the white team's rifle (built from its trace: tools/blender/weapons/trace/smle.py). Rigged from Config/Weapons.",
		},
		staff = {
			id = 109018663192748, -- v2: team accents (binding, ribbon, head ring, foot cap), colored per team
			category = "Weapons",
			folder = "Shared/Staffs",
			source = "assets/weapons/shared/staff.fbx",
			generator = "tools/blender/weapons/staff.py",
			description = "The mage staff, shared by every team: knotted faceted wood, an iron sleeve at the grip and a foot cap, a metal band and a ring under the head, a cloth binding and a ribbon (assets/weapons/staff/staff.blend, exported in gun space by tools/blender/weapons/export_staff.py). Rigged and colored per team from Config/Weapons (staff_grey / staff_olive / staff_white).",
		},
		shotgun_m1897 = {
			id = 118242502631158, -- v2: the bolt's channel in the receiver's back, 68 bigger holes (v1 112699594475693)
			category = "Weapons",
			folder = "Shared/Shotguns",
			source = "assets/weapons/shared/shotgun_m1897.fbx",
			generator = "tools/blender/weapons/m1897.py",
			description = "Winchester M1897 trench gun, the shotgun of all three teams (built from its trace: tools/blender/weapons/trace/m1897.py; a shell on the carrier shows through the port). Rigged from Config/Weapons.",
		},
		uniform1 = {
			category = "Teams",
			folder = "Grey/Uniform",
			uniform = "uniform1",
			source = "assets/teams/grey/uniform/uniform1.json",
			generator = "tools/clothing/uniform.py",
			description = "The grey team's uniform (slate): Shirt + Pants images from Config/Uniforms.Kits.uniform1.",
		},
		uniform2 = {
			category = "Teams",
			folder = "Olive/Uniform",
			uniform = "uniform2",
			source = "assets/teams/olive/uniform/uniform2.json",
			generator = "tools/clothing/uniform.py",
			description = "The olive team's uniform: Shirt + Pants images from Config/Uniforms.Kits.uniform2.",
		},
		rig1 = {
			id = 84046347370958,
			category = "Teams",
			folder = "Shared/Rigs",
			source = "assets/teams/shared/rigs/rig1.fbx",
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
			category = "Teams",
			folder = "Shared/Rigs",
			source = "assets/teams/shared/rigs/rig2.fbx",
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
			category = "Teams",
			folder = "Shared/Rigs",
			source = "assets/teams/shared/rigs/rig3.fbx",
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
			id = 84488254718914,
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/default/helmet_stahl.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "Stahlhelm-style helmet, grey team: deep dome, small forward visor peak, skirt flaring over the ears and "
				.. "neck; 12 flat sides (216 tris). No national decal (fictional nations).",
			-- rim baseline 0.15 below the head center; the back of the skirt is the lowest point
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27,
				attach = { 0, 0.235, 0.006 },
				shell = "stahl",
				center = { 0, 0.5148, -0.0059 },
			},
		},
		helmet_stahl_goggles = {
			id = 96839649750928,
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_goggles.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_stahl (unchanged) with a dark leather strap round the dome's slope and big "
				.. "aviator goggles on the front; flat amber lenses. Grey team.",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27,
				attach = { 0, 0.235, 0.006 },
				parts = { Strap = { 46, 39, 34 }, Lens = { 222, 150, 52 } },
				shell = "stahl",
				center = { 0, 0.5148, -0.0059 },
			},
		},
		helmet_stahl_ammo = {
			id = 106418173364815,
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_ammo.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_stahl (unchanged) with a dark leather band on the step above the skirt and "
				.. "five red shotgun shells on gold heads on the wearer's right, held by a thin flat strap. Grey team.",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27,
				attach = { 0, 0.235, 0.006 },
				parts = { Band = { 46, 39, 34 }, Hull = { 150, 54, 44 }, Brass = { 204, 172, 92 } },
				shell = "stahl",
				center = { 0, 0.5148, -0.0059 },
			},
		},
		helmet_m33_goggles = {
			id = 129172538186129,
			category = "Teams",
			folder = "Olive/Helmets",
			source = "assets/teams/olive/helmets/variants/helmet_m33_goggles.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "helmet_m33 with a leather strap and big aviator goggles riding on the front slope; flat blue lenses. Olive team.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.18,
				parts = { Strap = { 106, 72, 46 }, Lens = { 86, 150, 214 } },
				shell = "m33",
				center = { 0, 0.5415, 0 },
			},
		},
		helmet_m33_ammo = {
			id = 111462508849651,
			category = "Teams",
			folder = "Olive/Helmets",
			source = "assets/teams/olive/helmets/variants/helmet_m33_ammo.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_m33 (unchanged) with a leather band low round the dome and five red shotgun "
				.. "shells on brass heads on the wearer's right, held by a thin flat strap wrapped round each. Olive team.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.18,
				parts = { Band = { 106, 72, 46 }, Hull = { 150, 54, 44 }, Brass = { 176, 146, 80 } },
				shell = "m33",
				center = { 0, 0.5415, 0 },
			},
		},
		helmet_m33 = {
			id = 89604539658442,
			category = "Teams",
			folder = "Olive/Helmets",
			source = "assets/teams/olive/helmets/default/helmet_m33.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "M33-style helmet, olive team: rounded dome worn low, rim raised at the front, arched over the ears, "
				.. "lower at the back; tuck above the rim, sloped sides, rounded crown, 12 sides (216 tris).",
			-- color = uniform2 cloth; brim = the lowest rim point (the back)
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.18,
				shell = "m33",
				center = { 0, 0.5415, 0 },
			},
		},
		helmet_brodie = {
			id = 93232405386184,
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/default/helmet_brodie.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "WW1 Brodie helmet, the future white team's default (user 2026-10-12): 10 flat sides, short "
				.. "down-sloping brim (158 tris), worn tipped back 8 degrees.",
			fit = {
				attachment = "HatAttachment",
				color = { 214, 214, 210 },
				brim = 0.06,
				shell = "brodie",
				center = { 0, 0.3818, 0.0039 },
			},
		},
		helmet_brodie_goggles = {
			id = 107628167670818,
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/variants/helmet_brodie_goggles.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_brodie (unchanged, tipped back) with a leather strap round the dome's slope "
				.. "and big aviator goggles on the front; flat teal lenses. White team (colours a proposal).",
			fit = {
				attachment = "HatAttachment",
				color = { 214, 214, 210 },
				brim = 0.06,
				parts = { Strap = { 120, 84, 56 }, Lens = { 72, 176, 150 } },
				shell = "brodie",
				center = { 0, 0.3818, 0.0039 },
			},
		},
		helmet_brodie_ammo = {
			id = 101501598430404,
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/variants/helmet_brodie_ammo.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_brodie (unchanged, tipped back) with a leather band on the wall above the brim "
				.. "and five red shotgun shells on steel heads on the wearer's right, held by a thin flat strap. White team.",
			fit = {
				attachment = "HatAttachment",
				color = { 214, 214, 210 },
				brim = 0.06,
				parts = { Band = { 120, 84, 56 }, Hull = { 150, 54, 44 }, Brass = { 168, 170, 174 } },
				shell = "brodie",
				center = { 0, 0.3818, 0.0039 },
			},
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
