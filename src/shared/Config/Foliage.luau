--!strict
-- Client grass tufts (replaces Roblox terrain grass decoration, which cannot be controlled per player).
-- Tufts spawn only on Grass/LeafyGrass terrain around the camera, chunk by chunk, by quality level.

local Foliage = {
	ChunkSize = 32, -- studs; tufts are generated per chunk and cached
	Cell = 3, -- candidate grid inside a chunk (one candidate per cell)
	Materials = { "Grass", "LeafyGrass" }, -- terrain materials that grow grass
	Sink = 0.15, -- studs below the surface so tuft bases never float
	ScaleRange = { 0.8, 1.35 },
	UpdateHz = 4, -- how often chunk loading re-checks the camera position

	-- Quality levels. density = chance a cell gets a tuft; radius = draw distance in studs;
	-- swayRadius = tufts this close sway in the wind (0 = no sway).
	-- Sparser and further (user 2026-10-17: "grass is not rendering that far ... simpler and less thick"; was .25 / 60,
	-- .45 / 90, .7 / 130): with the thinner blades below, about as many parts in all as before.
	Levels = {
		Off = { density = 0, radius = 0, swayRadius = 0 },
		Low = { density = 0.12, radius = 100, swayRadius = 0 },
		Medium = { density = 0.22, radius = 150, swayRadius = 20 },
		High = { density = 0.32, radius = 200, swayRadius = 35 },
	},
	Order = { "Off", "Low", "Medium", "High" },

	Sway = { amp = 6, freq = 0.8 }, -- degrees, Hz (shares GlobalWind direction with trees)

	-- After a blast (src/client/GrassFoliage) the tufts on the churned ground go at once; then, `after` s later (once
	-- the voxels have arrived), any within the churn radius plus `margin` studs whose ground no longer grows grass.
	Scrub = { after = { 0.5, 3 }, margin = 4 },

	-- Thin, flowy blade patches (Config/Assets GrassBlades) as a second layer: they replace Roblox's terrain grass
	-- decoration (turned off in the place: Terrain -> Decoration), which the user liked but found too dense; it has
	-- no density setting (user 2026-10-14: "less spaced together maybe cut like half the amount"). Same fields as
	-- above; `Salt` keeps its cells apart from the tufts'. Same GrassQuality setting.
	Blades = {
		ChunkSize = 32,
		Cell = 2, -- 16 x 16 candidates per chunk
		Salt = 1000,
		Materials = { "Grass", "LeafyGrass" },
		Sink = 0.1,
		ScaleRange = { 0.85, 1.3 },
		Levels = {
			Off = { density = 0, radius = 0, swayRadius = 0 },
			-- fuller (user 2026-10-14: "add some more grass, i just dont want missing patches"; was .2 / .32 / .42)
			-- thinner (user 2026-10-17: "less thick"; was .45 / .65 / .8), still near the camera only
			Low = { density = 0.3, radius = 55, swayRadius = 0 },
			Medium = { density = 0.45, radius = 75, swayRadius = 25 },
			High = { density = 0.55, radius = 95, swayRadius = 40 },
		},
		UpdateHz = 4,
		Sway = { amp = 9, freq = 0.9 }, -- thin blades bend further than the tufts
	},
}

return table.freeze(Foliage)
