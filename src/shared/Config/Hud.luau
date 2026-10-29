--!strict
-- The combat HUD, "quartermaster's brass" (user 2026-10-26: "make a unique UI that reflects that the weapons reload
-- sequence is like ... use actual parts from the weapon"; "show the chamber, the shell empty if fired, an animation of
-- the chamber / bolt moving and have the magazine box be the actual magazine (semi transparent showing ammo and show
-- ammo going up)"). Brass-rimmed panels, each with a cut-away of the real thing drawn live in a ViewportFrame:
-- - guns (src/client/AmmoHud): a three-quarter cut-away of the action, the gun a flat shadow, the bolt, the rounds
--   (the shared round Config/Assets ammo_rifle, a pistol's own cartridge) and the magazine well clear;
-- - the staff (src/client/StaffHud): a magic rock in the team's colour, faded when empty, bright when full,
--   flickering while it can't be used (burnt out by a stage 3 shot);
-- - artillery (src/client/ArtilleryHud): the field gun's breech cut away with its round, the howitzer's crystal.
-- Layout (reference pixels) in src/shared/ui/CombatHud.json; colours in Config/Palette.UI.Hud. Data only.

local Hud = {
	-- the shared round's library model (Config/Assets ammo_rifle: Case + Bullet, the spent Casing, Origin at the head)
	Round = { "Weapons", "Shared", "Ammo", "ammo_rifle" },
	-- a weapon's own round in place of it (the pistols' cartridges, Config/Assets ammo_*: the same parts)
	Rounds = {
		pistol_nagant = { "Weapons", "Shared", "Ammo", "ammo_nagant" },
		pistol_webley = { "Weapons", "Shared", "Ammo", "ammo_webley" },
		pistol_c96 = { "Weapons", "Shared", "Ammo", "ammo_mauser" },
	} :: { [string]: { string } },

	-- the cut-aways' light (the ViewportFrames: a direction; its colours in Palette.UI.Hud viewAmbient / viewLight)
	Light = { -0.4, -1, -0.6 },

	-- the hit note (src/client/Firing): what a shot hit and how far, over the screen centre
	HitNote = { textSize = 16, stroke = 0.5, y = -40, size = { 300, 20 } },

	Gun = {
		-- the cut-away seen three-quarters on (user 2026-10-26: "make it 3d and off angle", from a cut-away of a Mauser
		-- action): toward the camera in gun space (+X the gun's right, +Y up, +Z its rear), the lens, the share of the
		-- framed box added round it
		from = { 1, 0.35, 0.4 },
		fov = 24,
		margin = 0.08,
		-- the framed box round the action (round lengths `ahead` of the chamber; round widths for the rest): above the
		-- bore, below the magazine well, to each side of the bore, behind the bolt's rear fully back
		frame = { ahead = 1.4, above = 1.6, below = 0.3, side = 2, behind = 1 },
		-- everything but the bolt, the rounds and the magazine well is one flat shadow (user 2026-10-26: "make
		-- everything else just a simple shadow sillouette"): the gun's own parts in Palette.UI.Hud.shadow under the
		-- clear layer, `see` see-through, fading out over `fade` of the view's width at each end; not the `clear` parts
		-- (nor a pump gun's feed parts)
		shadow = { see = 0.45, fade = 0.2 },
		clear = { "Gun", "Bolt", "Rounds", "Bullets", "Casing", "HeldRounds", "Origin", "Bore" },
		-- the bolt, a simple 3D piece (round widths): a round body from its face to `body` of the way to the gun's
		-- bolt's rear, `radius` round; a ring of lugs at the face; the cocking piece behind, `cock` of the body's
		-- width; its handle a rod (`stem` wide) out to the gun's own knob (Config/Weapons reload.knob, drawn when it
		-- sits more than `side` modelled studs off the bore: not the Winchester's plunger) with a ball `knob` wide on it,
		-- moving exactly as the gun's bolt does (turned, slid back)
		bolt = {
			radius = 0.62,
			body = 0.86,
			lug = 1.12,
			lugLength = 0.7,
			cock = 0.72,
			stem = 0.4,
			knob = 0.84,
			side = 0.03,
		},
		-- no clipping (user 2026-10-26: "make sure the animations are accurate, doesnt clip"), round widths: the top
		-- round sits `under` below the bolt's body, its head `behind` ahead of the open bolt's face (so the bolt clears
		-- it before it rises)
		gap = { under = 0.55, behind = 0.4 },
		-- the magazine well, an open box with its near side cut away (round widths): `wall` thick, `inside` each side of
		-- the stack's middle, `front`/`rear` past the rounds' tips and heads, the walls' top `above` the top round,
		-- `room` under the last round, `lip` the near side's low rim (no follower or spring, user 2026-10-26: "remove
		-- the spring and platform in the magazine ... just make the bullet come up on its own")
		well = {
			wall = 0.12,
			inside = 1,
			front = 0.25,
			rear = 0.25,
			above = 0.55,
			room = 0.6,
			lip = 0.24,
		},
		-- a stripper clip's strip at its rounds' heads (round widths: thick, wider than a round)
		strip = { thick = 0.12, width = 1.15 },
		-- an en-bloc clip: a plate behind its rounds on the far side (round widths)
		enbloc = { thick = 0.1 },
		-- a pump gun's tube, drawn as an open trough (round widths each side of the shells)
		trough = 0.75,
		stagger = 0.42, -- a double stack's rounds, side to side, in round diameters (when they sit closer than `double`)
		double = 0.95, -- rounds closer than this many diameters apart are a double stack
		tubeStep = 1.02, -- a pump gun's tube: shell lengths from one shell to the next
		openFrom = 0.04, -- share of the bolt's travel back from which the action counts as open
		closing = 0.05, -- share of the travel the bolt must come forward from its furthest to count as closing
		rise = 0.14, -- seconds the stack takes to come up a round
		-- a clip's rounds pushed in settle onto the stack over `settle` seconds all told (user 2026-10-26: "make sure
		-- all the bullets are rested before bolting close"); they are down before the closing bolt's face reaches
		-- their heads whatever the time
		settle = 0.12,
		-- a semi-automatic's self-cycling action is a blur (Config/Weapons action.boltTime, ~0.1 s): the cut-away plays
		-- its own cycle after a shot over `time` seconds (under its fireTime), back over the first `back` share, held
		-- to `hold`, home by the end (user 2026-10-26: "for semi auto rifles ... its not accurate to how the bullets
		-- are being fed")
		auto = { time = 0.3, back = 0.3, hold = 0.42 },
		-- a round fed: its head on the bolt's face, it rises to the chamber's line as the face goes from the stack's
		-- heads to the chamber, nose up by up to `tilt` degrees; the stack under it comes up a round as it clears, over
		-- the first 1/`clear` of that
		feed = { tilt = 9, clear = 1.6 },
		tubeFeed = 0.75, -- a pump gun: the shell rides up onto the carrier over this share of the bolt's way forward
		eject = 0.8, -- share of the bolt's travel back at which the case (or a round) leaves it
		-- the case thrown out: seconds, how far up, out to the right and back (round lengths), turns
		fly = { time = 0.5, up = 1.6, out = 0.8, back = 0.9, turns = 1.5 },
		fade = 0.6, -- share of a throw or a drop after which it fades out
		spentShade = 0.35, -- a fired shotgun hull, darker by this share
		-- an empty en-bloc clip dropping out of the bottom: seconds, how far (clip heights)
		drop = { time = 0.55, fall = 3, tilt = 35 }, -- (tilt: degrees it tips as it falls)
		-- a round's length and width (studs) until the weapon's own are known
		fallback = { length = 0.2, width = 0.03 },
		-- the stack's step down, in round diameters: the gun's own rounds' spacing where it is at least `tight`, else
		-- `pitch` (a detachable box spreads them down to its bottom, `floor` diameters above it)
		tight = 0.5,
		pitch = 0.62,
		floor = 0.3,
		-- per weapon (modelled studs, gun space): where a chambered round's head sits (else the gun's own case
		-- template's head: every rifle but the Carcano, whose template is short) and a pump gun's tube, its first
		-- shell's head (forward of the shell on the carrier) (tools/blender/weapons/m1897.py: tube row 59 px, its
		-- rear 528 px, the breech face 548 px, the bore row 26 px; 0.00263 studs a px)
		weapons = {
			rifle_m91 = { chamber = { 0, 0.0715, -0.47 } },
			shotgun_m1897 = {
				tube = { 0, -0.0218, -0.4078 },
				chamber = { 0, 0.065, -0.355 },
			},
		},
		-- a hint plate's line by what the click would do (Rules/Firing.next) and the reload; {key}: the reload key
		hints = {
			Bolt = "Click: work the bolt",
			Pump = "Click: work the pump",
			Load = "Click: stop loading",
			Clip = "{key}: load a clip",
			Box = "{key}: new magazine",
			Shells = "{key}: load shells",
			Rounds = "{key}: load rounds", -- a revolver's gate
		},
		-- a revolver's cylinder (src/client/AmmoHud): the camera this many cylinder sizes off, from behind, right and up
		-- (gun space), its field of view
		drum = { distance = 1.6, from = { 0.45, 0.35, 1 }, fov = 40 },
	},

	-- a crystal in a cut-away (src/client/HudKit.shine: the staff's gem, the howitzer's): its own colour full, darkened
	-- by `dim`, toward Palette.UI.Hud.crystalHollow as the charge runs low; dead (Palette crystalDead), drop-outs every
	-- `every` s or so (`jitter` of that either way), each `time` s, to `depth` of its light
	Crystal = {
		dim = 0.35,
		flicker = { every = 0.22, jitter = 0.5, time = 0.08, depth = 0.35 },
	},

	-- the 3D gem (src/client/HudKit.gem; the staff's and the howitzer's): a real quartz point, its cracks engraved
	-- (Config/Assets hud_gem: Crystal + CrystalCracks, then the floating Shard1..); the shards float round it: each
	-- turns round the gem `orbit` degrees a second (by its place in the list), bobs `bob` studs at `speed` cycles a
	-- second, spins `spin` degrees a second on its own axis
	Gem = {
		model = { "Weapons", "Shared", "Staffs", "hud_gem" },
		parts = { "Crystal", "CrystalCracks", "Shard1", "Shard2", "Shard3", "Shard4", "Shard5" },
		shards = { orbit = { 10, -6, 14, -9, 7 }, bob = 0.06, speed = 0.7, spin = 50 },
	},

	Staff = {
		fov = 20,
		spin = 24, -- degrees a second the rock turns
		bob = { height = 0.04, speed = 1.4 }, -- its float (share of its size, cycles a second)
		flash = 0.4, -- full again: a flash toward white fading over this, `flashLight` of the way
		flashLight = 0.4,
		shake = { time = 0.3, size = 5, speed = 70 }, -- a refused shot
		pop = { time = 0.35, size = 0.25 }, -- full again: the rock swells by `size` and back over `time` s
		tilt = 12, -- degrees the rock leans toward the camera
		margin = 0.05,
		fit = 0.7, -- the view frames a cube this share of the rock's diagonal, shards and all (it turns inside it)
	},

	Artillery = {
		fov = 12,
		margin = 0.1,
		-- the cut-away: the whole gun, every part `see` see-through (user 2026-10-26: "make it general transparency")
		-- but the `solid` ones (the round is solid too) and the `skip` ones (not drawn); the box framed
		see = 0.62,
		-- the gun's own crystal parts, not drawn: the 3D gem (Config/Hud.Gem) sits in their place instead (user
		-- 2026-10-26: "replace the howizer gem with the same 3d gem"), as long as the gun's Crystal, its c axis along
		-- the gun's +Z (out of the breech face)
		solid = { "Crystal", "CrystalCracks" },
		skip = { "Origin", "Bore" },
		frame = { "Crystal", "Breech" }, -- (the first of these the gun has: the howitzer's view centres on its crystal)
		-- around the framed parts, studs: how far behind the breech and ahead of it the view reaches
		reach = { back = 2.2, front = 1.6 },
		-- the round in the chamber (field gun; gun space at rest): its head this far behind the hinge's z, on the bore
		chamberBack = 0.05,
		chamberWidth = 0.3, -- (studs: the round's box framed)
		slide = 0.35, -- seconds the round takes to go in (it goes in at Config/Artillery.Load.loaded)
		fly = { time = 0.6, back = 1.6, up = 0.8, turns = 1 }, -- the fired case thrown out as the breech opens
		openAt = 0.5, -- share of the breech's swing at which the case leaves
		fade = 0.6, -- share of the throw after which the case fades out
		-- where the camera looks from (a direction in gun space): the field gun from its right side (the breech and
		-- the round in profile), the howitzer from behind (the crystal sits in its breech face)
		views = {
			default = { from = { 1, 0, 0 } },
			-- the howitzer: from behind and under its breech, looking up at the crystal hanging under it as it does
			-- laid at 45..80 degrees (user 2026-10-26: "lower the camera more", "make sure the howitzer camera is
			-- acttually aimmed at this, or at least an accurate representation of the current howitzer"); only what
			-- moves with the barrel drawn (the bed, the deck and its ladder stood between)
			artillery_howitzer = {
				from = { 0.35, -0.25, 1 },
				only = { "Cradle", "CradleTrim", "Barrel", "BarrelRunes", "BarrelTrim", "Breech" },
			},
		},
		timer = "%.1f%%", -- the reload's share until it can fire, in tenths of a percent
	},

	-- the kit list (src/client/KitList, Rules/KitList; layout CombatHud.json "Kit"; user 2026-10-27: "i dont like the
	-- robblox default one", "make it a kit list but move it on the left"): Roblox's hotbar off, one row per item carried
	-- this life at the bottom left, as stencil plates (user 2026-10-27: "Stencil plates with the basic font"). Colours:
	-- Palette.UI.Hud kitName / kitKey / kitEmpty / kitHeldText, count, countLow, the team's field and rim (Teams).
	Kit = {
		order = { "Primary", "Grenade", "Shovel" }, -- Config/Weapons slots top to bottom; any other after, as it came
		-- KeyCode names: key n draws row n's item, and puts it away again if it is in the hands
		keys = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" },
		-- shown fully for `linger` seconds after any change (a number key, a draw or put-away, an item come or gone, a
		-- grenade count), then fading out over `fade` (user 2026-10-27: "2 s linger + 0.4 s fade")
		linger = 2,
		fade = 0.4,
		field = 0.62, -- a row's plate transparency (the team's field)
		fieldHeld = 0.1, -- the row in the hands (the team's rim colour)
		out = 16, -- reference px the row in the hands sticks out further to the right
		-- an item pressed while the last one is still going over the shoulder (Config/Locomotion.Stow) shows as chosen
		-- at once, its plate this transparent, for the put-away's time plus `wait` seconds
		pending = 0.5,
		wait = 0.3,
		gap = 4, -- reference px between rows
		count = "x%d", -- a grenade row's count (the Tool's "Count"; x0 once the last is thrown: the row stays)
	},
}

return table.freeze(Hud)
