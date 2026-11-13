--!strict
-- Classes and the match currency (user 2026-10-27: "a type of temporary currency that resets every match that allows
-- players to spawn with a certain loadout"). Every player starts a match with `Start` points and earns `Earn`. A class
-- is unlocked once a match for its `unlock`, which pays its first life, and then costs its `fee` each respawn as it
-- (user 2026-11-12: "Grenadier and Engineer is 100 to unlock, include that it is 50 after respawn and give the kit to
-- the player for free"; src/server/Loadouts, Rules/Classes.price). The points are invisible to the player except in the loadout menu while respawning (user: "they only
-- see their match currency in the loadout menu when they are respawning"). A pick it can't pay for spawns the
-- `Default` class and stays picked.

export type Def = {
	name: string,
	unlock: number, -- paid once a match, at the first spawn as the class; it pays that first life too
	fee: number, -- paid every later life as the class (each respawn)
	-- the primary: "weapon" (the kit's bolt rifle, Config/Uniforms.Kits) or a key of the kit's `Gear` below
	primary: string,
	grenades: boolean, -- carries the kit's grenades
	helmet: string?, -- a key of the kit's `Gear` (the alternate helmet); nil: the kit's own headwear
	builds: { string }, -- the Config/Build.Pieces kinds it may lay and build
	locked: boolean?, -- shown, but not picked yet (coming later)
	blurb: string, -- the loadout menu's line under the name (src/client/Menus)
}

-- what everyone may build (user: "everyone else can only build trenches and other small assets")
-- (Hesco barriers and sandbag piles were the Engineer's from round 7 to 2026-11-02; everyone's again, user 2026-11-02:
-- "allow sandbags and barriers to be built by ordinary soldiers too")
-- (foxholes everyone's, user 2026-11-02)
local SMALL = { "Trench", "Foxhole", "Sandbags", "Wire", "Hesco", "Bridge" }

local Classes = {
	-- the loadout's orders sheet (user 2026-11-11, option A; was paper kit cards): each class's rune (Config/Runes), a
	-- row you can't afford this see-through, a row under the mouse filled with ink this see-through
	Cards = {
		runes = {
			Rifleman = "raidho",
			Grenadier = "sowilo",
			AutoRifler = "tiwaz",
			Shotgunner = "hagalaz",
			Engineer = "othala",
			Mage = "ansuz",
		},
		faded = 0.45,
		hover = 0.88,
	},
	Currency = "Marks", -- the currency's name, shown in the loadout menu
	-- the menus (src/client/Menus): seconds after a death before the loadout menu opens (the death is seen first)
	MenuAfterDeath = 2,
	-- the menus' camera on the match (src/client/MatchCam): a random spot of the map at least `Inset` studs in from its
	-- edges on open ground (`Tries` rolls), a new one every `Every` seconds; the camera circles it `Distance` out and `Height` up at `Turn` rad/s,
	-- looking `LookUp` above the ground there; the ground is found by a ray from `RayTop` down `RayDepth`
	Cam = {
		Every = 8,
		Inset = 120,
		Tries = 6,
		Distance = 70,
		Height = 32,
		Turn = 0.05,
		LookUp = 4,
		RayTop = 400,
		RayDepth = 800,
	},
	-- the loadout menu's soldier (src/client/Menus): the view's light, the camera `Distance` out and `Up` over the point
	-- it looks at (`Look` up from the rig's root), at `Fov` degrees, circling at `Turn` rad/s
	Preview = {
		Ambient = { 170, 170, 170 },
		Light = { 255, 255, 255 },
		Distance = 19,
		Up = 0.9,
		Look = 0.6,
		Fov = 28,
		Turn = 0.35,
	},
	-- points at the start of every match: enough to unlock and play the Grenadier or the Engineer (user 2026-11-05:
	-- "give all soldiers a starting fee enough to pay for engineer or to pay for grenadier"; 85 from 2026-11-06, 100
	-- with the 2026-11-12 prices)
	Start = 100,
	Default = "Rifleman", -- free: anyone can always play it
	-- the classes in the menu's order
	List = { "Rifleman", "Grenadier", "Engineer", "AutoRifler", "Shotgunner", "Mage" }, -- (user 2026-11-11)
	Defs = {
		-- the kit's own helmet (user 2026-10-27: "the plated helmets should only be on soldiers with semi auto rifles")
		Rifleman = {
			name = "Rifleman",
			blurb = "Bolt-action rifle",
			unlock = 0,
			fee = 0,
			primary = "weapon",
			grenades = false,
			builds = SMALL,
		},
		Grenadier = {
			name = "Grenadier",
			blurb = "Rifle and five grenades",
			unlock = 100,
			fee = 50,
			primary = "weapon",
			grenades = true,
			builds = SMALL,
		},
		-- the team's semi-automatic rifle and its alternate helmet (user: "these will use the alternate helmet")
		AutoRifler = {
			name = "Auto rifler",
			blurb = "Semi-automatic rifle",
			unlock = 200,
			fee = 100,
			primary = "semi",
			grenades = false,
			helmet = "altHelmet",
			builds = SMALL,
		},
		-- the team's pump shotgun and the shotgun shell helmet, no grenades (user 2026-10-27: "can you add the shotgun
		-- class for 150?")
		Shotgunner = {
			name = "Shotgunner",
			blurb = "Pump shotgun, shell-band helmet",
			unlock = 200,
			fee = 100,
			primary = "shotgun",
			grenades = false,
			helmet = "shellHelmet",
			builds = SMALL,
		},
		-- the only class that builds artillery (user: "only they can build artilleries"); open to players (user
		-- 2026-11-01), not yet to bots (Config/Bots.Classes)
		Engineer = {
			name = "Engineer",
			blurb = "Builds field guns, rune howitzers, MG nests and dugouts", -- (its own builds; user 2026-11-11)
			unlock = 100,
			fee = 50,
			-- the kit's pistol (user 2026-10-28: the Engineer's own sidearm; the C96, the Nagant, the Webley)
			primary = "pistol",
			grenades = false,
			-- the team's soft cloth cap (user 2026-10-27: "a cap that isnt bullet proof"; Config/Assets fit.soft)
			helmet = "engineerCap",
			-- (Nest: the MG nest, user 2026-10-27; Dugout: user 2026-11-02, "Engineers only")
			builds = { "Trench", "Foxhole", "Sandbags", "Wire", "Hesco", "Bridge", "Gun", "Nest", "Dugout" },
		},
		-- the team's goggles (user 2026-10-27: "goggles on mage")
		Mage = {
			name = "Mage",
			blurb = "Rune staff",
			unlock = 300,
			fee = 150,
			primary = "staff",
			grenades = false,
			helmet = "goggles",
			builds = SMALL,
		},
	} :: { [string]: Def },
	-- each kit's class gear beyond Config/Uniforms.Kits (its bolt rifle, grenades, shovel and helmet): Config/Weapons
	-- and Config/Assets entries
	Gear = {
		uniform1 = {
			pistol = "pistol_c96",
			semi = "rifle_mondragon",
			staff = "staff_grey",
			altHelmet = "helmet_stahl_plate",
			goggles = "helmet_stahl_goggles",
			shotgun = "shotgun_m1897",
			shellHelmet = "helmet_stahl_ammo",
			engineerCap = "cap_feld",
		},
		uniform2 = {
			pistol = "pistol_nagant",
			semi = "rifle_remington8",
			staff = "staff_olive",
			altHelmet = "helmet_m33_plate",
			goggles = "helmet_m33_goggles",
			shotgun = "shotgun_m1897",
			shellHelmet = "helmet_m33_ammo",
			engineerCap = "cap_side",
		},
		uniform3 = {
			pistol = "pistol_webley",
			semi = "rifle_winchester1907",
			staff = "staff_brown",
			altHelmet = "helmet_adrian_visor",
			goggles = "helmet_brodie_goggles",
			shotgun = "shotgun_m1897",
			shellHelmet = "helmet_brodie_ammo",
			engineerCap = "cap_trench",
		},
	} :: { [string]: { [string]: string } },
	-- every award below paid this many times over, in every mode (user 2026-11-02 set 1.5; the marks rebalance,
	-- 2026-11-05, folded it into the numbers below; 2026-11-06 a quarter, user: "i played for about 10 minutes and i
	-- have 300 points already": a 20 v 20 bot match measured a player at ~27 a minute, the target ~6, so the Auto rifler
	-- comes at ~15 minutes and the Mage at ~28); the points may hold fractions, shown rounded down (src/client/Menus)
	-- 2026-11-12 four times that again with the new prices (unlocks 100 / 200 / 300, fees 50 / 100 / 150; user chose
	-- ~27 a minute): a Grenadier or Engineer unlocks in ~4 minutes and a ~2 minute life pays its 50 back; the Auto
	-- rifler and Shotgunner (~7.5 minutes) and the Mage (~11) cost an average soldier more each life than it earns
	Pay = 1,
	-- points earned (the marks rebalance, user 2026-11-05: kills, objectives, building, support and gun crews all rated
	-- the same, so each style earns about 6 a minute; no Win award, "drop")
	Earn = {
		Kill = 20,
		Headshot = 4, -- on top of the kill, when the killing hit was to the head
		Assist = 8,
		Capture = 30, -- a zone captured (src/server/Loadouts.award; the zone capture calls it)
		-- Normal mode (src/server/Frontline, user 2026-10-27): each soldier in the zone when an enemy sector goes neutral;
		-- a kill in or near your side's sector while the enemy is attacking it
		Neutralise = 15,
		Defend = 10,
		Piece = 4, -- a sandbag wall, wire or gun built to full (the finishing swing)
		-- building by the time at it (user 2026-11-06: "player's who play engineer should benefit just as much as
		-- aggressive players who play strictly for gun pvp"): per full dig's worth of Build swings (Config/Shovel.Dig
		-- .length, 2.6 s) that raise something, a trench square, a piece, a dugout, a repair (src/server/Build,
		-- Rules/Build.swingSpent): 23 a minute (Pay 1), a fighter's rate; it replaces the Trench award
		Work = 1,
		Repair = 4, -- a wrecked gun made usable again (the swing that does it; src/server/Artillery)
		Drag = 5, -- a downed teammate dragged at least `DragPay.least` studs (once per knock-down; src/server/Dragging)
		Heal = 8, -- per `HealPer` health healed on a teammate (src/server/Healing)
	},
	HealPer = 100,
	DragPay = { least = 10 },
	-- who gets the kill and the assists: the last enemy to hurt the soldier within `window` seconds before the death
	-- gets the kill; every other one who took at least `least` health off them in that time an assist
	Assist = { window = 15, least = 20 },
}

return Classes
