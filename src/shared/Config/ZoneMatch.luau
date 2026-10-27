--!strict
-- Zone capture, free-for-all (user 2026-10-27: "players must be in various areas of the map to gain points, only 1
-- player can be in the zone at a time"): one zone is live at a time and moves between a map's spots (Config/Maps/*
-- .zoneMatch); a soldier alone in it, alive and on their feet, scores; two or more in it contest it and nobody scores.
-- Timed matches, everyone an enemy (Rules/Teams). Rules/ZoneMatch is the maths, src/server/ZoneMatch runs it,
-- src/client/ZoneMarker colours the zone for each viewer.
local ZoneMatch = {
	Radius = 16, -- studs, across the ground (user 2026-10-27: "expand the capture area"; was 10)
	Height = 8, -- how far above or below the zone's ground a soldier still counts as in it
	PointsPerSecond = 1,
	MoveEvery = 60, -- seconds a spot stays live
	Warning = 10, -- seconds before a move the next spot is marked
	MatchSeconds = 480,
	-- a capture (user 2026-10-27: "holding a live spot alone for 10 s, once per spot per player"): seconds held alone
	-- while a spot is live, added up; once per player each time a spot goes live (paid by src/server/Loadouts)
	CaptureSeconds = 10,
	ResultsSeconds = 10, -- the results, then the next match
	Tick = 0.2, -- seconds between the server's occupancy checks
	SpawnZoneClear = 60, -- spawn at least this far from the live zone (unless no spawn point is)
	-- seconds a fresh spawn can't be hurt (or until it attacks: src/server/Damage.protect); it can't hold the zone meanwhile
	SpawnProtection = 3,
	SpawnLift = 3.2, -- a spawned root this far over the ground (standing)
	SpawnWait = 10, -- seconds a new character's root is waited for
	FeetBelowRoot = 3, -- a soldier's feet this far under the root (what counts as in the zone: Height round them)
	GroundRay = { top = 300, depth = 600 }, -- the ground found by a ray this high, this long, down on terrain only
	-- the marker (built by the server, coloured per viewer by the client; user 2026-10-27: "a translucent floating
	-- circle and ... a beam that reveals its location in the sky. make it disappear when ADS"): a see-through disc the
	-- zone's size floating `lift` over the highest ground under it, and a beam up from its middle; both hidden for
	-- this player while aiming (src/client/ZoneMarker). The next spot's disc only, fainter, during the warning.
	Marker = {
		Disc = { thickness = 0.2, lift = 0.8, transparency = 0.55, samples = 12 },
		Beam = { width = 1.6, height = 260, transparency = 0.45 },
		NextTransparency = 0.8,
		FlashSeconds = 0.35, -- contested: flashes between its colour and Free
		Colors = {
			Free = { 196, 192, 180 },
			Mine = { 90, 170, 90 },
			Theirs = { 196, 70, 58 },
			Contested = { 230, 160, 40 },
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
