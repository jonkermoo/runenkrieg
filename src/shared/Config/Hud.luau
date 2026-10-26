--!strict
-- The combat HUD, "quartermaster's brass" (user 2026-10-26: "make a unique UI that reflects that the weapons reload
-- sequence is like ... use actual parts from the weapon"; "show the chamber, the shell empty if fired, an animation of
-- the chamber / bolt moving and have the magazine box be the actual magazine (semi transparent showing ammo and show
-- ammo going up)"). Brass-rimmed panels, each with a cut-away of the real thing drawn live in a ViewportFrame:
-- - guns (src/client/AmmoHud): the held weapon's own parts seen from its right, the action see-through, every part
--   posed as on the gun (the bolt working, the clip going in, the pump), its rounds one by one (the shared round,
--   Config/Assets ammo_rifle) rising in the magazine, the round or the fired case in the chamber riding the bolt;
-- - the staff (src/client/StaffHud): a magic rock in the team's colour, faded when empty, bright when full,
--   flickering while it can't be used (burnt out by a stage 3 shot);
-- - artillery (src/client/ArtilleryHud): the field gun's breech cut away with its round, the howitzer's crystal.
-- Layout (reference pixels) in src/shared/ui/CombatHud.json; colours in Config/Palette.UI.Hud. Data only.

local Hud = {
	-- the shared round's library model (Config/Assets ammo_rifle: Case + Bullet, the spent Casing, Origin at the head)
	Round = { "Weapons", "Shared", "Ammo", "ammo_rifle" },

	Gun = {
		fov = 8, -- the viewport camera's lens (narrow: near flat, a drawing more than a photo)
		margin = 0.12, -- share of the framed box added round it
		-- the cut-away: how see-through each part is (a part not named is solid)
		see = {
			Metal = 0.62,
			Receiver = 0.58,
			Wood = 0.86,
			Handguard = 0.86,
			Magazine = 0.55,
			Clip = 0.3,
			Trigger = 0.5,
		},
		-- never shown: the invisible origin, templates, and the merged rounds the HUD's own rounds stand in for
		skip = { "Gun", "Origin", "Casing", "Rounds", "Bullets", "Bore" },
		-- the box framed: these parts at rest (any the gun has), the chamber and the magazine's rounds
		frame = { "Bolt", "Clip", "Magazine", "Shell", "Receiver" },
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
		drop = { time = 0.55, fall = 3 },
		-- per weapon (modelled studs, gun space): the tube under the barrel, its first shell's head and the step
		-- forward between shells, from the shell on the carrier at rest; where a chambered shell's head sits
		-- (tools/blender/weapons/m1897.py: tube row 59 px, its rear 528 px, the breech face 548 px; shell row 42 px,
		-- head 628 px; 0.00263 studs a px)
		weapons = {
			shotgun_m1897 = {
				tube = { 0, -0.0447, -0.263 },
				chamber = { 0, 0.0421, -0.21 },
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
		-- to `depth` of its glow
		flicker = { every = 0.18, time = 0.07, depth = 0.15 },
		flash = 0.4, -- full again: a white flash fading over this
		shake = { time = 0.3, size = 5, speed = 70 }, -- a refused shot
		-- the three stage lamps under it (Zoltraak's stages) light as the charge reaches each
		stagePulse = 6, -- cycles a second the reached lamp pulses while held, by `pulseDepth` of its light
		pulseDepth = 0.25,
		lampIdle = 0.55, -- a stage the mana could pay for: its lamp lit this share
		tilt = 12, -- degrees the rock leans toward the camera
		margin = 0.05,
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
