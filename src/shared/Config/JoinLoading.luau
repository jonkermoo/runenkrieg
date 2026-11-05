--!strict
-- Loading a whole map on this client (src/client/MapLoader, Rules/JoinLoading; user 2026-11-04: "the main menu should
-- not even be visible until the current map is done loading", then "every map is fully loaded before anyone plays"):
-- on joining (behind the Runenkrieg loading screen and the armory, src/client/Menus + EndScenes) and in the armory
-- after a vote (src/client/MatchCutscene). The server keeps the live map streamed in for every player
-- (src/server/MapFocus: replication foci over it, each holding Workspace.StreamingMinRadius round it), the client asks
-- for each spot of a grid over it, then preloads its meshes, textures and decals and waits for the download queue.
-- Every wait is on a real signal; the per-step caps only stop one stuck request from hanging the whole load.
return table.freeze({
	-- Workspace.StreamingMinRadius (default.project.json sets the same; tests/joinloading checks): what lies this
	-- close to a replication focus never streams out
	MinRadius = 600,
	FocusMargin = 200, -- studs past the map's bounds the foci cover too (the forest and hills seen from it)
	FocusFolder = "MapFocus", -- Workspace folder of the foci's parts (unseen, no collisions, no hits)
	Spacing = 400, -- studs at the most between the spots streamed in across the map's bounds
	StreamWait = 8, -- seconds at the most one spot's stream request may take (the engine's own timeout)
	Batch = 40, -- assets preloaded at a time
	DrainWait = 20, -- seconds at the most for the download queue to empty once everything is preloaded
	Hold = 0.4, -- seconds the full bar stays before the title screen's buttons
	Reveal = 1.2, -- seconds the black takes to clear off the armory once its set stands
	-- the server's count of the map's parts (a Model attribute set by src/server/MapFocus) against what this client
	-- holds: the load waits until it holds this share of them, `HeldWait` seconds at the most (destruction and
	-- streaming detail keep the two from matching exactly)
	PartsAttribute = "LoadParts",
	HeldShare = 0.97,
	HeldWait = 20,
	-- admin (src/client/DevAdminMenu): a slow load, seconds added to each step of this client's own load (a
	-- LocalPlayer attribute; never replicated)
	SlowAttribute = "DevSlowLoad",
	SlowSteps = { 0, 0.5, 2 },
})
