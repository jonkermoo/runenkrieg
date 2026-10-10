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
	Levels = {
		Off = { density = 0, radius = 0, swayRadius = 0 },
		Low = { density = 0.25, radius = 60, swayRadius = 0 },
		Medium = { density = 0.45, radius = 90, swayRadius = 20 },
		High = { density = 0.7, radius = 130, swayRadius = 35 },
	},
	Order = { "Off", "Low", "Medium", "High" },

	Sway = { amp = 6, freq = 0.8 }, -- degrees, Hz (shares GlobalWind direction with trees)
}

return table.freeze(Foliage)
