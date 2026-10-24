--!strict
-- Health, damage, death and respawn (M12; user 2026-10-17, docs/MILESTONES.md M12). Rules/Damage and Rules/Blast read
-- this; src/server/Damage applies it. Data only.

local Damage = {
	Health = 100, -- every soldier's health; no regeneration (src/character/Health replaces Roblox's)
	HelmetFloor = 1, -- the health a helmet hit leaves at least (never fatal by itself)

	-- Damage by weapon class (Config/Weapons `class`) and hit zone (Rules/Damage.zone): the head, the torso (the
	-- HumanoidRootPart counts as torso), the limbs; `helmet` = a hit on the helmet's half of the head with the helmet on
	-- (it comes off, src/server/Helmets), never fatal by itself (user: "no fatal headshot from the helmet hit itself").
	-- A shotgun's numbers are per pellet, with its Config/Weapons `pellets` falloff (full to `full`, none past `none`).
	Weapons = {
		BoltRifle = { Head = 200, Torso = 70, Limb = 60, Helmet = 40 }, -- user: torso 70 (2 hits)
		SemiRifle = { Head = 200, Torso = 55, Limb = 45, Helmet = 40 }, -- W2: so they don't outclass the bolt rifles
		Shotgun = { Head = 30, Torso = 20, Limb = 12, Helmet = 10 },
	},
	-- Up close a helmet doesn't save you (user 2026-10-21: "one shot to the head up close"; bolt rifles only, a hard
	-- cutoff): within this many studs of the muzzle a helmet hit counts as a head hit (the helmet still comes off).
	-- Classes not listed: the helmet hit at every range.
	HelmetLethal = { BoltRifle = 100 } :: { [string]: number },

	-- A gun's butt stroke (Config/Melee, user-approved 2026-10-22): by zone as a shot's; a bare head goes down in one,
	-- the torso in two; the helmet comes off (never fatal by itself, HelmetFloor). Knocks: alive, the head, helmet and
	-- torso a medium one, a limb a slight one; killed, the zone's drop (Knocks.Killed).
	Melee = {
		Damage = { Head = 100, Torso = 50, Limb = 35, Helmet = 35 },
		Knocks = { Head = "Torso", Helmet = "Torso", Torso = "Torso", Limb = "Limb" },
	},

	-- Every hit knocks you to the ground (user 2026-10-17): the Config/Ragdoll.Knocks entry by the zone that took the
	-- most damage, alive or killed by it: arms / legs / the helmet a slight knockback, the torso a medium one, a
	-- headshot kill a collapse.
	Knocks = {
		Alive = { Head = "Limb", Helmet = "Limb", Torso = "Torso", Limb = "Limb" },
		Killed = { Head = "HeadDrop", Helmet = "HeadDrop", Torso = "TorsoDrop", Limb = "LimbDrop" },
		Other = "LimbDrop", -- died some other way (a fall, a reset)
	},

	-- The staff (user 2026-10-17): checked on the server, a sphere cast from the caster's head toward the target, as wide
	-- as the beam, as long as the stage's range; no hit zones and no damage falloff (user: "no damage fall off, but
	-- increase the range throughout each stage of the charge"). Per stage 1..3.
	Staff = {
		Range = { 150, 300, 500 }, -- studs
		Radius = { 0.5, 0.9, 1.6 }, -- the beam's half width for hits, studs
		Damage = { 35, 70, 200 },
		Knock = { "Limb", "Torso", "StaffThrow" }, -- alive; killed: the Killed knock below
		Killed = { "TorsoDrop", "TorsoDrop", "StaffThrow" },
		-- where a stage's beam lands: a blast (Blast below) of this many kg of TNT; 0 = no blast (user: "it should
		-- destroy the map on a full beam")
		Charge = { 0, 0.5, 10 },
		-- what each stage's blast does (user 2026-10-17: "a stage 2 should be capable of causing tree recoil and breaking
		-- surrounding glass, but not destroy a building part (maybe damage it)"): `soldiers` hurt and knocked by it
		-- (stage 2: only by its beam), `trees` felled or stripped by it (every tree near still shakes: Net "Explosion"),
		-- a `crater`; `wear`: a section loses at most this share of its MaxHP per blast (3 stage 2 shots break one),
		-- in full within `wearFull` studs of the blast (to the section's nearest surface), fading to 0 at `wearReach`
		-- (Studio rounds 1-2: neighbouring walls ~3 studs off broke too, then lost 20% a shot), except the classes in
		-- `breaks` (glass shatters)
		-- your own staff never hurts you (user 2026-10-18: "make sure that your own beam cant kill yourself"): the beam
		-- and its blast leave the caster out (its blast doesn't throw them either, `ownFling`: user 2026-10-21, a
		-- point-blank stage 3 threw its caster to their death), and a tree it fells doesn't hurt them for this many
		-- seconds after the shot (it lands Config/Damage.Trees.Fall.time after)
		SelfSafe = 5,
		Blasts = {
			{ soldiers = true, trees = true, crater = true, ownFling = false },
			{
				soldiers = false,
				trees = false,
				crater = false,
				wear = 0.4,
				wearFull = 1.5,
				wearReach = 3,
				breaks = { Glass = true },
			},
			{ soldiers = true, trees = true, crater = true, ownFling = false },
		},
	},

	-- A blast that behaves like a real one (user 2026-10-17: "scale accordingly to how an explosion would be in real
	-- life"): Hopkinson-Cranz scaled distance Z = R / W^(1/3) (R metres, W kg of TNT) and the Kinney-Graham peak
	-- overpressure (Rules/Blast). Everything below is in kPa of overpressure, so a bigger charge reaches further by the
	-- cube root of its weight. At 10 kg: ~82 kPa at 18 studs, ~29 at 30, ~10 at 60.
	Blast = {
		MetresPerStud = 0.357, -- (Config/Weapons: 0.357 m per stud)
		AmbientKPa = 101.325,
		Reach = 12, -- Z beyond which nothing is felt (m / kg^(1/3)); bounds the search (~67 studs at 10 kg)
		-- soldiers: damage from `from` kPa (0) rising to `kill` kPa (`max` damage, kills from full health). At 10 kg:
		-- lethal within ~9 studs, ~72 at 10, ~31 at 12, ~8 at 14, nothing from ~15; a grenade's own blast kills to
		-- ~1.8-2.3 (user 2026-10-18: "lethal within ~8"; then "at points where players take damage from a blast is also
		-- when they should ragdoll": damage and knocks both end at ~15 studs; 2026-10-23: near misses should kill, kill
		-- 540 -> 400, was lethal to ~8). Was kill 80, from 8: lethal to ~16, hurt to ~70
		Soldier = { from = 126, kill = 400, max = 100 },
		-- whoever a blast hurts is flung away from it, as hard as it hurt them (user 2026-10-18: "the staff lvl 3 charge
		-- only flings me when im dead. i want it to fling me when it damages me too, scaled to damage"): the `knock`
		-- (Config/Ragdoll.Knocks) at `least` of its force for the slightest hurt, up to all of it at `max` damage; a
		-- kill flings in full. (Was knocks by pressure: thrown within ~6 studs, knocked down ~10, light ~15.)
		Fling = { knock = "BlastThrow", least = 0.3 },
		-- map sections (Config/Destruction.Materials, the section's "Class"): a section fails at its class's overpressure;
		-- below that it loses MaxHP x (kPa / fail)^Weaken (so nearby blasts wear it down). Buildings and props.
		-- User 2026-10-17: "buildings evaporate way too easily ... a stage 3 blast should not crumble a building ... an
		-- average building hit by a stage 3 blast should just leave a medium sized crater where it hit". At 10 kg every
		-- wall, roof, door and prop breaks within ~6 studs (a 1-2 section hole), is worn out to ~15, and glass breaks
		-- within ~37 (stage 2's 0.5 kg: ~14). Was glass 8 (~72 studs), thatch / door / wood 20-25 (~33), tile / plaster
		-- 300 (~10), brick 900, stone 1200 (map session's sturdier masonry).
		Fail = {
			Glass = 20,
			Tile = 1000,
			Thatch = 1000,
			Door = 1000,
			Wood = 1000,
			Plaster = 1000,
			Brick = 1000,
			Stone = 1200,
			-- player-built sandbags (Config/Build): earth soaks a blast; a grenade at the foot takes one column
			-- (~1.3 studs), the staff's full beam ~5, the howitzer ~17
			Sandbag = 1500,
		},
		FailDefault = 1000,
		Weaken = 1, -- (was 2) each blast wears what it doesn't break, so blasts at one spot widen the hole
		-- section kinds a blast only wears, never breaks: each floor is one slab, so any blast in a room took the whole
		-- floor (user 2026-10-17: never break, until floors are split into pieces)
		WearOnly = { Floor = true },
		-- Cover (user 2026-10-18: "people behind cover arent hurt by explosions, unless their cover got destroyed"): a
		-- blast hurts a soldier by the share of these body parts it has a clear line to, cast after it has broken what
		-- it breaks (so lost cover is no cover), and flings them as hard as that hurts (Fling above). Under `minShare`
		-- nothing reaches them. Lines skip whatever is within `skip` studs of the blast (the wall it went off against).
		-- Within `near` studs of the torso cover doesn't count (user 2026-10-23: "a grenade or staff explosion that
		-- missed a few studs away should kill"; a blast lying on the ground lost its lines to bumps and grass). 5: a
		-- blast 4 studs off on the ground is ~4.8 from the torso (~2.7 up).
		Cover = {
			parts = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" },
			minShare = 0.17,
			skip = 1,
			near = 5,
		},
		-- classes that break at their fail pressure or not at all, never worn bit by bit (Studio round 1: glass with 1 HP
		-- added up weaker blasts, so a second stage 2 shot broke windows far off)
		Brittle = { Glass = true },
		-- trees (Config/TreeSway.Tag): at their trunk base over `fail` a tree is felled whole (no stump: the crater is
		-- there; user 2026-10-17); below it loses its HP (Trees below) like a section: MaxHP x (kPa / fail)^Weaken
		Tree = { fail = 60, weaken = 2 },
		-- a crater in the terrain (Rules/Blast.craterPlan): radius = perCubeRoot x W^(1/3) studs (~5 at 10 kg), the ball
		-- sunk `sink` x radius; a low rim of `rim.count` balls of `rim.size` x radius at `rim.at` x radius, sunk
		-- `rim.sink` x radius under the ground (it rises ~(size - sink) x radius); the ground out to `churn` x radius
		-- turns from `churnFrom` to `churnTo` (blasted earth: grass is gone at once and never grows back; user: "as the
		-- battle goes on, there should be little to no grass on the map"), until it fills back in (`Refill`).
		-- The hole is a wide, shallow bowl you can walk out of (user 2026-10-18: a 50 kg shell's sunk ball left a pit 12
		-- deep with near-upright walls, "players are unable to get out"): `width` x radius across its mouth, `depth` x
		-- radius deep at its centre, a parabola to the mouth, pressed into the ground as it lies (on a slope too: a level
		-- cut left an uphill cliff); tests/blast.spec keeps its walls plus a 25 degree hillside under the walkable slope.
		-- 10 kg: ~20 across, ~3 deep; 50 kg: ~34 across, ~5 deep (Studio: the voxels make it ~2/3 that deep).
		Crater = {
			perCubeRoot = 2.32,
			width = 2, -- (1.7 / 0.75 walked out on the flat but left too steep a wall up a 0.4 slope)
			depth = 0.6,
			-- (Studio: 0.38 / 0.2 at 1.15 left no rim, 0.65 / 0.4 at 1.2 rose 2-2.5 and narrowed the hole; 0.45 / 0.4 at
			-- 1.35 rose ~+0.9..+1.3); now just past the bowl's mouth
			rim = { count = 16, at = 2.15, size = 0.45, sink = 0.4 },
			churn = 2.5,
			churnDepth = 1.5, -- x radius: only ground this far above or below the blast churns (none for a blast up a wall)
			churnFrom = { "Grass", "LeafyGrass", "Ground", "Sand" },
			churnTo = "Mud",
			-- Craters fill back in (Rules/Refill, src/server/Ground; user 2026-10-23: "during long battles i dont want
			-- the map to disappear because of craters", picked 2 + 5 + 2 min and a cap of 40): `delay` s after the blast
			-- the ground eases back to what it was in `steps` even steps over `time` s, then stays mud `mud` s more (a
			-- fresh blast there restarts it from the ground as it is). With more than `maxCraters` waiting, the oldest
			-- starts filling now. A blast's thrown earth puts back `rimFill` of what an older crater under it lacks.
			-- Trenches and gun pits never refill. The server checks every `tick` s and writes at most `budget` voxels a
			-- tick (the rest wait for the next).
			Refill = {
				delay = 120,
				time = 300,
				mud = 120,
				steps = 20,
				maxCraters = 40,
				rimFill = 0.5,
				tick = 1,
				budget = 40000,
			},
		},
	},

	-- Tree HP (user 2026-10-17: "trees get HP"; src/server/Trees, Rules/Trees). MaxHP = HP[kind] x the tree's scale.
	-- Bullets chip the trunk by weapon class (per pellet for a shotgun); blasts as Blast.Tree above. A tree felled by
	-- bullets falls along the shot and leaves a stump; a blast fells it whole, away from the blast, no stump.
	Trees = {
		HP = { Pine = 300, Broadleaf = 360, Birch = 240 }, -- ~30 rifle hits at scale 1
		Weapons = { BoltRifle = 10, SemiRifle = 8, Shotgun = 2 },
		-- a shovel's Destroy swings (src/server/Build, Trees.chop; user 2026-10-23): this many fell a tree of any size
		Chop = { swings = 10 },
		-- the fall: clients animate it over `time` s; then the server places it where it lies, anchored (no physics:
		-- user: "stay for some time ... don't lag the server"), as cover for `lifetime` s, at most `maxFallen` on the
		-- map (the oldest goes first); it sinks into the ground over `sinkTime` s and is removed.
		-- `tipShare`: how far along its height it rests on the ground (the canopy's top is soft)
		Fall = {
			time = 2.2,
			lifetime = 300,
			maxFallen = 60,
			sinkTime = 2.5,
			sinkDepth = 6,
			minTilt = 25, -- (was 60: an uphill fall stopped there and sank into the slope) it may lean on a hill
			maxTilt = 120, -- (was 95: downhill falls floated up to 6.6 over the slope)
			tipShare = 0.85,
			-- it lies clear of the ground along its whole length (samples along it): the trunk's half thickness to clear,
			-- tapering to `tipClear` x that at the top (the crown may press into the ground)
			samples = 10,
			tipClear = 0.2,
			-- landing: a bounce back of `bounce` degrees settling over `bounceTime` s (src/client/TreeFall)
			bounce = 7, -- (its peak is ~0.43 x this: ~3 degrees)
			bounceTime = 0.6,
			-- its imprint (user 2026-10-17: "not a crater ... a thick imprint", even, the tree not floating): the trunk lies
			-- pressed `depth` studs into the ground all along it, and wherever it lies on the ground (its underside within
			-- `touch` of it) the ground round it is churned to `churnTo`, `churnRadius` across and `churnDepth` deep, every
			-- `step` studs. (Carving a 1-stud trough didn't show in 4-stud voxels except on flat ground.)
			Imprint = {
				depth = 1,
				step = 2,
				touch = 0.8,
				churnRadius = 4.5,
				churnDepth = 3,
				churnFrom = { "Grass", "LeafyGrass", "Ground", "Sand" },
				churnTo = "Mud",
			},
			-- uprooted (felled whole by a blast): the butt lies on the ground (its half thickness up), with a root ball of
			-- mud at it (`radius` x the trunk's width, `min` to `max`: smaller vanishes in 4-stud voxels) and a pit where
			-- it stood (`pit` x that, `pitBack` x the radius behind the butt, its centre `pitSink` x it under the ground)
			-- (was 1.8 x the width, no cap: 7-9 stud mounds that buried the pit; then 2.6-3.2, user: "a tiny bit smaller")
			-- `material`: its own terrain material, coloured darker than mud (Config/Palette.Terrain)
			-- (Studio: rise 0.15 topped out +1.6..+3.1 with the voxels, and a 0.9 pit at 1.1 behind didn't show)
			Roots = {
				radius = 0.9,
				min = 2.3,
				max = 2.8,
				pit = 1.2,
				rise = -0.2,
				pitBack = 1.6,
				pitSink = 0.4,
				material = "Basalt",
			},
			-- soldiers under it when it lands: within `radius` (x the scale) of the trunk's line they take `damage` and
			-- the `knock`, pushed to the side they stand on; the trunk lets characters through for `ghost` s after (and
			-- longer while one is still inside it, up to `ghostMax`), so nobody is pushed into the ground or flung
			Crush = { radius = 2.5, damage = 60, knock = "Torso", ghost = 1.5, ghostMax = 6 },
		},
		-- a staff beam's direct hit on a trunk (standing or lying): `damage[stage]`; from `shatterFrom` the trunk
		-- shatters (debris, a stump left; the crown drops and sheds) - not the same as a blast at the roots, which fells it
		-- whole (user 2026-10-17)
		Direct = { damage = { 40, 120 }, shatterFrom = 3 },
		Stump = { height = 1.2, widthShare = 0.9 }, -- of the trunk's base width
		-- a felled tree lies with `share` x its MaxHP again (user 2026-10-17: "give it continue HP so it can be
		-- destroyed"): bullets and blasts wear it down; at 0 it sinks and fades away (Fall.sinkTime)
		Fallen = { share = 0.5 },
		-- The leaves have HP of their own (user 2026-10-17): HP[kind] x the tree's scale. Bullets never touch them.
		-- A staff beam through the canopy's box takes `through[stage]`, one passing or landing within `nearDistance[stage]`
		-- studs of it `near[stage]` (a few stage 2 shots strip a tree); a blast by its overpressure at the canopy: all
		-- at `blastFail` kPa, (kPa / blastFail)^blastWeaken below. Stripped (or the tree felled: its leaves go to 0),
		-- the canopy sheds over `shedTime` s on the clients and is removed. `react[stage]`: how hard a beam shakes the
		-- leaves and how many fall (x the leaf bits, src/client/Impacts), half for a beam only passing near.
		Leaves = {
			HP = { Pine = 100, Broadleaf = 120, Birch = 80 },
			through = { 12, 40, 200 },
			near = { 5, 30, 120 },
			nearDistance = { 2, 5, 10 },
			blastFail = 25,
			blastWeaken = 1,
			shedTime = 4,
			react = { 0.5, 1, 2 },
			nearReact = 0.5, -- x react for a beam only passing near
		},
	},

	-- Respawn after this many seconds: Config/Metrics.Combat.RespawnDelay (Players.RespawnTime).
}

return table.freeze(Damage)
