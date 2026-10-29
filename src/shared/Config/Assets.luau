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
	fidelity: string?, -- the meshes' CollisionFidelity (set by the Library sync: a running game can't set it)
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
		-- a soft cloth cap (the Engineer's, user 2026-10-27): no protection, a hit on it is a Head hit (src/server/Helmets)
		soft: boolean?,
		-- `brim` for a bald wearer: a cap that sits on its hair, lowered to rest on the bare head (user 2026-10-28)
		bald: number?,
	}?,
	-- hairs: where the mesh's bounding-box center sits in head space (Roblox axes); a rigged hair (an Origin marker at
	-- the head's centre, tools/hair/rig_hair.py) instead says how many bones sway it (src/client/HairMotion)
	hair: { center: { number }?, bones: number? }?,
	-- packs: how much further back (studs) the slung weapons ride over this pack (Config/Weapons `stow`; src/server/
	-- Armory): the pack's back surface where the weapon crosses it, minus the bare Torso's back (0.5)
	sling: number?,
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
		pistol_nagant = {
			-- v3: the chambers drilled through the cylinder and lined dark (an empty chamber is a hole), the rounds the
			-- 7.62x38R of tools/blender/weapons/pistol_ammo.py (Round<k> heads and crimped mouths + Bullet<k> noses),
			-- hidden Cartridge and Casing templates for the gate (v2 136927059301419: the cylinder's faces fixed, the grip
			-- two flat wood panels on a slimmer, rounded frame, a round per chamber filling its mouth; v1 100351614666603)
			id = 80228872124161,
			category = "Weapons",
			folder = "Olive/Pistols",
			source = "assets/weapons/olive/pistol_nagant.fbx",
			generator = "tools/blender/weapons/nagant.py",
			description = "Nagant M1895 revolver, the olive team's Engineer pistol (its shape from a low-poly reference: tools/blender/weapons/trace/nagant.py; a round part per chamber shows the rounds left). Rigged from Config/Weapons.",
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
			description = "Lee-Enfield SMLE Mk III, the brown team's rifle (built from its trace: tools/blender/weapons/trace/smle.py). Rigged from Config/Weapons.",
		},
		pistol_webley = {
			-- v3: the .455 rounds in detail (tools/blender/weapons/pistol_ammo.py: brass Round<k> + lead Bullet<k>) and the
			-- chambers drilled through (an empty one a hole); v2 138842852856190: rebuilt in our style over the user's
			-- reference model (Daz's "Webley Revolver Mk VI"); v1 73066004337005: traced from a photo, 10 parts
			id = 105356442537528,
			category = "Weapons",
			folder = "White/Pistols",
			source = "assets/weapons/white/pistol_webley.fbx",
			generator = "tools/blender/weapons/webley.py",
			description = "Webley Mk VI revolver, the brown team's Engineer pistol (built over the outlines in tools/blender/weapons/trace/webley_daz.py). Rigged from Config/Weapons.",
		},
		rifle_mondragon = {
			id = 77357570578798,
			category = "Weapons",
			folder = "Grey/Rifles",
			source = "assets/weapons/grey/rifle_mondragon.fbx",
			generator = "tools/blender/weapons/mondragon.py",
			description = "Mondragón FSK 15 semi-automatic rifle, the grey team's (W2; built from its trace: tools/blender/weapons/trace/mondragon.py; review assets/weapons/grey/review/rifle_mondragon_v7.blend). Rigged from Config/Weapons.",
		},
		rifle_remington8 = {
			id = 120790254551949,
			category = "Weapons",
			folder = "Olive/Rifles",
			source = "assets/weapons/olive/rifle_remington8.fbx",
			generator = "tools/blender/weapons/remington8.py",
			description = "Remington Model 8 semi-automatic rifle, the olive team's (W2; built from its trace: tools/blender/weapons/trace/remington8.py; review assets/weapons/olive/review/rifle_remington8_v4.blend). Rigged from Config/Weapons.",
		},
		rifle_winchester1907 = {
			id = 80789332043518,
			category = "Weapons",
			folder = "White/Rifles",
			source = "assets/weapons/white/rifle_winchester1907.fbx",
			generator = "tools/blender/weapons/winchester1907.py",
			description = "Winchester 1907 semi-automatic rifle, the brown team's (W2; built from its trace: tools/blender/weapons/trace/winchester1907.py; review assets/weapons/white/review/rifle_winchester1907_v6.blend; a detachable 15-round box). Rigged from Config/Weapons.",
		},
		staff = {
			id = 109018663192748, -- v2: team accents (binding, ribbon, head ring, foot cap), colored per team
			category = "Weapons",
			folder = "Shared/Staffs",
			source = "assets/weapons/shared/staff.fbx",
			generator = "tools/blender/weapons/staff.py",
			description = "The mage staff, shared by every team: knotted faceted wood, an iron sleeve at the grip and a foot cap, a metal band and a ring under the head, a cloth binding and a ribbon (assets/weapons/staff/staff.blend, exported in gun space by tools/blender/weapons/export_staff.py). Rigged and colored per team from Config/Weapons (staff_grey / staff_olive / staff_brown).",
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
			description = "Mills bomb No. 5, the brown team's grenade (from references/weapons/grenades/mills_*.jpg): six columns of segments, base and filler plugs, the lever, pin and ring. Rigged from Config/Weapons.",
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
			-- v5 (user 2026-10-26: a round breech ring and a round collar round the barrel, the slide stepped down and
			-- shorter, a satchel strapped to the trail's side, no sight post, axle boxes or linch pins, an open muzzle;
			-- v4 96409235868239)
			-- v4 (user 2026-10-26: round rivets, the handspike "tail" gone; v3 114781083776162: the shield's top flap flat,
			-- was tilted forward; team accent pieces <part>Trim / Fittings / Kit / Marking, Config/Palette.Artillery.Team;
			-- before it 123043192837733)
			id = 117442240826066,
			category = "Weapons",
			folder = "Shared/Artillery",
			source = "assets/weapons/shared/artillery_qf18.fbx",
			generator = "tools/blender/artillery/qf18.py",
			description = "QF 18-pounder field gun at real size (built from its trace: tools/blender/artillery/trace/qf18.py). Moving parts: Wheels + Tyres roll, Mount traverses, Cradle elevates, Barrel + Bore recoil, Breech opens.",
		},
		-- the MG nest's gun (user 2026-10-27; design approved by the user): v3 with the shield and the ammo box as their
		-- own parts, so a nest being built sets each up in its turn (v2 121882149099009 had them in the mount; v1
		-- 97496546594152 had Gun* names)
		mg08 = {
			id = 71692109520199,
			category = "Weapons",
			folder = "Shared/Artillery",
			source = "assets/weapons/shared/mg08.fbx",
			generator = "tools/blender/mgnest/mg08.py",
			description = "The MG nest's machine gun: an MG 08 traced from a photo (tools/blender/mgnest/trace/mg08.py), built 1.5x like the rifles (5.04 long), with an M1910-style arched shield and keyhole, on a turntable and yoke, its ammo box and a belt of the shared rifle round. Gun space: origin on the mount bag's top under the pivot, the muzzle -Z. Moving parts: Mount + MountFittings + Shield + ShieldTrim + ShieldFittings + BoxKit + BoxTrim + BoxFittings + Belt + Rounds + Bullets traverse, Cradle + CradleTrim + CradleFittings + Barrel + Bore elevate about (0, 1.035, 0); Carriage stays. Sights: a rear peep ring and a front ring with cross wires on y 1.78.",
		},
		artillery_howitzer = {
			-- v10 (user 2026-10-26: runes only round the crystal; meshing ring gear and pinions with hand wheels, turned by
			-- src/client/Artillery; a long recuperator off centre over the barrel and a fat buffer under it, an open
			-- muzzle, rivets on their surfaces, a player-wide ladder; v9 120030284881139)
			-- v9 (user 2026-10-26: curved brush-stroke runes, their halos taken off again: "it makes the runes
			-- indecipherable"; v8 98289221398793 had them); round rivets; v7 127169406913245: team accent pieces <part>Trim
			-- / Fittings / Kit / Marking,
			-- Config/Palette.Artillery.Team; v6 70753419490474, Bertha v11, the bigger cracked gem; v10 82040723469817;
			-- before it the BL 9.2-inch at 1.3x, 82367327569698)
			id = 138825884647241,
			category = "Weapons",
			folder = "Shared/Artillery",
			source = "assets/weapons/shared/artillery_bertha.fbx",
			generator = "tools/blender/artillery/bertha.py",
			description = "The magic howitzer: a 42 cm siege mortar of our own after the Big Bertha and the Gamma-Gerat, no wheels: a riveted box carriage turning on a giant toothed ring gear, a layered short barrel trunnioned high between its walls, two silos beside it and a housing under it, a bolted yoke and dial sight, a toothed elevating sector and big spoked hand wheels by the gunner's step, a crew deck and ladder at the back; the cracked, chipped gem (its cracks a part of their own, CrystalCracks) in a ring of runes on the round breech face, rune bands on the barrel, runes on the bed. Moving parts: Mount traverses, Cradle elevates, Barrel + BarrelRunes + Bore + Breech + Crystal + CrystalCracks recoil.",
		},
		-- the staff HUD's gem (user 2026-10-26: "trace a real gem that is shaped similarily", "make it physcial
		-- engravings", "add floating shards around it"; Config/Hud.Staff)
		hud_gem = {
			id = 98625703626073,
			category = "Weapons",
			folder = "Shared/Staffs",
			source = "assets/weapons/shared/hud_gem.fbx",
			generator = "tools/blender/weapons/hud_gem.py",
			description = "The staff HUD's gem: a lopsided double-terminated quartz point at quartz's true face angles (uneven faces, off-centre tips, four chips), its cracks V grooves cut into it (Crystal; the groove walls CrystalCracks), and five broken-off quartz shards floating round it (Shard1..Shard5, each centred on its own middle). The c axis along +Y.",
		},
		-- the shared rifle round (user 2026-10-26: the combat HUD shows each round on its own, Config/Hud.Round): the
		-- model every rifle's magazine rounds and casing are made from
		ammo_rifle = {
			id = 74015378077606,
			category = "Weapons",
			folder = "Shared/Ammo",
			source = "assets/weapons/shared/ammo_rifle.fbx",
			generator = "tools/blender/weapons/ammo.py",
			description = "The shared rifle round at the rifles' modelled scale: a loaded round (Case + Bullet, case head at the Origin, pointing -Z) and a spent Casing beside it (x +0.05).",
		},
		-- the pistol cartridges (user 2026-10-28: "detailed pistol and revolver shell", for the models and the ammo
		-- display), one per Engineer pistol, the same parts as ammo_rifle; real size (the pistols' modelled scale)
		ammo_nagant = {
			id = 78265810704735,
			category = "Weapons",
			folder = "Shared/Ammo",
			source = "assets/weapons/shared/ammo_nagant.fbx",
			generator = "tools/blender/weapons/pistol_ammo.py",
			description = "7.62x38R Nagant round (the Nagant M1895's): a long rimmed case crimped round a copper bullet seated wholly inside (Case + Bullet, case head at the Origin, pointing -Z) and a fired Casing beside it (x +0.05, its mouth open, primer struck).",
		},
		ammo_webley = {
			id = 134106576623387,
			category = "Weapons",
			folder = "Shared/Ammo",
			source = "assets/weapons/shared/ammo_webley.fbx",
			generator = "tools/blender/weapons/pistol_ammo.py",
			description = ".455 Webley Mk II round (the Webley Mk VI's): a short case with a wide rim and a lead round-nosed bullet (Case + Bullet, case head at the Origin, pointing -Z) and a fired Casing beside it (x +0.05).",
		},
		ammo_mauser = {
			id = 133218514196898,
			category = "Weapons",
			folder = "Shared/Ammo",
			source = "assets/weapons/shared/ammo_mauser.fbx",
			generator = "tools/blender/weapons/pistol_ammo.py",
			description = "7.63x25 Mauser round (the C96's): a rimless bottlenecked case with an extraction groove and a copper round-nosed bullet (Case + Bullet, case head at the Origin, pointing -Z) and a fired Casing beside it (x +0.05).",
		},
		-- the field gun's fixed round (2026-10-20, docs/MILESTONES.md A2): carried by the gunner while loading
		-- (Config/Artillery.Load), colored from Config/Palette.Artillery by mesh name
		round_qf18 = {
			id = 110166358677668,
			category = "Weapons",
			folder = "Shared/Artillery",
			source = "assets/weapons/shared/round_qf18.fbx",
			generator = "tools/blender/artillery/round_qf18.py",
			description = "QF 18-pounder HE round at real size (1.57 studs): the brass 84 x 292R case, a copper driving band, the yellow shell and a steel nose fuze (meshes Case, Band, Shell, Fuze). Origin at the case head, pointing -Z.",
		},
		-- the trench spade for digging and building (user 2026-10-19, design F), shared by every team, colored from
		-- Config/Palette.Shovel by mesh name. No mechanics yet.
		shovel = {
			-- v2: a plain iron tube instead of crossed straps, the foot treads the blade's own shoulders made thicker
			-- (v1 124738061416580)
			id = 86334126238475,
			category = "Weapons",
			folder = "Shared/Shovels",
			source = "assets/weapons/shared/shovel.fbx",
			generator = "tools/blender/weapons/shovel.py",
			description = "Tread spade, 3.5 studs, small two-handed: a wooden D-grip and haft, a brass collar, a plain iron tube, a tapered socket, a dished blade whose shoulders are thickened into foot treads, and a riveted tongue on its back (meshes Wood, Iron, Blade, Brass). Origin at the D-grip's bar, the blade toward -Z, the scoop's hollow toward +Y.",
		},
		-- a trench's dirt pieces (user 2026-10-23, trenches v2; tools/blender/trench/contact_sheet.py renders them all):
		-- built per square dug full by src/server/Trenches, colored from Config/Palette.Build by mesh name
		trench_pieces = {
			-- v4 (user 2026-10-24): walls at 59 degrees and a thick heap of dirt (Wall<i>Parapet) on each wall's top edge,
			-- the trench otherwise as v2 (v3 80264039854445 was another session's, dropped; v2 78446214415283); v5: the heaps
			-- lower and set back behind the wall's top, off its slabs and planks (v4 139463386134488); v6: the heaps a little
			-- closer to the wall's top (v5 107262926311515); v7: the heaps right on the wall's top and a Corner piece
			-- where a wall stops at a joining trench (v6 122327305436244); v8: a skirt of low dirt slabs past each heap,
			-- Wall<i>Apron (v7 82070975213659)
			id = 94215187575150,
			category = "Props",
			folder = "Trench",
			source = "assets/props/trench_pieces.fbx",
			generator = "tools/blender/trench/trench_pieces.py",
			fidelity = "Hull",
			description = "A trench square's dirt pieces, 8 studs long, in piece space (x along from the square's start, y up from the floor, z out of the trench, Origin at 0): walls Wall1-8 (a smooth base slab that collides, Wall<i>Chunks, low-poly earth slabs on it; Wall5-8 also Wall<i>Planks + Wall<i>PlanksDark, plank steps laid on its own bare stretch), floors Floor1-4 (+ Floor<i>Chunks, slabs across the trench).",
		},
		-- the sandbag pile (user 2026-10-27: pillow bags, two under one, "give it some firmth"): each bag its own mesh, so
		-- a pile is built a bag at a time; colored from Config/Palette.Build by mesh name. v2: stage 1, the scraped Patch
		-- and the empty Sacks ("a new stage 1, where no sandbags are placed"; v1 92308983969194)
		sandbag_pile = {
			id = 104301953084157,
			category = "Props",
			folder = "Sandbags",
			source = "assets/props/sandbag_pile.fbx",
			generator = "tools/blender/sandbags/pile.py",
			fidelity = "Hull",
			description = "A pile of three pillow sandbags in piece space (x along the pile, y up from the ground, z toward the defenders behind it, Origin at the foot's centre): Bag1 and Bag2 side by side on the ground (3.6 long, 1.6 deep, ties pointing outward), Bag3 centred on them, its underside settled into the joint; Bag<i>Cord the tie round each bag's neck; stage 1: Patch, the ground scraped flat under the pile (its top 0.05 up), and Sacks, three empty sacks folded at the +x end. 7.2 wide plus the ears, 3.68 high, the bottom row's top 1.96.",
		},
		-- the MG nest's mount bag (user 2026-10-27: "make the mount sandbag more circular and less long"): v2 with its
		-- Origin (v1 108497445715304 had none)
		sandbag_round = {
			id = 126056372875183,
			category = "Props",
			folder = "Sandbags",
			source = "assets/props/sandbag_round.fbx",
			generator = "tools/blender/mgnest/mg08.py",
			fidelity = "Hull",
			description = "The MG nest's mount bag: a short, nearly round pillow bag (Bag) lying along the gun, tied at the back (BagCord), its top sagging into a dent under the gun's foot plate. Gun space, Origin at the bag's foot under its middle; the dent's centre 0.2 in front of it (-z).",
		},
		hesco = {
			-- v3 (user round 5: "make another flat model for when it has just been placed": stage 0; approved "the flat
			-- just-placed look is right"); v2 132136802135276: 5.25 high ("just barely the players height"); v1
			-- 70847550749595 was 4 high, approved in Blender: "the inside looks right"
			id = 111641075459224,
			category = "Props",
			folder = "Build",
			source = "assets/props/hesco.fbx",
			generator = "tools/blender/hesco/hesco.py",
			fidelity = "Hull",
			description = "The Hesco barrier, 6 x 6 x 5.25 studs, in piece space (footprint centred on the Origin on the ground), one set of pieces per stage: stage 0 just laid at 0 HP (Scrape0 the scraped ground, Pack0 + Wire0 the unit lying folded flat), stages s = 1-4: Wire<s> (mesh, rim, corner coils), Liner<s> (slack liner above the dirt, stages 1-3), LinerFull<s> (liner under the dirt, stages 2-4), Earth<s>, Damp<s>, Clods<s>, Stones<s> (the dirt and what lies on it, stages 2-4), Flaps1 + Piles1 (stage 1). Only the Earth blocks: the wire and liner stop nothing (user 2026-10-27).",
		},
		-- a trench bridge's planks (user 2026-10-27; tools/blender/bridge/bridge_pieces.py renders them on the trench pieces):
		-- built by src/server/Build per bridge, colored from Config/Palette.Build by mesh name
		bridge_pieces = {
			-- v2: the deck boards laid on the stringers' tops (they floated), the sills and stringers straight and level
			-- (v1 121849607058281)
			id = 76835404637067,
			category = "Props",
			folder = "Bridge",
			source = "assets/props/bridge_pieces.fbx",
			generator = "tools/blender/bridge/bridge_pieces.py",
			fidelity = "Box",
			description = "A trench bridge's planks in piece space (origin on the square's centre line at ground level, x along the trench over one 8-stud square, z across it, y up; deck top 3.1, heap crest to crest 19.2; Origin at 0): variants Bridge1-6, each Bridge<v>Frame (+Dark: sills on the heaps, spliced stringers), Bridge<v>Boards (+Dark: stage 1's deck boards), Bridge<v>More (+Dark: the boards stage 2 adds). Every board modelled with grain grooves engraved on its face.",
		},
		-- the shovel's barbed wire (user 2026-10-27, tools/blender/wire/wire.py): laid by src/server/Build, one look shown
		-- at a time
		barbed_wire = {
			id = 106200729480297,
			category = "Props",
			folder = "Wire",
			source = "assets/props/barbed_wire.fbx",
			generator = "tools/blender/wire/wire.py",
			description = "A barbed wire section 8 long, 4 wide, 3.1 high, in piece space (x along, -4 to 4; y up from the ground; z across; Origin at 0), in three looks: standing (Pickets: two staggered rows of timber pickets; Strands: a strand along each row's tops and one low; Coil: one round concertina between the rows), stage 1 (BundlePickets stacked on the ground, BundleWire: the coil pushed shut beside them), broken (WreckPickets knocked flat or snapped, WreckWire: the coil crushed and torn in three, cut strands). Barbs are in their wire's mesh.",
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
		uniform3 = {
			category = "Teams",
			folder = "White/Uniform",
			uniform = "uniform3",
			source = "assets/teams/white/uniform/uniform3.json",
			generator = "tools/clothing/uniform.py",
			description = "The brown team's uniform (chocolate service tunic, puttees): Shirt + Pants images from "
				.. "Config/Uniforms.Kits.uniform3.",
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
		dressing_pad = {
			id = 101528084780164,
			category = "Teams",
			folder = "Shared/Bandages",
			source = "assets/teams/shared/bandages/dressing_pad.fbx",
			generator = "tools/blender/gear/bandages.py",
			description = "The med pack's dressing (mesh Cloth): a folded gauze pad with a short tail at each end, drawn out of the pack and pressed on (Config/Healing.Held.Pad).",
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
		-- Backpacks, one per team (user 2026-10-18/19; docs/CHARACTERS.md "Backpacks"): worn on the back of the Torso,
		-- each part placed at its offset from the export's Origin marker (the Torso center), keeping its imported
		-- rotation (src/server/Packs). Colored by mesh name from Config/Palette.Packs.
		pack_tornister = {
			id = 121478944791516, -- shorter, thicker roll clear of the stowed rifle and shovel (user 2026-10-20)
			category = "Teams",
			folder = "Grey/Packs",
			source = "assets/teams/grey/packs/pack_tornister.fbx",
			generator = "tools/blender/gear/pack.py",
			sling = 1.2, -- the flap's straps reach 1.68 (user 2026-10-19: the rifle rides over the pack)
			description = "German Tornister, the grey team's pack: a boxy canvas body under a hide flap with leather edge bands, "
				.. "two closure straps, a big blanket roll across the top against the back, shoulder bands (436-488 tris).",
		},
		pack_zaino = {
			id = 95650984386789, -- shorter, thicker roll (user 2026-10-20)
			category = "Teams",
			folder = "Olive/Packs",
			source = "assets/teams/olive/packs/pack_zaino.fbx",
			generator = "tools/blender/gear/pack.py",
			sling = 1.25, -- the bulging flap and straps reach 1.74 in the middle
			description = "Italian zaino M1907, the olive team's pack: a soft bulging canvas sack, a flap following the bulge, "
				.. "two side straps and a centre strap, a big blanket roll across the top, shoulder bands (660 tris).",
		},
		pack_p08 = {
			id = 119253478374701, -- shorter, thicker roll (user 2026-10-20)
			category = "Teams",
			folder = "White/Packs",
			source = "assets/teams/white/packs/pack_p08.fbx",
			generator = "tools/blender/gear/pack.py",
			sling = 1.1, -- the mess tin and its strap reach 1.59
			description = "British 1908 web large pack, the brown team's: a square web box, a flap two thirds down, two short "
				.. "straps, a mess tin on the flap, a big blanket roll across the top, shoulder bands (468 tris).",
		},
		helmet_stahl = {
			id = 98976523443657, -- reworked 2026-10-19 (docs/HATS.md "Rework")
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/default/helmet_stahl.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "Stahlhelm M1916, grey team (reworked 2026-10-19, traced from a side view): a round crown, tall "
				.. "straight walls, a long bell-shaped flare into the skirt and neck guard, rolled edge, gold side lugs; hollow, "
				.. "12 sides (544 tris). No national decal (fictional nations).",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27, -- the traced Stahlhelm: its back rim; the front rim sits 0.125 above the head centre (eyes show)
				parts = { Lugs = { 204, 172, 92 } },
				shell = "stahl",
				center = { 0, 0.672, -0.034 },
			},
		},
		helmet_stahl_goggles = {
			id = 96770262181573, -- reworked 2026-10-19 (docs/HATS.md "Rework")
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_goggles.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_stahl (unchanged) with a leather strap round the dome and big aviator goggles on "
				.. "the front; flat amber lenses. Grey team.",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27, -- the traced Stahlhelm: its back rim; the front rim sits 0.125 above the head centre (eyes show)
				parts = { Strap = { 46, 39, 34 }, Lens = { 222, 150, 52 }, Lugs = { 204, 172, 92 } },
				shell = "stahl",
				center = { 0, 0.672, -0.034 },
			},
		},
		helmet_stahl_ammo = {
			id = 139604548411760, -- reworked 2026-10-19 (docs/HATS.md "Rework")
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_ammo.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_stahl (unchanged) with a leather band low round the dome and five red shotgun "
				.. "shells on gold heads on the wearer's right, held by a thin flat strap. Grey team.",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27, -- the traced Stahlhelm: its back rim; the front rim sits 0.125 above the head centre (eyes show)
				parts = {
					Band = { 46, 39, 34 },
					Hull = { 150, 54, 44 },
					Brass = { 204, 172, 92 },
					Lugs = { 204, 172, 92 },
				},
				shell = "stahl",
				center = { 0, 0.672, -0.034 },
			},
		},
		helmet_stahl_katzling = {
			id = 88658020114991, -- 2026-10-25, holes for the rooted reference ears; v1 139562349895399 (2026-10-20)
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_katzling.fbx",
			generator = "tools/blender/gear/slit.py",
			description = "The default helmet_stahl (unchanged) with an oval hole each side of the crown, cut round the "
				.. "Katzling ears' shell and fur blades (--tufts), a rolled steel ring round each (user 2026-10-20/25). "
				.. "Worn by Katzlings (Rules/Looks.helmetEntry). Grey team (1130 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27, -- the traced Stahlhelm: its back rim; the front rim sits 0.125 above the head centre (eyes show)
				parts = { Lugs = { 204, 172, 92 } },
				shell = "stahl",
				center = { 0, 0.6835, -0.034 }, -- the rings sit on the dome's sides: the box is the default's
			},
		},
		helmet_m33_goggles = {
			id = 136907445966779, -- narrowed M33 (2026-10-20; docs/HATS.md "New helmets")
			category = "Teams",
			folder = "Olive/Helmets",
			source = "assets/teams/olive/helmets/variants/helmet_m33_goggles.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_m33 (unchanged) with a leather strap round the dome and big aviator goggles on "
				.. "the front; flat blue lenses. Olive team.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.13, -- raised 0.05 so the eyes show (user 2026-10-13; was -0.18)
				parts = { Strap = { 106, 72, 46 }, Lens = { 86, 150, 214 }, Lugs = { 176, 146, 80 } },
				shell = "m33",
				center = { 0, 0.5397, 0 },
			},
		},
		helmet_m33_ammo = {
			id = 125728031453524, -- narrowed M33 (2026-10-20; docs/HATS.md "New helmets")
			category = "Teams",
			folder = "Olive/Helmets",
			source = "assets/teams/olive/helmets/variants/helmet_m33_ammo.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_m33 (unchanged) with a leather band low round the dome and five red shotgun "
				.. "shells on brass heads on the wearer's right, held by a thin flat strap. Olive team.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.13, -- raised 0.05 so the eyes show (user 2026-10-13; was -0.18)
				parts = {
					Band = { 106, 72, 46 },
					Hull = { 150, 54, 44 },
					Brass = { 176, 146, 80 },
					Lugs = { 176, 146, 80 },
				},
				shell = "m33",
				center = { 0, 0.5397, 0 },
			},
		},
		helmet_m33 = {
			id = 97355249592293, -- narrowed M33 (2026-10-20; docs/HATS.md "New helmets")
			category = "Teams",
			folder = "Olive/Helmets",
			source = "assets/teams/olive/helmets/default/helmet_m33.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "M33, olive team (reworked 2026-10-19): the approved pre-rework shape (rounded dome worn low, rim "
				.. "raised at the front, arched over the ears, lower at the back) with a rolled lip and a rib above it, "
				.. "a brass vent rivet each side, narrowed side to side (oval 0.86, user 2026-10-20); hollow, 12 sides (448 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.13, -- raised 0.05 so the eyes show (user 2026-10-13; was -0.18)
				parts = { Lugs = { 176, 146, 80 } },
				shell = "m33",
				center = { 0, 0.5397, 0 },
			},
		},
		helmet_brodie = {
			id = 104280433784436, -- reworked 2026-10-19 (docs/HATS.md "Rework")
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/default/helmet_brodie.fbx",
			generator = "tools/blender/gear/helmet.py",
			description = "Brodie Mk I, the brown team's default (reworked 2026-10-19): a "
				.. "rounded bowl, a wide brim sloping to a rolled lip, oval front to back, a crown rivet, worn tipped "
				.. "back 8 degrees; hollow, 10 sides (280 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 }, -- chocolate, as the brown uniform (user 2026-10-21)
				brim = 0.06,
				shell = "brodie",
				center = { 0, 0.3781, 0.0023 },
			},
		},
		helmet_brodie_goggles = {
			id = 73432666409046, -- reworked 2026-10-19 (docs/HATS.md "Rework")
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/variants/helmet_brodie_goggles.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_brodie (unchanged) with a leather strap round the dome and big aviator goggles on "
				.. "the front; flat teal lenses. Brown team.",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 }, -- chocolate, as the brown uniform (user 2026-10-21)
				brim = 0.06,
				parts = { Strap = { 58, 40, 28 }, Lens = { 72, 176, 150 } }, -- dark leather on the chocolate (user 2026-10-21)
				shell = "brodie",
				center = { 0, 0.3781, 0.0023 },
			},
		},
		helmet_brodie_ammo = {
			id = 78603559603166, -- reworked 2026-10-19 (docs/HATS.md "Rework")
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/variants/helmet_brodie_ammo.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_brodie (unchanged) with a leather band low round the dome and five red shotgun "
				.. "shells on steel heads on the wearer's right, held by a thin flat strap. Brown team.",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 }, -- chocolate, as the brown uniform (user 2026-10-21)
				brim = 0.06,
				parts = { Band = { 58, 40, 28 }, Hull = { 150, 54, 44 }, Brass = { 168, 170, 174 } }, -- dark leather band
				shell = "brodie",
				center = { 0, 0.3781, 0.0023 },
			},
		},
		helmet_brodie_fennek = {
			id = 108652845162963, -- 2026-10-25, holes for the rooted reference ears; v1 105223519655559 (2026-10-21)
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/variants/helmet_brodie_fennek.fbx",
			generator = "tools/blender/gear/slit.py",
			description = "The default helmet_brodie (unchanged) with a hole each side of the crown cut to the Fennek ears' "
				.. "outline, shell and fur blades (--shape hull --tufts), a rolled steel ring round each (user "
				.. "2026-10-21/25). Worn by Fennek (Rules/Looks.helmetEntry). Brown team (848 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 }, -- the brown team's chocolate (white-team branch)
				brim = 0.06,
				shell = "brodie",
				center = { 0, 0.3902, 0.0023 }, -- the rings sit on the dome's sides: the box is the default's
			},
		},
		-- New helmets (user 2026-10-20: one more per team, "different helmet, different armoring"; docs/HATS.md "New helmets")
		helmet_stahl_plate = {
			id = 132394662760568,
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_plate.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_stahl (unchanged) with a heavy brow plate hung on its lugs, arched over the "
				.. "forehead, in a darker grey. Grey team.",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27, -- the traced Stahlhelm: its back rim; the front rim sits 0.125 above the head centre (eyes show)
				parts = { Plate = { 58, 60, 64 }, Lugs = { 204, 172, 92 } },
				shell = "stahl",
				center = { 0, 0.672, -0.034 },
			},
		},
		helmet_m33_plate = {
			id = 71968134222975,
			category = "Teams",
			folder = "Olive/Helmets",
			source = "assets/teams/olive/helmets/variants/helmet_m33_plate.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "The default helmet_m33 (unchanged) with a slim brow plate bolted across the front, in a darker "
				.. "olive, two brass bolts. Olive team.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = -0.13,
				parts = { Plate = { 90, 90, 56 }, Bolts = { 176, 146, 80 }, Lugs = { 176, 146, 80 } },
				shell = "m33",
				center = { 0, 0.5397, 0 },
			},
		},
		helmet_adrian_visor = {
			id = 139258592514715, -- front raised 0.1 (2026-10-20: the peak covered half the eyes)
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/variants/helmet_adrian_visor.fbx",
			generator = "tools/blender/gear/accessory.py",
			description = "Adrian M1915, the brown team's second helmet (base: assets/teams/white/helmets/default/helmet_adrian.fbx, "
				.. "helmet.py): a rounded bowl with a crest, a bead and sloping front and back peaks; a three-slat bronze "
				.. "visor hinged up against the bowl, so the face shows. Hollow, 848 tris. Brown team (colours a proposal).",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 }, -- chocolate, as the brown uniform (user 2026-10-21)
				brim = -0.02, -- the front peak sits 0.21 above the head centre (eyes show)
				parts = { Visor = { 176, 116, 58 } }, -- bronze (user 2026-10-27: "the brown plates should also be bronze")
				shell = "adrian",
				center = { 0, 0.616, 0.0118 },
			},
		},
		-- the class helmets with ear holes (user 2026-10-27: Rifleman plate, Mage goggles; slit.py --base)
		helmet_stahl_plate_katzling = {
			id = 98538430075934, -- 2026-10-27
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_plate_katzling.fbx",
			generator = "tools/blender/gear/slit.py",
			description = "helmet_stahl_plate (unchanged) with the Katzling ear holes and rolled rings of helmet_stahl_katzling "
				.. "(--tufts --base helmet_stahl_plate). Worn by Katzlings (Rules/Looks.helmetEntry). Grey team (1210 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27, -- the traced Stahlhelm: its back rim; the front rim sits 0.125 above the head centre (eyes show)
				parts = { Plate = { 58, 60, 64 }, Lugs = { 204, 172, 92 } },
				shell = "stahl",
				center = { 0, 0.6834, -0.034 },
			},
		},
		helmet_stahl_goggles_katzling = {
			id = 102146492317293, -- 2026-10-27
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_goggles_katzling.fbx",
			generator = "tools/blender/gear/slit.py",
			description = "helmet_stahl_goggles (unchanged) with the Katzling ear holes and rolled rings of helmet_stahl_katzling "
				.. "(--tufts --base helmet_stahl_goggles). Worn by Katzlings (Rules/Looks.helmetEntry). Grey team (1350 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27, -- the traced Stahlhelm: its back rim; the front rim sits 0.125 above the head centre (eyes show)
				parts = { Strap = { 46, 39, 34 }, Lens = { 222, 150, 52 }, Lugs = { 204, 172, 92 } },
				shell = "stahl",
				center = { 0, 0.6834, -0.034 },
			},
		},
		helmet_adrian_visor_fennek = {
			id = 124778702224786, -- 2026-10-27
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/variants/helmet_adrian_visor_fennek.fbx",
			generator = "tools/blender/gear/slit.py",
			description = "helmet_adrian_visor (unchanged) with the Fennek ear holes and rolled rings of helmet_brodie_fennek "
				.. "(--shape hull --tufts --base helmet_adrian_visor). Worn by Fenneks (Rules/Looks.helmetEntry). Brown team (1444 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 }, -- chocolate, as the white uniform (user 2026-10-21)
				brim = -0.02, -- the front peak sits 0.21 above the head centre (eyes show)
				parts = { Visor = { 176, 116, 58 } }, -- bronze (user 2026-10-27: "the brown plates should also be bronze")
				shell = "adrian",
				center = { 0, 0.616, 0.0118 },
			},
		},
		-- Engineer caps (user 2026-10-27, docs/HATS.md "Engineer caps"): soft cloth, NOT bulletproof (fit.soft: a hit on
		-- one is a full Head hit and knocks it off, src/server/Helmets.soft); worn over their own shaved hairs
		-- (`hair_<style>_<shell>`). Config/Classes.Gear engineerCap.
		cap_feld = {
			id = 120060802340742,
			category = "Teams",
			folder = "Grey/Hats",
			source = "assets/teams/grey/hats/cap_feld.fbx",
			generator = "tools/blender/gear/caps/cap.py",
			description = "The grey team's soft field cap (Engineer): a rolled lip, a darker band with a gold cog pin, a seam rib, a soft crown bulging past the band and slumping forward, off-white piping round it; tipped back 4 degrees, level side to side (the Katzling's ears). Not bulletproof (fit.soft); 5% bigger than first made, so the hair underneath has room (user 2026-10-27). 756 tris.",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = 0.12,
				parts = { Band = { 58, 60, 64 }, Piping = { 212, 210, 198 }, Pin = { 204, 172, 92 } },
				shell = "feld",
				center = { 0, 0.3416, 0.015 },
				soft = true,
			},
		},
		cap_feld_katzling = {
			id = 100126078130512,
			category = "Teams",
			folder = "Grey/Hats",
			source = "assets/teams/grey/hats/cap_feld_katzling.fbx",
			generator = "tools/blender/gear/caps/slit_caps.py",
			description = "cap_feld (unchanged) with a snug hole each side of the crown round the Katzling ear's fur, wider in front for its fluff, and a sleeve of the cap's cloth rising round each ear with a floor inside, a stitched hem on its lip in the band's darker grey (user 2026-10-27: the ears floated over wide holes). Worn by Katzlings (Rules/Looks.helmetEntry). 1452 tris.",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = 0.12,
				parts = {
					Band = { 58, 60, 64 },
					Piping = { 212, 210, 198 },
					Pin = { 204, 172, 92 },
					Hem = { 58, 60, 64 },
				},
				shell = "feld",
				center = { 0, 0.3699, 0.015 },
				soft = true,
			},
		},
		cap_side = {
			id = 126107118086539,
			category = "Teams",
			folder = "Olive/Hats",
			source = "assets/teams/olive/hats/cap_side.fbx",
			generator = "tools/blender/gear/caps/cap.py",
			description = "The olive team's folded side cap (Engineer): boat-shaped, the sides leaning in to a ridge, the front and back peaked, the turned-up curtain's darker edge, a brass cog pin and stud; canted 10 degrees to the wearer's right. Not bulletproof (fit.soft); 5% bigger than first made, so the hair underneath has room (user 2026-10-27). 708 tris.",
			fit = {
				attachment = "HatAttachment",
				color = { 116, 114, 72 },
				brim = 0.48,
				parts = { Edge = { 90, 90, 56 }, Pin = { 176, 146, 80 } },
				shell = "side",
				center = { 0.0027, 0.2637, -0.0074 },
				soft = true,
				bald = 0.3, -- 0.18 down to the crown: bald, it floated on its curtain's edge (user 2026-10-28)
			},
		},
		cap_trench = {
			id = 136890475919507,
			category = "Teams",
			folder = "White/Hats",
			source = "assets/teams/white/hats/cap_trench.fbx",
			generator = "tools/blender/gear/caps/cap.py",
			description = "The brown team's floppy trench cap (Engineer): a band, a soft crown ballooning out and sagging at the sides, pushed back 7 degrees, a short drooping dark peak, the ear flaps folded up with buttons, an off-white cord, a brass cog pin. Not bulletproof (fit.soft); 5% bigger than first made, so the hair underneath has room (user 2026-10-27). 844 tris.",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 },
				brim = 0.18,
				parts = {
					Peak = { 74, 48, 28 },
					Flaps = { 86, 62, 44 },
					Cord = { 212, 210, 198 },
					Pin = { 176, 146, 80 },
				},
				shell = "trench",
				center = { 0, 0.2973, 0.0679 },
				soft = true,
			},
		},
		cap_trench_fennek = {
			id = 107932948432860,
			category = "Teams",
			folder = "White/Hats",
			source = "assets/teams/white/hats/cap_trench_fennek.fbx",
			generator = "tools/blender/gear/caps/slit_caps.py",
			description = "cap_trench (unchanged) with a snug hole each side of the crown round the Fennek ear's fur, wider in front for its fluff, and a sleeve of the cap's cloth rising round each ear with a floor inside, a stitched hem on its lip in the peak's dark brown (user 2026-10-27: the ears floated over wide holes). Worn by Fennek (Rules/Looks.helmetEntry). 1542 tris.",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 },
				brim = 0.18,
				parts = {
					Peak = { 74, 48, 28 },
					Flaps = { 86, 62, 44 },
					Cord = { 212, 210, 198 },
					Pin = { 176, 146, 80 },
					Hem = { 74, 48, 28 },
				},
				shell = "trench",
				center = { 0, 0.3289, 0.0679 },
				soft = true,
			},
		},
		helmet_brodie_goggles_fennek = {
			id = 81298979861398, -- 2026-10-27
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/variants/helmet_brodie_goggles_fennek.fbx",
			generator = "tools/blender/gear/slit.py",
			description = "helmet_brodie_goggles (unchanged) with the Fennek ear holes and rolled rings of helmet_brodie_fennek "
				.. "(--shape hull --tufts --base helmet_brodie_goggles). Worn by Fenneks (Rules/Looks.helmetEntry). Brown team (1056 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 }, -- chocolate, as the white uniform (user 2026-10-21)
				brim = 0.06,
				parts = { Strap = { 58, 40, 28 }, Lens = { 72, 176, 150 } }, -- dark leather on the chocolate (user 2026-10-21)
				shell = "brodie",
				center = { 0, 0.3902, 0.0023 },
			},
		},
		-- the Shotgunner's shell-band helmets with ear holes (user 2026-10-27; slit.py --base)
		helmet_stahl_ammo_katzling = {
			id = 106412495316107, -- 2026-10-27
			category = "Teams",
			folder = "Grey/Helmets",
			source = "assets/teams/grey/helmets/variants/helmet_stahl_ammo_katzling.fbx",
			generator = "tools/blender/gear/slit.py",
			description = "helmet_stahl_ammo (unchanged) with the Katzling ear holes and rolled rings of helmet_stahl_katzling "
				.. "(--tufts --base helmet_stahl_ammo). Worn by Katzlings (Rules/Looks.helmetEntry). Grey team (1958 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 80, 82, 86 },
				brim = -0.27, -- the traced Stahlhelm: its back rim; the front rim sits 0.125 above the head centre (eyes show)
				parts = {
					Band = { 46, 39, 34 },
					Hull = { 150, 54, 44 },
					Brass = { 204, 172, 92 },
					Lugs = { 204, 172, 92 },
				},
				shell = "stahl",
				center = { 0, 0.6834, -0.034 },
			},
		},
		helmet_brodie_ammo_fennek = {
			id = 119000847226618, -- 2026-10-27
			category = "Teams",
			folder = "White/Helmets",
			source = "assets/teams/white/helmets/variants/helmet_brodie_ammo_fennek.fbx",
			generator = "tools/blender/gear/slit.py",
			description = "helmet_brodie_ammo (unchanged) with the Fennek ear holes and rolled rings of helmet_brodie_fennek, "
				.. "the holes 0.15 longer at the front for the low tufts (--shape hull --tufts --front 0.15 --base "
				.. "helmet_brodie_ammo; user 2026-10-27). Worn by Fenneks (Rules/Looks.helmetEntry). White team (1668 tris).",
			fit = {
				attachment = "HatAttachment",
				color = { 96, 70, 50 }, -- chocolate, as the brown uniform (user 2026-10-21)
				brim = 0.06,
				parts = { Band = { 58, 40, 28 }, Hull = { 150, 54, 44 }, Brass = { 168, 170, 174 } }, -- dark leather band
				shell = "brodie",
				center = { 0, 0.3901, 0.0023 },
			},
		},
		-- Species ears and tails (Config/Species, src/server/Species; user 2026-10-18/20): one piece per mesh, named
		-- `<Piece>_<role>` (the role picks its colour: Rules/Species.color). Ears are head-local (the Origin marker is
		-- the head's center), tails Torso-local (the Torso's center).
		ears_katzling = {
			id = 111195693660590, -- v6 2026-10-25; v3 115041129787289, v2 105362765217637, v1 131909248233922
			category = "Teams",
			folder = "Shared/Species",
			source = "assets/teams/shared/species/ears_katzling.fbx",
			generator = "tools/blender/gear/ears_ref.py",
			description = "Katzling cat ears from the user's reference hair (shell and fur blades of catalog "
				.. "116579723315238, scaled 1.2 / 1.6 deep / 1.25 tall, its root sunk into the head): an open shell in the "
				.. "hair colour, a fan of pink and cream blades inside (user 2026-10-25; 1180 tris).",
		},
		ears_fennek = {
			id = 133114690983265, -- v5 2026-10-25; v2 135952144124699, v1 96521357487348 (named pieces clashed)
			category = "Teams",
			folder = "Shared/Species",
			source = "assets/teams/shared/species/ears_fennek.fbx",
			generator = "tools/blender/gear/ears_ref.py",
			description = "Fennek fennec ears: the Katzling's reference ear (catalog 116579723315238) taller and "
				.. "narrower (1.0 / 1.8 deep / 1.6 tall, its root sunk into the head): an open shell in the hair colour, a fan of pink and "
				.. "cream blades inside (user 2026-10-25; 1180 tris).",
		},
		ears_alb = {
			id = 99118164513786, -- v1 96073907474669 (named pieces clashed)
			category = "Teams",
			folder = "Shared/Species",
			source = "assets/teams/shared/species/ears_alb.fbx",
			generator = "tools/blender/gear/species.py",
			description = "Alb elf ears: long skin-coloured blades out of the head's sides, pointing down and back under "
				.. "the helmet rim (92 tris).",
		},
		tail_katzling = {
			id = 78500799352387, -- v1 93930987857958 (ringed segments)
			category = "Teams",
			folder = "Shared/Species",
			source = "assets/teams/shared/species/tail_katzling.fbx",
			generator = "tools/blender/gear/species.py",
			description = "Katzling cat tail: one smooth tapered mesh hanging behind the legs, curling up at the end in a J, "
				.. "skinned to 5 bones Tail1-5 (concept A; 2.15 long).",
		},
		tail_fennek = {
			id = 110025158183885, -- v1 89946798239053 (ringed segments)
			category = "Teams",
			folder = "Shared/Species",
			source = "assets/teams/shared/species/tail_fennek.fbx",
			generator = "tools/blender/gear/species.py",
			description = "Fennek fennec tail: one long bushy brush, wolf-shaped, hanging down and back and curving up, a dark "
				.. "tip mesh, skinned to 5 bones Tail1-5 (2.3 long, 376 tris).",
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
		-- Rigged hairs (2026-10-20: refit over the R6 collar, tools/hair/neck_fit.py; skinned to sway,
		-- tools/hair/rig_hair.py) are placed by their Origin marker instead and give `hair.bones`.
		hair_wolf_cut = {
			id = 113256526579133, -- refit for R6 and rigged (2026-10-20)
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/refit/hair_wolf_cut.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair wolf_cut, original refit for R6 (tools/hair/neck_fit.py), rigged to sway (3998 tris). From 18320597179 'Black Stylish Layered Wolf Cut Short Hair' (AvaSky).",
			hair = { bones = 4 },
		},
		hair_wolf_cut_m33 = {
			id = 123448780807622, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/refit/under/hair_wolf_cut_m33.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair wolf_cut under the m33 helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (4120 tris).",
			hair = { bones = 4 },
		},
		hair_wolf_cut_stahl = {
			id = 126575598777569, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/refit/under/hair_wolf_cut_stahl.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair wolf_cut under the stahl helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (4041 tris).",
			hair = { bones = 4 },
		},
		hair_wolf_cut_brodie = {
			id = 105749681226529, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/refit/under/hair_wolf_cut_brodie.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair wolf_cut under the brodie helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (4081 tris).",
			hair = { bones = 4 },
		},
		hair_wolf_cut_adrian = {
			id = 123251126579214, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/refit/under/hair_wolf_cut_adrian.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair wolf_cut under the adrian helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (4128 tris).",
			hair = { bones = 4 },
		},
		hair_low_ponytail = {
			id = 110950679249754, -- refit for R6, rigged, its tip tucked into the pack (2026-10-20)
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/refit/hair_low_ponytail.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair low_ponytail, original refit for R6 (tools/hair/neck_fit.py), rigged to sway (3132 tris). From 14401441197 'Low Ponytail (Black)' (YOU LOVE HAIR).",
			hair = { bones = 6 },
		},
		hair_low_ponytail_m33 = {
			id = 84344600264282, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/refit/under/hair_low_ponytail_m33.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair low_ponytail under the m33 helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (3131 tris).",
			hair = { bones = 6 },
		},
		hair_low_ponytail_stahl = {
			id = 90405510880679, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/refit/under/hair_low_ponytail_stahl.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair low_ponytail under the stahl helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (3131 tris).",
			hair = { bones = 6 },
		},
		hair_low_ponytail_brodie = {
			id = 121945792439071, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/refit/under/hair_low_ponytail_brodie.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair low_ponytail under the brodie helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (3128 tris).",
			hair = { bones = 6 },
		},
		hair_low_ponytail_adrian = {
			id = 138177862745285, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/refit/under/hair_low_ponytail_adrian.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair low_ponytail under the adrian helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (3120 tris).",
			hair = { bones = 6 },
		},
		hair_m_wolf = {
			id = 128481240440323, -- refit for R6 and rigged (2026-10-20)
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/refit/hair_m_wolf.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_wolf, original refit for R6 (tools/hair/neck_fit.py), rigged to sway (3997 tris). From 96306223630485 'Really Messy Emo Wolf Cut Boy Hair' (kwarm).",
			hair = { bones = 4 },
		},
		hair_m_wolf_m33 = {
			id = 130290503905273, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/refit/under/hair_m_wolf_m33.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_wolf under the m33 helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (4029 tris).",
			hair = { bones = 4 },
		},
		hair_m_wolf_stahl = {
			id = 77828511561744, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/refit/under/hair_m_wolf_stahl.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_wolf under the stahl helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (4006 tris).",
			hair = { bones = 4 },
		},
		hair_m_wolf_brodie = {
			id = 129064284848538, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/refit/under/hair_m_wolf_brodie.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_wolf under the brodie helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (4052 tris).",
			hair = { bones = 4 },
		},
		hair_m_wolf_adrian = {
			id = 73310907494805, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/refit/under/hair_m_wolf_adrian.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_wolf under the adrian helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (4050 tris).",
			hair = { bones = 4 },
		},
		hair_m_slick = {
			id = 101462156176326, -- refit for R6 and rigged (2026-10-20)
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/refit/hair_m_slick.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_slick, original refit for R6 (tools/hair/neck_fit.py), rigged to sway (2963 tris). From 137919482126630 'Beautiful Swoop Hair Male' (Crooner).",
			hair = { bones = 1 },
		},
		hair_m_slick_m33 = {
			id = 134547063480081, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/refit/under/hair_m_slick_m33.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_slick under the m33 helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (2963 tris).",
			hair = { bones = 1 },
		},
		hair_m_slick_stahl = {
			id = 113448809911258, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/refit/under/hair_m_slick_stahl.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_slick under the stahl helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (2963 tris).",
			hair = { bones = 1 },
		},
		hair_m_slick_brodie = {
			id = 134275329770818, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/refit/under/hair_m_slick_brodie.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_slick under the brodie helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (2963 tris).",
			hair = { bones = 1 },
		},
		hair_m_slick_adrian = {
			id = 80420827998687, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/refit/under/hair_m_slick_adrian.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_slick under the adrian helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (2958 tris).",
			hair = { bones = 1 },
		},
		hair_m_midpart = {
			id = 90190575335651, -- refit for R6 and rigged (2026-10-20)
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/refit/hair_m_midpart.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_midpart, original refit for R6 (tools/hair/neck_fit.py), rigged to sway (3615 tris). From 98001154915857 'Light Brown Sleek Male Hair' (platan).",
			hair = { bones = 2 },
		},
		hair_m_midpart_m33 = {
			id = 101953247018810, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/refit/under/hair_m_midpart_m33.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_midpart under the m33 helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (3641 tris).",
			hair = { bones = 2 },
		},
		hair_m_midpart_stahl = {
			id = 75942769614215, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/refit/under/hair_m_midpart_stahl.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_midpart under the stahl helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (3615 tris).",
			hair = { bones = 2 },
		},
		hair_m_midpart_brodie = {
			id = 88318588737841, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/refit/under/hair_m_midpart_brodie.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_midpart under the brodie helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (3649 tris).",
			hair = { bones = 2 },
		},
		hair_m_midpart_adrian = {
			id = 87287081645234, -- tucked under the shell, nothing below the rim lost (2026-10-24)
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/refit/under/hair_m_midpart_adrian.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_midpart under the adrian helmet: the R6 refit tucked in under the shell (tools/blender/gear/hair_tuck.py), then shaved where it still pokes through (hair_under.py), rigged to sway (3683 tris).",
			hair = { bones = 2 },
		},
		hair_wolf_cut_feld = {
			id = 102731799104607,
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/refit/under/hair_wolf_cut_feld.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair wolf_cut under the feld cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 4 },
		},
		hair_wolf_cut_side = {
			id = 98327207559386,
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/refit/under/hair_wolf_cut_side.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair wolf_cut under the side cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 4 },
		},
		hair_wolf_cut_trench = {
			id = 76197133549406,
			category = "Characters",
			folder = "Hairs/wolf_cut",
			source = "assets/characters/hairs/wolf_cut/refit/under/hair_wolf_cut_trench.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair wolf_cut under the trench cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway. Tucked, pinched and shaved 0.045 inside the cap, not 0.015, so it stays under the cap's front in game (user 2026-10-28: it poked out at the front).",
			hair = { bones = 4 },
		},
		hair_low_ponytail_feld = {
			id = 100462190662821,
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/refit/under/hair_low_ponytail_feld.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair low_ponytail under the feld cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 6 },
		},
		hair_low_ponytail_side = {
			id = 83475732772616,
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/refit/under/hair_low_ponytail_side.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair low_ponytail under the side cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 6 },
		},
		hair_low_ponytail_trench = {
			id = 83646441365503,
			category = "Characters",
			folder = "Hairs/low_ponytail",
			source = "assets/characters/hairs/low_ponytail/refit/under/hair_low_ponytail_trench.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair low_ponytail under the trench cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway. Tucked, pinched and shaved 0.045 inside the cap, not 0.015, so it stays under the cap's front in game (user 2026-10-28: it poked out at the front).",
			hair = { bones = 6 },
		},
		hair_m_wolf_feld = {
			id = 111682984993847,
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/refit/under/hair_m_wolf_feld.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_wolf under the feld cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 4 },
		},
		hair_m_wolf_side = {
			id = 89851885713926,
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/refit/under/hair_m_wolf_side.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_wolf under the side cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 4 },
		},
		hair_m_wolf_trench = {
			id = 112017722009700,
			category = "Characters",
			folder = "Hairs/m_wolf",
			source = "assets/characters/hairs/m_wolf/refit/under/hair_m_wolf_trench.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_wolf under the trench cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway. Tucked, pinched and shaved 0.045 inside the cap, not 0.015, so it stays under the cap's front in game (user 2026-10-28: it poked out at the front).",
			hair = { bones = 4 },
		},
		hair_m_slick_feld = {
			id = 83093642914741,
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/refit/under/hair_m_slick_feld.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_slick under the feld cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 1 },
		},
		hair_m_slick_side = {
			id = 117149990819174,
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/refit/under/hair_m_slick_side.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_slick under the side cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 1 },
		},
		hair_m_slick_trench = {
			id = 76709398435810,
			category = "Characters",
			folder = "Hairs/m_slick",
			source = "assets/characters/hairs/m_slick/refit/under/hair_m_slick_trench.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_slick under the trench cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway. Tucked, pinched and shaved 0.045 inside the cap, not 0.015, so it stays under the cap's front in game (user 2026-10-28: it poked out at the front).",
			hair = { bones = 1 },
		},
		hair_m_midpart_feld = {
			id = 111512238255742,
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/refit/under/hair_m_midpart_feld.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_midpart under the feld cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 2 },
		},
		hair_m_midpart_side = {
			id = 110520556654760,
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/refit/under/hair_m_midpart_side.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_midpart under the side cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway.",
			hair = { bones = 2 },
		},
		hair_m_midpart_trench = {
			id = 114120397129545,
			category = "Characters",
			folder = "Hairs/m_midpart",
			source = "assets/characters/hairs/m_midpart/refit/under/hair_m_midpart_trench.fbx",
			generator = "tools/hair/rig_hair.py",
			description = "Hair m_midpart under the trench cap (Engineer): the R6 refit tucked in under the cap (hair_tuck) and pinched in under the band so it comes out from under the cap (hair_pinch_caps), then shaved where it still pokes through (hair_under; the caps' copies keep the crown's overhang as skin, tools/blender/gear/caps/), then finished (faces through any cap part or left over the band deleted, every face backed so it shows from behind, a sheet of hair on the head under the band filling the gaps the cap's crown left between the strands: tools/blender/gear/caps/hair_finish_caps.py), rigged to sway. Tucked, pinched and shaved 0.045 inside the cap, not 0.015, so it stays under the cap's front in game (user 2026-10-28: it poked out at the front).",
			hair = { bones = 2 },
		},
	} :: { [string]: Entry },

	-- Tree placement: height in studs (trunk base to canopy top) at scale 1.
	TreeTargetHeight = { Pine = 40, Broadleaf = 30, Birch = 27 },
}

return table.freeze(Assets)
