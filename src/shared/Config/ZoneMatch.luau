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
	-- the marker (built by the server, coloured per viewer by the client; user 2026-10-29: "make it more of a ring with a
	-- light beacon. make it look nice"): a glowing ring the zone's size laid over the ground (each corner on the ground
	-- under it, so it follows the slope), a dashed ring just inside it, and a beacon up from its middle (a bright core
	-- and a faint halo, both fading out into the sky, slowly breathing, a light on the ground under it); all of it hidden
	-- for this player while aiming (user 2026-10-27: "make it disappear when ADS"; src/client/ZoneMarker). The next
	-- spot: its rings only, fainter, during the warning.
	Marker = {
		Ring = { segments = 48, width = 0.7, height = 0.3, lift = 0.35, transparency = 0.05 },
		-- `inset` in from the ring; each dash `fill` of its share of the round
		Dashes = { count = 32, inset = 1.6, width = 0.3, height = 0.2, fill = 0.55, transparency = 0.3 },
		Beacon = {
			base = 0.6, -- over the ground at the middle
			height = 260,
			-- each layer's width and transparency at its foot and its top (a Beam's sides are hard: thin layers)
			core = { width = 0.6, foot = 0.05, top = 1 },
			halo = { width = 2.6, foot = 0.65, top = 1 },
			lightEmission = 1,
			pulseSeconds = 2.4, -- one breath
			pulse = 0.3, -- the widths swing this share either way
		},
		Light = { range = 22, brightness = 1.6, pulse = 0.35 },
		NextTransparency = 0.7, -- the next spot's rings
		FlashSeconds = 0.35, -- contested: flashes between its colour and Free
		Colors = {
			Free = { 236, 226, 196 },
			Mine = { 110, 220, 110 },
			Theirs = { 235, 80, 64 },
			Contested = { 255, 176, 40 },
		},
	},
	-- the point leader (user 2026-10-29: "whoever has the most points have a border/glow (just so they're obvious)"):
	-- a Highlight on their character, seen by everyone else where they're in sight (Rules/ZoneMatch.leader)
	Leader = {
		name = "LeaderGlow",
		fill = { 255, 206, 72 },
		fillTransparency = 0.75,
		outline = { 255, 236, 150 },
		outlineTransparency = 0,
		depthMode = "Occluded", -- "AlwaysOnTop": seen through walls too
	},
	LeaderAttribute = "Leader", -- on the marker: the leader's UserId (nil while nobody has a point)
	-- replicated state: attributes on the marker Model (Phase, State, Holder (a UserId), Leader, Spot, NextSpot, MoveAt,
	-- EndsAt (workspace:GetServerTimeNow())) and each Player's score
	ScoreAttribute = "ZoneScore",
	-- on Workspace while a match runs: everyone is everyone's enemy (Rules/Teams), whatever their uniform
	FreeForAllAttribute = "FreeForAll",
	MarkerName = "Zone",
	NextMarkerName = "NextZone",
}

return table.freeze(ZoneMatch)
