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
		Shotgun = { Head = 30, Torso = 20, Limb = 12, Helmet = 10 },
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
		-- except the classes in `breaks` (glass shatters)
		Blasts = {
			{ soldiers = true, trees = true, crater = true },
			{ soldiers = false, trees = false, crater = false, wear = 0.4, breaks = { Glass = true } },
			{ soldiers = true, trees = true, crater = true },
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
		-- soldiers: damage from `from` kPa (0) rising to `kill` kPa (`max` damage, kills from full health)
		Soldier = { from = 8, kill = 80, max = 100 },
		-- knocks by overpressure, strongest first (Config/Ragdoll.Knocks); below the last: nothing (only hurt). User
		-- 2026-10-17: "even if you miss your full charge, you should be able to ragdoll only the person you were trying
		-- to aim at (and the people really close to him)": at 10 kg thrown within ~6 studs, knocked down within ~10 (was
		-- 29 / 10 / 8.5 kPa: thrown ~30, knocked ~68). Whoever the blast kills is thrown wherever they stood.
		Knocks = {
			{ above = 1000, knock = "BlastThrow" },
			{ above = 320, knock = "Torso" },
		},
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
		},
		FailDefault = 1000,
		Weaken = 1, -- (was 2) each blast wears what it doesn't break, so blasts at one spot widen the hole
		-- section kinds a blast only wears, never breaks: each floor is one slab, so any blast in a room took the whole
		-- floor (user 2026-10-17: never break, until floors are split into pieces)
		WearOnly = { Floor = true },
		-- trees (Config/TreeSway.Tag): at their trunk base over `fail` a tree is felled whole (no stump: the crater is
		-- there; user 2026-10-17); below it loses its HP (Trees below) like a section: MaxHP x (kPa / fail)^Weaken
		Tree = { fail = 60, weaken = 2 },
		-- a crater in the terrain (Rules/Blast.craterPlan): radius = perCubeRoot x W^(1/3) studs (~5 at 10 kg), the ball
		-- sunk `sink` x radius; a low rim of `rim.count` balls of `rim.size` x radius at `rim.at` x radius, sunk
		-- `rim.sink` x radius under the ground (it rises ~(size - sink) x radius); the ground out to `churn` x radius
		-- turns from `churnFrom` to `churnTo` (blasted earth: grass is gone at once and never grows back; user: "as the
		-- battle goes on, there should be little to no grass on the map"). Terrain stays changed (voxels: no upkeep).
		Crater = {
			perCubeRoot = 2.32,
			sink = 0.45,
			-- (Studio: 0.38 / 0.2 at 1.15 left no rim, 0.65 / 0.4 at 1.2 rose 2-2.5 and narrowed the hole)
			rim = { count = 12, at = 1.35, size = 0.45, sink = 0.4 }, -- (0.5 / 0.35 at 1.35 rose ~2.2 at 6 studs)
			churn = 2.2,
			churnDepth = 1.5, -- x radius: only ground this far above or below the blast churns (none for a blast up a wall)
			churnFrom = { "Grass", "LeafyGrass", "Ground", "Sand" },
			churnTo = "Mud",
		},
	},

	-- Tree HP (user 2026-10-17: "trees get HP"; src/server/Trees, Rules/Trees). MaxHP = HP[kind] x the tree's scale.
	-- Bullets chip the trunk by weapon class (per pellet for a shotgun); blasts as Blast.Tree above. A tree felled by
	-- bullets falls along the shot and leaves a stump; a blast fells it whole, away from the blast, no stump.
	Trees = {
		HP = { Pine = 300, Broadleaf = 360, Birch = 240 }, -- ~30 rifle hits at scale 1
		Weapons = { BoltRifle = 10, Shotgun = 2 },
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
			minTilt = 60,
			maxTilt = 95,
			tipShare = 0.85,
		},
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
