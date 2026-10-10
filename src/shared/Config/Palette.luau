--!strict
-- The art palette (docs/ART_STYLE.md). Flat colors only: every part is SmoothPlastic and terrain
-- materials are overridden with untextured MaterialVariants, so these RGB values ARE the look.
-- Tuned to references/style (semi-low-poly, soft olive greens, warm tan dirt, dark grey rock).

local Palette = {
	Terrain = {
		Grass = { 108, 142, 74 },
		LeafyGrass = { 94, 128, 66 }, -- under groves
		Ground = { 150, 126, 96 }, -- dirt patches, slopes, yards
		Sand = { 168, 146, 112 }, -- roads
		Mud = { 112, 94, 74 }, -- river bed
		Rock = { 98, 94, 90 },
	},
	Water = { color = { 72, 124, 134 }, transparency = 0.35, reflectance = 0, waveSize = 0.05 },
	Trees = {
		Pine = { { 48, 84, 62 }, { 56, 94, 66 }, { 44, 78, 58 } },
		Broadleaf = { { 88, 132, 64 }, { 100, 142, 70 }, { 80, 122, 58 } },
		Birch = { { 132, 160, 82 }, { 120, 150, 72 } },
		Bark = { 98, 74, 58 },
		BirchBark = { 214, 210, 196 },
	},
	-- Grass tufts: a few shades around the terrain grass so tufts read as part of the ground.
	GrassTufts = { { 112, 148, 74 }, { 100, 136, 68 }, { 124, 156, 80 }, { 94, 128, 64 } },
	-- Buildings: copies of one template pick a color per role (walls/roof/trim/door) from these,
	-- so repeated shapes still read as different houses while sharing one tone.
	Buildings = {
		Walls = {
			Whitewash = { 232, 228, 214 },
			Cream = { 226, 214, 186 },
			Sand = { 210, 192, 158 },
			Sage = { 172, 182, 152 },
			Stone = { 196, 190, 176 },
			Brick = { 162, 94, 74 },
			RedBrick = { 142, 80, 64 },
			WhiteBoard = { 222, 220, 208 },
			TarBoard = { 76, 66, 60 },
			BarnRed = { 140, 72, 58 },
		},
		Roofs = {
			Slate = { 76, 80, 88 },
			Terracotta = { 152, 86, 66 },
			Brown = { 106, 82, 68 },
			DarkTile = { 88, 76, 72 },
			Moss = { 98, 106, 86 },
		},
		Trim = { { 240, 236, 226 }, { 76, 66, 60 }, { 100, 76, 60 } },
		Doors = { { 100, 76, 60 }, { 72, 86, 66 }, { 122, 62, 54 }, { 62, 72, 88 } },
		Floor = { 124, 98, 74 },
		Stairs = { 112, 88, 66 },
		Foundation = { 130, 126, 118 },
		Chimney = { 142, 84, 66 },
		Glass = { 156, 190, 198 },
		GlassTransparency = 0.35,
		Metal = { 62, 62, 64 },
		Sign = { 222, 208, 172 },
		Wood = { 112, 86, 64 },
	},
	-- UI: flat panels, one outline thickness everywhere.
	UI = {
		panel = { 44, 50, 42 },
		button = { 64, 72, 60 },
		accent = { 120, 150, 80 },
		outline = { 24, 28, 22 },
		text = { 236, 232, 220 },
		stroke = 2,
	},
	Atmosphere = { color = { 206, 218, 226 }, decay = { 126, 146, 160 } },
}

return table.freeze(Palette)
