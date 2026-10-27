--!strict
-- Classes and the match currency (user 2026-10-27: "a type of temporary currency that resets every match that allows
-- players to spawn with a certain loadout"). Every player starts a match with `Start` points, earns `Earn` for kills,
-- assists, captures and building, and pays a class's `cost` each life it spawns as that class (src/server/Loadouts,
-- Rules/Classes). The points are invisible to the player except in the loadout menu while respawning (user: "they only
-- see their match currency in the loadout menu when they are respawning"). A pick it can't pay for spawns the
-- `Default` class and stays picked.

export type Def = {
	name: string,
	cost: number,
	-- the primary: "weapon" (the kit's bolt rifle, Config/Uniforms.Kits) or a key of the kit's `Gear` below
	primary: string,
	grenades: boolean, -- carries the kit's grenades
	helmet: string?, -- a key of the kit's `Gear` (the alternate helmet); nil: the kit's own headwear
	builds: { string }, -- the Config/Build.Pieces kinds it may lay and build
	locked: boolean?, -- shown, but not picked yet (coming later)
	blurb: string, -- the loadout menu's line under the name (src/client/Menus)
}

-- what everyone may build (user: "everyone else can only build trenches and other small assets")
local SMALL = { "Trench", "Sandbags", "Wire" }

local Classes = {
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
	Start = 0, -- points at the start of every match
	Default = "Rifleman", -- free: anyone can always play it
	-- the classes in the menu's order
	List = { "Rifleman", "Grenadier", "AutoRifler", "Engineer", "Mage" },
	Defs = {
		Rifleman = {
			name = "Rifleman",
			blurb = "Bolt-action rifle",
			cost = 0,
			primary = "weapon",
			grenades = false,
			builds = SMALL,
		},
		Grenadier = {
			name = "Grenadier",
			blurb = "Rifle and two grenades",
			cost = 50,
			primary = "weapon",
			grenades = true,
			builds = SMALL,
		},
		-- the team's semi-automatic rifle and its alternate helmet (user: "these will use the alternate helmet")
		AutoRifler = {
			name = "Auto rifler",
			blurb = "Semi-automatic rifle, plate helmet",
			cost = 100,
			primary = "semi",
			grenades = false,
			helmet = "altHelmet",
			builds = SMALL,
		},
		-- coming later: the only class that builds artillery (user: "only they can build artilleries"); price a placeholder
		Engineer = {
			name = "Engineer",
			blurb = "Builds artillery",
			cost = 150,
			primary = "weapon",
			grenades = false,
			builds = { "Trench", "Sandbags", "Wire", "Gun" },
			locked = true,
		},
		Mage = { name = "Mage", blurb = "Rune staff", cost = 200, primary = "staff", grenades = false, builds = SMALL },
	} :: { [string]: Def },
	-- each kit's class gear beyond Config/Uniforms.Kits (its bolt rifle, grenades, shovel and helmet): Config/Weapons
	-- and Config/Assets entries
	Gear = {
		uniform1 = { semi = "rifle_mondragon", staff = "staff_grey", altHelmet = "helmet_stahl_plate" },
		uniform2 = { semi = "rifle_remington8", staff = "staff_olive", altHelmet = "helmet_m33_plate" },
		uniform3 = { semi = "rifle_winchester1907", staff = "staff_white", altHelmet = "helmet_adrian_visor" },
	} :: { [string]: { [string]: string } },
	-- points earned (user: kills, assists, captures, building; prices scaled down, so these are too)
	Earn = {
		Kill = 10,
		Headshot = 2, -- on top of the kill, when the killing hit was to the head
		Assist = 5,
		Capture = 15, -- a zone captured (src/server/Loadouts.award; the zone capture calls it)
		Piece = 2, -- a sandbag wall, wire or gun built to full (the finishing swing)
		Trench = 1, -- a trench square dug to full (the finishing swing)
	},
	-- who gets the kill and the assists: the last enemy to hurt the soldier within `window` seconds before the death
	-- gets the kill; every other one who took at least `least` health off them in that time an assist
	Assist = { window = 15, least = 20 },
}

return Classes
