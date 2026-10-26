--!strict
-- The combat HUD, "quartermaster's brass" (user 2026-10-26: "make a unique UI that reflects that the weapons reload
-- sequence is like ... use actual parts from the weapon"; "show the chamber, the shell empty if fired, an animation of
-- the chamber / bolt moving and have the magazine box be the actual magazine (semi transparent showing ammo and show
-- ammo going up)"). Brass-rimmed panels, each with a cut-away of the real thing drawn live in a ViewportFrame:
-- - guns (src/client/AmmoHud): only the ammo, real models (its rounds one by one, the shared round Config/Assets
--   ammo_rifle, rising in the magazine; the round or the fired case in the chamber riding the bolt) in flat
--   brass-edged shapes;
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
		fov = 8, -- the viewport camera's lens (narrow: near flat, a drawing more than a photo)
		margin = 0.12, -- share of the framed box added round it
		-- the flat shapes behind the magazine and the chamber (round lengths, but `thick` in studs): `pad` round the
		-- ammo, the brass edge `edge` wider, `back` behind the rounds, `see` how see-through
		slab = { thick = 0.01, pad = 0.06, edge = 0.03, back = 0.12, see = 0.1 },
		stagger = 0.42, -- a double stack's rounds, side to side, in round diameters (when they sit closer than `double`)
		double = 0.95, -- rounds closer than this many diameters apart are a double stack
		tubeStep = 1.02, -- a pump gun's tube: shell lengths from one shell to the next
		openFrom = 0.04, -- share of the bolt's travel back from which the action counts as open
		closing = 0.05, -- share of the travel the bolt must come forward from its furthest to count as closing
		rise = 0.14, -- seconds the stack takes to come up a round
		eject = 0.8, -- share of the bolt's travel back at which the case (or a round) leaves it
		feed = 0.75, -- closing, the next round rides up out of the magazine in front of the bolt over this share
		-- the case thrown out: seconds, how far up and out (round lengths), turns
		fly = { time = 0.5, up = 1.6, back = 0.9, turns = 1.5 },
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

	Staff = {
		fov = 20,
		spin = 24, -- degrees a second the rock turns
		bob = { height = 0.04, speed = 1.4 }, -- its float (share of its size, cycles a second)
		empty = 0.72, -- the rock's transparency with no mana (full: 0)
		-- burnt out (a stage 3 shot, Config/Spells.Mana.burnout): drop-outs every `every` s or so, each `time` s, down
		-- to `depth` of its glow (`jitter`: the gaps vary by this share either way)
		flicker = { every = 0.18, jitter = 0.5, time = 0.07, depth = 0.15 },
		flash = 0.4, -- full again: a white flash fading over this
		shake = { time = 0.3, size = 5, speed = 70 }, -- a refused shot
		-- the three stage lamps under it (Zoltraak's stages) light as the charge reaches each
		stagePulse = 6, -- cycles a second the reached lamp pulses while held, by `pulseDepth` of its light
		pulseDepth = 0.25,
		lampIdle = 0.55, -- a stage the mana could pay for: its lamp lit this share
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
		-- the field gun's cut-away: the parts shown (any the gun has), how see-through, the box framed
		show = { "Barrel", "Bore", "Breech", "Cradle", "Crystal", "CrystalCracks" },
		see = { Barrel = 0.6, Cradle = 0.75, Bore = 1 },
		frame = { "Breech", "Crystal" },
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
			artillery_howitzer = { from = { 0.45, 0.3, 1 } },
		},
		text = {
			elevation = "Elev %+.1f°",
			traverse = "Trav %+.1f°",
			ready = "Ready",
			loading = "Loading",
			charging = "Charging",
			broken = "Knocked out",
		},
	},
}

return table.freeze(Hud)
