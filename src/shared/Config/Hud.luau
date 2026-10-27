--!strict
-- The combat HUD, "quartermaster's brass" (user 2026-10-26: "make a unique UI that reflects that the weapons reload
-- sequence is like ... use actual parts from the weapon"; "show the chamber, the shell empty if fired, an animation of
-- the chamber / bolt moving and have the magazine box be the actual magazine (semi transparent showing ammo and show
-- ammo going up)"). Brass-rimmed panels, each with a cut-away of the real thing drawn live in a ViewportFrame:
-- - guns (src/client/AmmoHud): a three-quarter cut-away of the action, the gun a flat shadow, the bolt, the rounds
--   (the shared round Config/Assets ammo_rifle) and the magazine well clear;
-- - the staff (src/client/StaffHud): a magic rock in the team's colour, faded when empty, bright when full,
--   flickering while it can't be used (burnt out by a stage 3 shot);
-- - artillery (src/client/ArtilleryHud): the field gun's breech cut away with its round, the howitzer's crystal.
-- Layout (reference pixels) in src/shared/ui/CombatHud.json; colours in Config/Palette.UI.Hud. Data only.

local Hud = {
	-- the shared round's library model (Config/Assets ammo_rifle: Case + Bullet, the spent Casing, Origin at the head)
	Round = { "Weapons", "Shared", "Ammo", "ammo_rifle" },

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
		-- `room` under the last round for the follower, `lip` the near side's low rim; the follower plate (`width`,
		-- `thick` round widths, `length` round lengths) and its zigzag spring (`coils`, `thick` round widths, from
		-- `rear` to `front` of a round length back from the heads)
		well = {
			wall = 0.12,
			inside = 1,
			front = 0.25,
			rear = 0.25,
			above = 0.55,
			room = 1.3,
			lip = 0.24,
			follower = { width = 1.84, thick = 0.18, length = 0.85, gap = 0.1 },
			spring = { coils = 4, thick = 0.06, rear = 0.15, front = 0.8 },
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
		},
	},

	-- a crystal in a cut-away (src/client/HudKit.shine: the staff's rock, the howitzer's gem): until it's full, hollow
	-- (`hollow` see-through, Palette.UI.Hud.crystalHollow) and flickering (drop-outs every `every` s or so, `jitter` of
	-- that either way, each `time` s, to `depth` of its light); full, bright and `full` see-through; its black outline
	-- a copy pushed `push` of its size back from the camera, grown by `grow`
	Crystal = {
		dim = 0.35, -- its own colour full, darkened by this share (flat and dark, not bright)
		flicker = { every = 0.22, jitter = 0.5, time = 0.08, depth = 0.35 }, -- dead: drop-outs, to `depth` of its light
		-- the soft glow behind it: rings (shares of the view's height) each `see` see-through full, fading with the
		-- charge ^ `curve`
		glow = { rings = { 0.5, 0.72, 0.95 }, see = { 0.72, 0.84, 0.92 }, curve = 1.6 },
		-- motes circling it: how many, radians a second, the orbit (share of the view's width; `squash` its height),
		-- its wobble, pixels across, `see` see-through and `light` toward white
		motes = { count = 7, speed = 0.9, radius = 0.42, squash = 0.32, wobble = 0.05, size = 5, see = 0.15, light = 0.35 },
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
		fit = 0.62, -- the view frames a cube this share of the rock's diagonal (it turns inside it)
		-- the rock: the howitzer's cracked gem (Config/Assets artillery_howitzer, its Crystal + CrystalCracks)
		model = { "Weapons", "Shared", "Artillery", "artillery_howitzer" },
		parts = { "Crystal", "CrystalCracks" },
	},

	Artillery = {
		fov = 12,
		margin = 0.1,
		-- the cut-away: the whole gun, every part `see` see-through (user 2026-10-26: "make it general transparency")
		-- but the `solid` ones (the round is solid too) and the `skip` ones (not drawn); the box framed
		see = 0.62,
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
			artillery_howitzer = { from = { 0.35, 0.06, 1 } }, -- (low: user 2026-10-26, "lower the camera more")
		},
		timer = "%.1f%%", -- the reload's share until it can fire, in tenths of a percent
	},
}

return table.freeze(Hud)
