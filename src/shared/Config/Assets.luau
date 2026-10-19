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
	-- hairs: where the mesh's bounding-box center sits in head space (Roblox axes)
	hair: { center: { number } }?,
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
			-- v3: a metal-lined magazine well under the action (user 2026-10-19: wood showed where the rounds should be);
			-- v2 87306177976563: sight line 0.057 over the bore (v1 78115054198721)
			id = 71283772137659,
			category = "Weapons",
			folder = "Grey/Rifles",
			source = "assets/weapons/grey/rifle_g98.fbx",
			generator = "tools/blender/weapons/gewehr98.py",
			description = "Gewehr 98 rifle, the grey team's default (built from its trace: tools/blender/weapons/trace/gewehr98.py). Rigged from Config/Weapons.",
		},
		rifle_smle = {
			-- v6: a metal-lined magazine well under the action (user 2026-10-19: wood showed where the rounds should be);
			-- v5 130639053099807: the bolt handle in a notch in the body and socket, the butt clear of the cocking piece (user 2026-10-13:
			-- clipping at the bolt's end and lever); v4 113048279523913: stock flat beside the action, the bridge on both
			-- walls (v1-v3 see-through in first person)
			id = 89375001951596,
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
			-- v3: the hammer in its own slot, cocked lower under the bolt (v2 118242502631158: the bolt's channel in the
			-- receiver's back, 68 bigger holes; v1 112699594475693)
			id = 109341050997401,
			category = "Weapons",
			folder = "Shared/Shotguns",
			source = "assets/weapons/shared/shotgun_m1897.fbx",
			generator = "tools/blender/weapons/m1897.py",
			description = "Winchester M1897 trench gun, the shotgun of all three teams (built from its trace: tools/blender/weapons/trace/m1897.py; a shell on the carrier shows through the port). Rigged from Config/Weapons.",
		},
		-- the grenades, one per team (tools/blender/weapons/grenades.py; Config/Weapons, Config/Grenades)
		grenade_mills = {
			id = 138444756692849,
			category = "Weapons",
			folder = "White/Grenades",
			source = "assets/weapons/white/grenade_mills.fbx",
			generator = "tools/blender/weapons/grenades.py",
			description = "Mills bomb No. 5, the white team's grenade (from references/weapons/grenades/mills_*.jpg): six columns of segments, base and filler plugs, the lever, pin and ring. Rigged from Config/Weapons.",
		},
		grenade_stick = {
			id = 76412002834293,
			category = "Weapons",
			folder = "Grey/Grenades",
			source = "assets/weapons/grey/grenade_stick.fbx",
			generator = "tools/blender/weapons/grenades.py",
			description = "Stielhandgranate M1917, the grey team's grenade (from references/weapons/grenades/stick_am613018_1.jpg): the can head, iron collar, wooden handle and screw cap. Rigged from Config/Weapons.",
		},
		grenade_sipe = {
			id = 97677876339961,
			category = "Weapons",
			folder = "Olive/Grenades",
			source = "assets/weapons/olive/grenade_sipe.fbx",
			generator = "tools/blender/weapons/grenades.py",
			description = "SIPE, the olive team's grenade (from references/weapons/grenades/sipe_museo.jpg): seven columns of segments, a flat bottom and the fuse tube. Rigged from Config/Weapons.",
		},
		-- Artillery (user 2026-10-18): player-placed, hard to build, set up in the very back for area damage. Shared
		-- by every team, painted per team (Config/Palette.Artillery). Moving parts are their own meshes; firing is
		-- later game code.
		artillery_qf18 = {
			id = 123043192837733,
			category = "Weapons",
			folder = "Shared/Artillery",
			source = "assets/weapons/shared/artillery_qf18.fbx",
			generator = "tools/blender/artillery/qf18.py",
			description = "QF 18-pounder field gun at real size (built from its trace: tools/blender/artillery/trace/qf18.py). Moving parts: Wheels + Tyres roll, Mount traverses, Cradle elevates, Barrel + Bore recoil, Breech opens.",
		},
		artillery_howitzer = {
			id = 82367327569698,
			category = "Weapons",
			folder = "Shared/Artillery",
			source = "assets/weapons/shared/artillery_howitzer.fbx",
			generator = "tools/blender/artillery/howitzer.py",
			description = "The magic howitzer: a BL 9.2-inch howitzer at 1.3x with glowing rune bands, a focus crystal in the breech and a rune circle round its racer (trace: tools/blender/artillery/trace/howitzer.py). Moving parts: Mount traverses, Cradle elevates, Barrel + BarrelRunes + Bore recoil, Breech + Crystal open.",
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
		bandage_roll = {
			id = 97919711807234, -- v2: plain part names (v1 81519541602272)
			category = "Teams",
			folder = "Shared/Bandages",
			source = "assets/teams/shared/bandages/bandage_roll.fbx",
			generator = "tools/blender/gear/bandages.py",
			description = "Rolled bandage held in the hand (mesh Cloth); origin at the roll centre, axis along X.",
		},
		dressing_packet = {
			id = 77548616662657, -- v2: plain part names (v1 98977144276918)
			category = "Teams",
			folder = "Shared/Bandages",
			source = "assets/teams/shared/bandages/dressing_packet.fbx",
			generator = "tools/blender/gear/bandages.py",
			description = "The med pack: canvas field dressing (Canvas), red tear thread round one end (Thread), green cross on top (Cross).",
		},
		bandage_unroll = {
			id = 135562484794642, -- v2: plain part names (v1 100744010298901)
			category = "Teams",
			folder = "Shared/Bandages",
			source = "assets/teams/shared/bandages/bandage_unroll.fbx",
			generator = "tools/blender/gear/bandages.py",
			description = "Bandage that unrolls for the wrap animation: one skinned mesh (Cloth), bones Root -> Strip1..Strip8 (0.5 studs each), strip straight out toward -Z at rest.",
		},
		wrap_arm = {
			id = 113940896143702, -- v2: plain part names (v1 118691271151526)
			category = "Teams",
			folder = "Shared/Bandages",
			source = "assets/teams/shared/bandages/wrap_arm.fbx",
			generator = "tools/blender/gear/bandages.py",
			description = "Bandage worn on the left arm (forearm, 3 turns); its Origin goes at the arm part centre. Place by the Origin position and keep each part's imported rotation (as Helmets / Armory do); never PivotTo the model (its pivot is rotated: KNOWN_TRAPS).",
		},
		wrap_leg = {
			id = 94242164038534, -- v2: plain part names (v1 83469869892044)
			category = "Teams",
			folder = "Shared/Bandages",
			source = "assets/teams/shared/bandages/wrap_leg.fbx",
			generator = "tools/blender/gear/bandages.py",
			description = "Bandage worn on the right leg (thigh, 2 turns); its Origin goes at the leg part centre. Place by the Origin position and keep each part's imported rotation (as Helmets / Armory do); never PivotTo the model (its pivot is rotated: KNOWN_TRAPS).",
		},
		wrap_head = {
			id = 111609113227954, -- v4: follows the head's rounded top (v3 75131246502526, v2 120626644598162, v1 93649111980606)
			category = "Teams",
			folder = "Shared/Bandages",
			source = "assets/teams/shared/bandages/wrap_head.fbx",
			generator = "tools/blender/gear/bandages.py",
			description = "Bandage worn round the head (2 crossing turns); its Origin goes at the head part centre. Place by the Origin position and keep each part's imported rotation (as Helmets / Armory do); never PivotTo the model (its pivot is rotated: KNOWN_TRAPS).",
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
			id = 96961743783144, -- hollow (docs/HATS.md "Hollow helmets"; capped: 84488254718914)
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
				brim = -0.16, -- raised 0.11 so the eyes show (user 2026-10-13; was -0.27)
				attach = { 0, 0.125, 0.006 },
				shell = "stahl",
				center = { 0, 0.5148, -0.0059 },
			},
		},
		helmet_stahl_goggles = {
			id = 136877765689691, -- hollow (docs/HATS.md "Hollow helmets"; capped: 96839649750928)
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_goggles.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_stahl (unchanged) with a dark leather strap round the dome's slope and big "
				.. "aviator goggles on the front; flat amber lenses. Grey team.",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.16, -- raised 0.11 so the eyes show (user 2026-10-13; was -0.27)
				attach = { 0, 0.125, 0.006 },
				parts = { Strap = { 46, 39, 34 }, Lens = { 222, 150, 52 } },
				shell = "stahl",
				center = { 0, 0.5148, -0.0059 },
			},
		},
		helmet_stahl_ammo = {
			id = 137594790143815, -- hollow (docs/HATS.md "Hollow helmets"; capped: 106418173364815)
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_ammo.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_stahl (unchanged) with a dark leather band on the step above the skirt and "
				.. "five red shotgun shells on gold heads on the wearer's right, held by a thin flat strap. Grey team.",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.16, -- raised 0.11 so the eyes show (user 2026-10-13; was -0.27)
				attach = { 0, 0.125, 0.006 },
				parts = { Band = { 46, 39, 34 }, Hull = { 150, 54, 44 }, Brass = { 204, 172, 92 } },
				shell = "stahl",
				center = { 0, 0.5148, -0.0059 },
			},
		},
		helmet_m33_goggles = {
			id = 99499894447280, -- hollow (docs/HATS.md "Hollow helmets"; capped: 129172538186129)
			category = "Teams",
			folder = "Olive/Helmets",
			source = "assets/teams/olive/helmets/variants/helmet_m33_goggles.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "helmet_m33 with a leather strap and big aviator goggles riding on the front slope; flat blue lenses. Olive team.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.13, -- raised 0.05 so the eyes show (user 2026-10-13; was -0.18)
				parts = { Strap = { 106, 72, 46 }, Lens = { 86, 150, 214 } },
				shell = "m33",
				center = { 0, 0.5415, 0 },
			},
		},
		helmet_m33_ammo = {
			id = 106864180395816, -- hollow (docs/HATS.md "Hollow helmets"; capped: 111462508849651)
			category = "Teams",
			folder = "Olive/Helmets",
			source = "assets/teams/olive/helmets/variants/helmet_m33_ammo.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_m33 (unchanged) with a leather band low round the dome and five red shotgun "
				.. "shells on brass heads on the wearer's right, held by a thin flat strap wrapped round each. Olive team.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.13, -- raised 0.05 so the eyes show (user 2026-10-13; was -0.18)
				parts = { Band = { 106, 72, 46 }, Hull = { 150, 54, 44 }, Brass = { 176, 146, 80 } },
				shell = "m33",
				center = { 0, 0.5415, 0 },
			},
		},
		helmet_m33 = {
			id = 90751617241838, -- hollow (docs/HATS.md "Hollow helmets"; capped: 89604539658442)
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
				brim = -0.13, -- raised 0.05 so the eyes show (user 2026-10-13; was -0.18)
				shell = "m33",
				center = { 0, 0.5415, 0 },
			},
		},
		helmet_brodie = {
			id = 111983459615468, -- hollow (docs/HATS.md "Hollow helmets"; capped: 93232405386184)
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
			id = 137564109106630, -- hollow (docs/HATS.md "Hollow helmets"; capped: 107628167670818)
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
			id = 70619798795232, -- hollow (docs/HATS.md "Hollow helmets"; capped: 101501598430404)
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
		GrassBlades = {
			id = 71473325394731,
			category = "Foliage",
			folder = "Grass",
			source = "assets/foliage/grass/grass_blades.fbx",
			generator = "tools/blender/grass_blades.py",
			description = "Thin, flowy grass blade patches BladeA..C (12-20 curved blades each) for the client grass's second layer (Config/Foliage.Blades), in place of Roblox's terrain grass.",
			variants = { Blade = { "BladeA", "BladeB", "BladeC" } },
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
		-- Soldier hairs (user 2026-10-14; docs/HAIRS.md): per style the original (`hair_<style>`, worn bareheaded or once
		-- the helmet is shot off) and one helmet-on hair per helmet shell (`hair_<style>_<shell>`, shaved where the shell
		-- covers it: tools/blender/gear/hair_under.py). Shop hairs used with their creators' okay: they stay in Roblox
		-- (files local, ids only here). `hair.center`: the mesh's bounding-box center in head space (Roblox axes; worn
		-- at head.CFrame * CFrame.new(center)), from tools/hair/export_hairs.py. Recolored per soldier (Config/Uniforms).
		hair_wolf_cut = {
			id = 87693191747101,
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/hair_wolf_cut_bare.fbx",
			generator = "tools/hair/export_hairs.py",
			description = "Hair wolf_cut, original (3998 tris). From 18320597179 'Black Stylish Layered Wolf Cut Short Hair' (AvaSky).",
			hair = { center = { -0.0374, -0.0004, 0.0566 } },
		},
		hair_wolf_cut_m33 = {
			id = 131289307710891,
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/under/hair_wolf_cut_m33.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair wolf_cut under the m33 helmet: the original shaved where the shell covers it (3820 tris).",
			hair = { center = { 0.0529, -0.0744, 0.0426 } },
		},
		hair_wolf_cut_stahl = {
			id = 123155634788566,
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/under/hair_wolf_cut_stahl.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair wolf_cut under the stahl helmet: the original shaved where the shell covers it (3978 tris).",
			hair = { center = { 0.024, -0.088, 0.0482 } },
		},
		hair_wolf_cut_brodie = {
			id = 75494309088279,
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/under/hair_wolf_cut_brodie.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair wolf_cut under the brodie helmet: the original shaved where the shell covers it (3937 tris).",
			hair = { center = { 0.0918, -0.1082, 0.0289 } },
		},
		hair_low_ponytail = {
			id = 102239211504647,
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/hair_low_ponytail_bare.fbx",
			generator = "tools/hair/export_hairs.py",
			description = "Hair low_ponytail, original (3132 tris). From 14401441197 'Low Ponytail (Black)' (YOU LOVE HAIR).",
			hair = { center = { 0, -0.694, 0.1865 } },
		},
		hair_low_ponytail_m33 = {
			id = 85504697777545,
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/under/hair_low_ponytail_m33.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair low_ponytail under the m33 helmet: the original shaved where the shell covers it (3131 tris).",
			hair = { center = { 0, -0.694, 0.1865 } },
		},
		hair_low_ponytail_stahl = {
			id = 108435355713176,
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/under/hair_low_ponytail_stahl.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair low_ponytail under the stahl helmet: the original shaved where the shell covers it (3131 tris).",
			hair = { center = { 0, -0.694, 0.1865 } },
		},
		hair_low_ponytail_brodie = {
			id = 131603430842547,
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/under/hair_low_ponytail_brodie.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair low_ponytail under the brodie helmet: the original shaved where the shell covers it (3131 tris).",
			hair = { center = { 0, -0.694, 0.1865 } },
		},
		hair_m_wolf = {
			id = 135274996782454,
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/hair_m_wolf_bare.fbx",
			generator = "tools/hair/export_hairs.py",
			description = "Hair m_wolf, original (3997 tris). From 96306223630485 'Really Messy Emo Wolf Cut Boy Hair' (kwarm).",
			hair = { center = { 0.0284, 0.167, 0.0506 } },
		},
		hair_m_wolf_m33 = {
			id = 79768541923667,
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/under/hair_m_wolf_m33.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair m_wolf under the m33 helmet: the original shaved where the shell covers it (3329 tris).",
			hair = { center = { 0.0233, 0.0325, 0.0086 } },
		},
		hair_m_wolf_stahl = {
			id = 129400640299639,
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/under/hair_m_wolf_stahl.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair m_wolf under the stahl helmet: the original shaved where the shell covers it (3373 tris).",
			hair = { center = { 0.0354, 0.0146, 0.0608 } },
		},
		hair_m_wolf_brodie = {
			id = 82147726465629,
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/under/hair_m_wolf_brodie.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair m_wolf under the brodie helmet: the original shaved where the shell covers it (3242 tris).",
			hair = { center = { 0.0552, -0.0027, 0.0725 } },
		},
		hair_m_slick = {
			id = 134341339188089,
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/hair_m_slick_bare.fbx",
			generator = "tools/hair/export_hairs.py",
			description = "Hair m_slick, original (2963 tris). From 137919482126630 'Beautiful Swoop Hair Male' (Crooner).",
			hair = { center = { 0.0146, 0.2002, 0.0377 } },
		},
		hair_m_slick_m33 = {
			id = 131478334142059,
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/under/hair_m_slick_m33.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair m_slick under the m33 helmet: the original shaved where the shell covers it (3061 tris).",
			hair = { center = { 0.0146, 0.2002, 0.0377 } },
		},
		hair_m_slick_stahl = {
			id = 101353090993134,
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/under/hair_m_slick_stahl.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair m_slick under the stahl helmet: the original shaved where the shell covers it (3022 tris).",
			hair = { center = { 0.0146, 0.2002, 0.0377 } },
		},
		hair_m_slick_brodie = {
			id = 80089844700142,
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/under/hair_m_slick_brodie.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair m_slick under the brodie helmet: the original shaved where the shell covers it (3076 tris).",
			hair = { center = { 0.0128, 0.2002, 0.0403 } },
		},
		hair_m_midpart = {
			id = 131010005103271,
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/hair_m_midpart_bare.fbx",
			generator = "tools/hair/export_hairs.py",
			description = "Hair m_midpart, original (3615 tris). From 98001154915857 'Light Brown Sleek Male Hair' (platan).",
			hair = { center = { -0.0022, 0.1974, -0.0105 } },
		},
		hair_m_midpart_m33 = {
			id = 112252984245351,
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/under/hair_m_midpart_m33.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair m_midpart under the m33 helmet: the original shaved where the shell covers it (3923 tris).",
			hair = { center = { 0.0063, 0.1907, 0.0084 } },
		},
		hair_m_midpart_stahl = {
			id = 86983856412897,
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/under/hair_m_midpart_stahl.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair m_midpart under the stahl helmet: the original shaved where the shell covers it (3886 tris).",
			hair = { center = { 0.0059, 0.1835, 0.0119 } },
		},
		hair_m_midpart_brodie = {
			id = 125363532305753,
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/under/hair_m_midpart_brodie.fbx",
			generator = "tools/blender/gear/hair_under.py",
			description = "Hair m_midpart under the brodie helmet: the original shaved where the shell covers it (3785 tris).",
			hair = { center = { 0.0392, 0.1886, -0.0056 } },
		},
	} :: { [string]: Entry },

	-- Tree placement: height in studs (trunk base to canopy top) at scale 1.
	TreeTargetHeight = { Pine = 40, Broadleaf = 30, Birch = 27 },
}

return table.freeze(Assets)
