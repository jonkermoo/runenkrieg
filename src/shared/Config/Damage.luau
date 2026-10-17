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
		-- where a stage's beam lands: a blast (Blast below) of this many kg of TNT; 0 = no blast. Only the full beam
		-- damages the map (user: "it should destroy the map on a full beam")
		Charge = { 0, 0, 10 },
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
		-- knocks by overpressure, strongest first (Config/Ragdoll.Knocks); below the last: nothing
		Knocks = {
			{ above = 29, knock = "BlastThrow" },
			{ above = 10, knock = "Torso" },
			{ above = 8.5, knock = "Limb" },
		},
		-- map sections (Config/Destruction.Materials, the section's "Class"): a section fails at its class's overpressure;
		-- below that it loses MaxHP x (kPa / fail)^Weaken (so nearby blasts wear it down). Buildings and props.
		Fail = {
			Glass = 8,
			Tile = 300, -- a tiled roof loses the panels near the blast (~10 studs), not all of them (was 20, ~21)
			Thatch = 20,
			Door = 20,
			Wood = 25,
			-- sturdier than real masonry (user 2026-10-17): a full beam at a wall blows a 2-3 section hole, a story falls
			-- after 2-3 of them. At 10 kg: plaster ~10 studs, brick ~6, stone ~5.5 (real walls fail at ~70 kPa, ~19)
			Plaster = 300,
			Brick = 900,
			Stone = 1200,
		},
		FailDefault = 30,
		Weaken = 1, -- (was 2) each blast wears what it doesn't break, so blasts at one spot widen the hole
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
			rim = { count = 12, at = 1.2, size = 0.65, sink = 0.4 }, -- big balls: 4-stud voxels smooth away a thin rim
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
	},

	-- Respawn after this many seconds: Config/Metrics.Combat.RespawnDelay (Players.RespawnTime).
}

return table.freeze(Damage)
