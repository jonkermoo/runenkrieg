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

	-- Every hit knocks (user 2026-10-17: "getting shot any where should trigger a ragdoll. a headshot kill will drop the
	-- player with little to no ragdoll. a torso will do a medium one and a arm/leg will do a super light one"): the
	-- Config/Ragdoll.Knocks entry by the zone that took the most damage, alive or killed by it. "Helmet" is the helmet
	-- hit (alive by the rule above).
	Knocks = {
		Alive = { Head = "Stagger", Helmet = "Stagger", Torso = "Torso", Limb = "Stagger" },
		Killed = { Head = "HeadDrop", Helmet = "HeadDrop", Torso = "TorsoDrop", Limb = "LimbDrop" },
	},

	-- The staff (user 2026-10-17): checked on the server, a sphere cast from the caster's head toward the target, as wide
	-- as the beam, as long as the stage's range; no hit zones and no damage falloff (user: "no damage fall off, but
	-- increase the range throughout each stage of the charge"). Per stage 1..3.
	Staff = {
		Range = { 150, 300, 500 }, -- studs
		Radius = { 0.5, 0.9, 1.6 }, -- the beam's half width for hits, studs
		Damage = { 35, 70, 200 },
		Knock = { "Stagger", "Torso", "StaffThrow" }, -- alive; killed: the Killed knock below
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
			{ above = 8.5, knock = "Stagger" },
		},
		-- map sections (Config/Destruction.Materials, the section's "Class"): a section fails at its class's overpressure;
		-- below that it loses MaxHP x (kPa / fail)^Weaken (so nearby blasts wear it down). Buildings and props.
		Fail = {
			Glass = 8,
			Tile = 20,
			Thatch = 20,
			Door = 20,
			Wood = 25,
			Plaster = 28,
			Brick = 70,
			Stone = 80,
		},
		FailDefault = 30,
		Weaken = 2,
		-- trees (Config/TreeSway.Tag): over this a tree snaps at the trunk and falls away from the blast; despawns after
		Tree = { fail = 60, push = 18, spin = 1.2, despawn = 30 },
		-- a crater in the terrain: radius = perCubeRoot x W^(1/3) studs (~5 at 10 kg), the ball sunk `sink` x radius
		Crater = { perCubeRoot = 2.32, sink = 0.45 },
	},

	-- Respawn after this many seconds: Config/Metrics.Combat.RespawnDelay (Players.RespawnTime).
}

return table.freeze(Damage)
