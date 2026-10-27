--!strict
-- Zone capture, free-for-all (user 2026-10-27: "players must be in various areas of the map to gain points, only 1
-- player can be in the zone at a time"): one zone is live at a time and moves between a map's spots (Config/Maps/*
-- .zoneMatch); a soldier alone in it, alive and on their feet, scores; two or more in it contest it and nobody scores.
-- Timed matches, everyone an enemy (Rules/Teams). Rules/ZoneMatch is the maths, src/server/ZoneMatch runs it,
-- src/client/ZoneMarker colours the zone for each viewer.
local ZoneMatch = {
	Radius = 10, -- studs, across the ground
	Height = 8, -- how far above or below the zone's ground a soldier still counts as in it
	PointsPerSecond = 1,
	MoveEvery = 60, -- seconds a spot stays live
	Warning = 10, -- seconds before a move the next spot is marked
	MatchSeconds = 480,
	ResultsSeconds = 10, -- the results, then the next match
	Tick = 0.2, -- seconds between the server's occupancy checks
	SpawnZoneClear = 60, -- spawn at least this far from the live zone (unless no spawn point is)
	-- the marker (built by the server, coloured per viewer by the client): a ring of `Segments` blocks on the ground
	-- round the zone, a post with a pennant at its centre
	Marker = {
		Segments = 28,
		RingWidth = 1.2,
		RingHeight = 0.25,
		PostHeight = 7,
		PostWidth = 0.5,
		Pennant = { 2.4, 1.4, 0.15 },
		NextTransparency = 0.6, -- the next spot's ring, during the warning
		FlashSeconds = 0.35, -- contested: flashes between its colour and Free
		Colors = {
			Free = { 196, 192, 180 },
			Mine = { 90, 170, 90 },
			Theirs = { 196, 70, 58 },
			Contested = { 230, 160, 40 },
			Post = { 98, 74, 58 },
		},
	},
	-- replicated state: attributes on the marker Model (Phase, State, Holder (a UserId), Spot, NextSpot, MoveAt,
	-- EndsAt (workspace:GetServerTimeNow())) and each Player's score
	ScoreAttribute = "ZoneScore",
	-- on Workspace while a match runs: everyone is everyone's enemy (Rules/Teams), whatever their uniform
	FreeForAllAttribute = "FreeForAll",
	MarkerName = "Zone",
	NextMarkerName = "NextZone",
}

return table.freeze(ZoneMatch)
