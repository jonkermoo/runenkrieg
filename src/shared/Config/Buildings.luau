--!strict
-- Natural building styles (references/village). Sizes in studs: width = frontage along the road,
-- depth = front to back. Buildings are not built yet: they will be restyled to the flat-color look
-- (Config/Palette), but these sizes already reserve their lots in Rules/Village. "finish" names are
-- placeholders for palette colors; "class" is the destruction material class (Config/Destruction).

export type Finish = { finish: string, class: string }

local Buildings = {
	RoofOverhang = 1.2,
	FoundationMaterial = "Cobblestone",

	Styles = {
		-- Ref 1: brick or whitewashed two-story cottages, steep tiled roofs, chimneys, dormers.
		Cottage = {
			width = { 22, 26 },
			depth = { 14, 18 },
			stories = { 1, 2, 2 }, -- picked by hash
			storyHeight = 12,
			roofPitch = 42,
			walls = {
				{ finish = "Brick", class = "Brick" },
				{ finish = "Whitewash", class = "Plaster" },
				{ finish = "Whitewash", class = "Plaster" },
			},
			roofs = { "ClayTile", "DarkTile" },
			chimneys = { 1, 2 },
			dormerChance = 0.5,
		},
		-- Ref 1: weatherboarded cottages, white or tarred dark boards.
		Weatherboard = {
			width = { 22, 24 },
			depth = { 12, 16 },
			stories = { 1, 2 },
			storyHeight = 12,
			roofPitch = 38,
			walls = { { finish = "WhiteBoard", class = "Wood" }, { finish = "TarBoard", class = "Wood" } },
			roofs = { "DarkTile", "Slate" },
			chimneys = { 1 },
			dormerChance = 0.2,
		},
		-- Ref 2: identical single-story whitewashed row houses with low tiled roofs.
		Row = {
			width = { 20, 20 },
			depth = { 14, 14 },
			stories = { 1 },
			storyHeight = 12,
			roofPitch = 28,
			walls = { { finish = "Whitewash", class = "Plaster" } },
			roofs = { "DarkTile" },
			chimneys = { 1 },
			dormerChance = 0,
		},
		Church = {
			width = { 36, 36 },
			depth = { 20, 20 },
			stories = { 1 },
			storyHeight = 20,
			roofPitch = 45,
			walls = { { finish = "Limestone", class = "Stone" } },
			roofs = { "Slate" },
			chimneys = { 0 },
			dormerChance = 0,
			tower = { size = 12, height = 46, platformHeight = 34 },
		},
		Station = {
			width = { 44, 44 },
			depth = { 16, 16 },
			stories = { 1 },
			storyHeight = 12,
			roofPitch = 25,
			walls = { { finish = "Brick", class = "Brick" } },
			roofs = { "Slate" },
			chimneys = { 2 },
			dormerChance = 0,
		},
		Farmhouse = {
			width = { 24, 24 },
			depth = { 16, 16 },
			stories = { 2 },
			storyHeight = 12,
			roofPitch = 40,
			walls = { { finish = "Whitewash", class = "Plaster" } },
			roofs = { "ClayTile" },
			chimneys = { 2 },
			dormerChance = 0,
		},
		Barn = {
			width = { 30, 30 },
			depth = { 18, 18 },
			stories = { 1 },
			storyHeight = 16,
			roofPitch = 35,
			walls = { { finish = "BarnBoard", class = "Wood" } },
			roofs = { "DarkTile" },
			chimneys = { 0 },
			dormerChance = 0,
		},
		Shed = {
			width = { 12, 12 },
			depth = { 10, 10 },
			stories = { 1 },
			storyHeight = 10,
			roofPitch = 30,
			walls = { { finish = "TarBoard", class = "Wood" } },
			roofs = { "DarkTile" },
			chimneys = { 0 },
			dormerChance = 0,
		},
	},

	-- Which styles appear along which kind of road, picked by hash.
	RoadStyles = {
		Main = { "Cottage", "Cottage", "Weatherboard" },
		Lane = { "Cottage", "Weatherboard", "Weatherboard" },
		Row = { "Row" },
	},
}

return table.freeze(Buildings)
