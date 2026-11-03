--!strict
-- Teammates' health as an outline (user 2026-11-03: "can we make team health a colored outline on your teammates?"):
-- each living teammate in sight (a soldier of your kit, players and bot soldiers; nobody in a free-for-all) gets a
-- Highlight on this client only, its outline shaded by health (Palette.UI.TeamOutline), no fill. Rules/TeamOutline,
-- src/client/TeamOutline. Data only.

local TeamOutline = {
	-- Roblox draws at most 31 Highlights on a screen at once and a match holds up to 100 soldiers: only this many
	-- nearest teammates are outlined, the rest left for the game's other Highlights (the build focus, the point
	-- leader's glow, ...)
	MaxOutlines = 24,
	-- teammates farther than this (studs, from the camera) get none (the M map's dots find the far ones)
	MaxDistance = 400,
	-- how often the outlined set and their colours are picked again (seconds)
	Rate = 0.1,
	-- the outline: its transparency, its fill (1 = none), "Occluded" = only where they're in sight ("AlwaysOnTop":
	-- through walls too)
	OutlineTransparency = 0,
	FillTransparency = 1,
	DepthMode = "Occluded",
	-- on the local Player, set by the admin panel (client only): outlines off; your own character outlined too (to
	-- see the colours alone in a test with the "Health" buttons)
	OffAttribute = "DevTeamOutlinesOff",
	SelfAttribute = "DevTeamOutlineSelf",
}

return table.freeze(TeamOutline)
