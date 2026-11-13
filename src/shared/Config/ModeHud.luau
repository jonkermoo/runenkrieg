--!strict
-- The game modes' top bar (src/client/ModeHud, src/shared/ui/ModeHud.json, Rules/ModeHud; user 2026-10-29, option B
-- of the mode HUD drafts). Sizes are the spec's; colours Config/Palette UI.Hud.
local ModeHud = {
	-- Territory Push's replicated state: this Workspace folder (src/server/Frontline's Config/Frontline.FolderName)
	FrontlineFolder = "Frontline",
	Refresh = 0.1, -- seconds between the bar's updates
	FlashSeconds = 0.35, -- a contested diamond's edge flashes between pinContested and pinEdge
	Fill = { min = 0.002, edge = 0.001 }, -- a diamond's fill: the least share drawn, the width of its hard edge
	-- Territory Push's results line (Workspace.Frontline's Phase "Results"): with a winner, "<NATION> WINS"
	NoWinner = "MATCH OVER",
	-- Territory Push: in play the bar shows only while the map key is held (Config/Settings Key_Map, M: user 2026-10-31
	-- "V and map conflicts. make it holding m"), with a dot over each teammate seen through walls (on the loadout
	-- screen it always shows); both fade in and out in FadeSeconds
	FadeSeconds = 0.12,
	-- in play the front bar stays on as a strip (review 2026-11-12): this share of its size, this opaque
	Strip = { scale = 0.7, shown = 0.85 },
	-- the teammate dot: pixels across, studs above the head's centre; full size up to `near` studs from the camera,
	-- then smaller with distance down to `min` pixels (Rules/ModeHud.dotSize)
	Dot = { size = 10, above = 3.2, near = 25, min = 4 },
	-- the open points' world beacon (src/client/PointSeal's seal, as on the sketch map; its label the spec's PinLabel):
	-- pixels wide x tall, studs above the flagpole's top, the seal's size and ring, the capture bar's width x height
	Marker = { size = { 56, 70 }, above = 3, seal = 38, ring = 3, bar = { 34, 4 } },
	-- Territory Push: the countdown while the soldier stands frozen in its wave line (user 2026-11-01: players who deploy
	-- "just stand in the spawn until the wave unlocks, with no idea when the countdown ends"): this line over the
	-- seconds left (ModeHud.json WaveBar)
	Wave = { title = "YOUR WAVE MOVES OUT IN" },
	-- Point Capture: the move warning
	Warning = "THE ZONE MOVES IN %d",
}

return table.freeze(ModeHud)
