--!strict
-- Out-of-bounds walls: red force-field panels that fade in as a player approaches.
local Boundary = {
	-- One wall per side, fading as one (user 2026-10-18: "one solid object so it doesnt look like multiple blocks";
	-- was 40-stud panels fading each on its own). A part can't be longer than 2048 studs, so a longer side is cut into
	-- equal pieces of at most this, all fading together by the distance to the whole side.
	MaxPieceLength = 2000,
	BottomY = -40,
	TopY = 90,
	FadeFar = 90, -- invisible beyond this distance
	FadeNear = 8, -- fully visible at or within this distance
	MaxOpacity = 0.65,
	ColorRGB = { 255, 60, 50 },
	UpdateHz = 15,
	Tag = "BoundaryPanel",
}

return table.freeze(Boundary)
