--!strict
-- Out-of-bounds walls: red force-field panels that fade in as a player approaches.
local Boundary = {
	PanelWidth = 40, -- each panel fades on its own, so only the nearby stretch lights up
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
