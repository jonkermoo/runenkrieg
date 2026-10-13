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
	-- Buildings: copies of one template pick a color per role (walls/roof/trim/door) from these, so
	-- repeated shapes read as different houses. Muted, earthy, desaturated (Pordier-like; old English
	-- villages in references/village). Each wall/roof piece is also shaded a few % off by its Tone.
	Buildings = {
		Walls = {
			Whitewash = { 222, 216, 200 },
			Cream = { 212, 198, 168 },
			Ochre = { 196, 170, 124 },
			Stone = { 172, 164, 146 },
			Brick = { 148, 98, 78 },
			RedBrick = { 132, 84, 68 },
			BarnRed = { 126, 72, 58 },
			TarBoard = { 76, 68, 62 },
			WhiteBoard = { 212, 206, 190 },
		},
		Roofs = {
			Thatch = { 158, 128, 84 },
			ThatchDark = { 122, 98, 66 },
			ThatchWeathered = { 136, 124, 100 },
			DarkTile = { 90, 78, 72 },
			Slate = { 84, 86, 92 },
			RedTile = { 138, 86, 68 },
		},
		Trim = { { 82, 66, 54 }, { 104, 86, 68 }, { 70, 60, 54 } }, -- dark weathered wood
		Doors = { { 112, 88, 64 }, { 80, 92, 72 }, { 112, 62, 52 }, { 84, 92, 102 } },
		Floor = { 120, 96, 72 },
		Stairs = { 110, 88, 66 },
		Foundation = { 118, 114, 106 }, -- plinth stones
		Quoin = { 150, 144, 130 }, -- corner stones
		Chimney = { 136, 112, 96 }, -- old stone/brick stack
		Glass = { 138, 160, 166 },
		GlassTransparency = 0.4,
		Metal = { 54, 52, 50 }, -- iron hinges, handles
		Sign = { 210, 196, 162 },
		Wood = { 104, 82, 62 },
		ToneJitter = 0.04, -- +-4% per piece: hand-made, not factory-flat
	},
	-- Village props (Config/Props), same muted, hand-made look as the houses.
	Props = {
		Stone = { 146, 140, 126 },
		StoneDark = { 118, 112, 100 },
		Wood = { 112, 88, 66 },
		WoodDark = { 84, 66, 52 },
		WoodPale = { 206, 198, 180 }, -- painted pickets
		Hedge = { 74, 108, 58 },
		HedgeDark = { 62, 92, 50 },
		Hay = { 182, 156, 96 },
		Metal = { 54, 52, 50 },
		Rubber = { 34, 32, 30 },
		Water = { 92, 124, 128 },
		Glass = { 120, 140, 146 },
		CarBodies = { { 72, 42, 40 }, { 40, 44, 42 }, { 56, 70, 58 }, { 62, 64, 72 } },
		ToneJitter = 0.05,
	},
	-- Magic (src/client/Vfx, Config/Vfx): the glowing spell colors. Effects draw them bright (LightEmission, HDR
	-- brightness) so the Bloom in Lighting makes them glow; still flat colors, no textures (docs/ART_STYLE.md).
	Magic = {
		Core = { 235, 250, 255 }, -- the white-hot centre of beams, orbs and flashes
		Glow = { 120, 200, 255 }, -- the light blue body (Zoltraak, the circle's lines)
		Deep = { 70, 90, 230 }, -- the deep blue edge
		Violet = { 150, 90, 255 }, -- the outer haze, sparkles
		Gold = { 255, 200, 80 }, -- light spikes, holy flashes
		Ember = { 255, 60, 50 }, -- red glints and bursts
		Bolt = { 80, 255, 190 }, -- lightning
		-- the violet "hex" scheme (user reference 2026-10-13: a hot pink-violet capsule beam)
		HexCore = { 255, 228, 255 },
		Hex = { 240, 90, 255 },
		HexDeep = { 170, 40, 220 },
		HexEdge = { 90, 20, 140 },
	},
	-- UI: flat panels, one outline thickness everywhere.
	UI = {
		panel = { 44, 50, 42 },
		button = { 64, 72, 60 },
		accent = { 120, 150, 80 },
		outline = { 24, 28, 22 },
		text = { 236, 232, 220 },
		stroke = 2,
		-- the ammo display (src/client/Firing): a live round, a spent case in the chamber, an empty slot
		round = { 196, 160, 84 },
		spent = { 96, 84, 62 },
		slot = { 30, 34, 28 },
	},
	Atmosphere = { color = { 206, 218, 226 }, decay = { 126, 146, 160 } },
}

return table.freeze(Palette)
