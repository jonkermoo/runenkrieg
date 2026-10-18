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
	-- Flat colour (user 2026-10-18): ForceField's shimmer didn't show on one long wall (Studio: invisible head-on).
	Material = "SmoothPlastic",
	MaxOpacity = 0.45,
	-- drawn this thin (a BlockMesh's scale; it still blocks 1 stud thick): the see-through end faces where a side's two
	-- pieces meet doubled up into a bright stripe (Studio 2026-10-18)
	DrawnThickness = 0.02,
	-- The walls stop characters only: in their own collision group, which collides with nothing else, so every
	-- raycast and spherecast (aims, bullets, staff beams, shells) passes through (user: "shells and magic can go outside
	-- the map"). CanQuery off alone doesn't do it: Roblox ignores it while CanCollide is on.
	CollisionGroup = "Boundary",
	Blocks = { "Characters" },
	ColorRGB = { 255, 60, 50 },
	UpdateHz = 15,
	Tag = "BoundaryPanel",
}

return table.freeze(Boundary)
