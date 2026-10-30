--!strict
-- Frontline sectors on the map (user 2026-10-27): the invisible blocks dividing the sectors and the markers showing
-- where each sector's capture point is. Where they go is per map (Config/Maps/*: sectors, dividers); the maths is
-- Rules/Sectors; built by src/dev/Greybox. Seen while editing; in play the server shows them only while Workspace's
-- ShowAttribute is on (src/server/Sectors), which the admin panel switches.
local Sectors = {
	Divider = {
		BottomY = -40, -- under the deepest ground and river bed
		TopY = 120, -- over the highest ground in the bounds
		Thickness = 1,
		-- a river divider follows the river's middle line in this many straight pieces, south edge to north edge
		RiverSegments = 16,
		ColorRGB = { 200, 30, 140 },
		EditTransparency = 0.6,
		Tag = "SectorDivider",
	},
	Marker = {
		DiscHeight = 0.6, -- the capture area, a flat disc of the sector's radius on the ground at its point
		DiscLift = 0.3, -- above the ground at the point
		PoleWidth = 2, -- a pole on the point, so it's seen from afar while editing
		PoleHeight = 40,
		-- by the side that holds the sector at the start
		ColorRGB = { West = { 60, 100, 200 }, East = { 190, 50, 50 }, Neutral = { 220, 150, 30 } },
		EditTransparency = 0.5,
		LabelSize = { 120, 40 }, -- the id over the pole (BillboardGui, px)
		Tag = "SectorMarker",
	},
	-- In play they're shown while this Workspace attribute is on (the admin panel's switch). Each mode change sets it
	-- afresh: on in the DEV place while ShowInDevPlay is on, except in Normal mode (user 2026-10-27: "in normal mode
	-- the borders for territories and sectors arent visible. make it a toggleable thing in admin"); off elsewhere.
	ShowAttribute = "ShowSectors",
	ShowInDevPlay = true,
	DevPlaceId = 103459731368962, -- Runenkrieg [DEV] (roblox.json)
}

return table.freeze(Sectors)
