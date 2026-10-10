--!strict
-- Map 1 "Trenches into a village": sector chain data. Layout rationale: docs/maps/MAP1.md.
-- X runs along the front (west = Trench side, east = Village side); Z is lateral. Units: studs.
-- Team "West" holds the trench side, "East" the village side.

export type Sector = {
	id: string,
	name: string,
	x: number,
	z: number,
	radius: number,
	startOwner: "West" | "East" | "Neutral",
	isHQ: boolean?,
}

local Map1 = {
	name = "Trenches into a Village",
	bounds = { minX = -150, maxX = 1950, minZ = -400, maxZ = 400 }, -- playable area
	fogEnd = 600,
	sectors = {
		{ id = "HQW", name = "Rear Depot", x = 0, z = 0, radius = 60, startOwner = "West", isHQ = true },
		{ id = "S1", name = "Reserve Trench", x = 300, z = 20, radius = 45, startOwner = "West" },
		{ id = "S2", name = "The Ridge", x = 600, z = -60, radius = 45, startOwner = "West" },
		{ id = "S3", name = "Windmill Farm", x = 900, z = 40, radius = 45, startOwner = "Neutral" },
		{ id = "S4", name = "Canal Bridge", x = 1200, z = 0, radius = 45, startOwner = "East" },
		{ id = "S5", name = "Church Square", x = 1500, z = -40, radius = 45, startOwner = "East" },
		{ id = "HQE", name = "Rail Station", x = 1800, z = 0, radius = 60, startOwner = "East", isHQ = true },
	} :: { Sector },
	-- Canal runs north-south between S3 and S4; crossings are the only way over.
	canal = {
		x = 1060,
		width = 24,
		crossings = {
			{ name = "Stone Bridge", z = 0, width = 16, vehicles = true },
			{ name = "Footbridge", z = 250, width = 5, vehicles = false },
			{ name = "Collapsed Lock", z = -280, width = 8, vehicles = false },
		},
	},
}

return table.freeze(Map1)
