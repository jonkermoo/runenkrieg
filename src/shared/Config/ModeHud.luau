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
	-- Territory Push: in play the bar shows only while this key is held, with a dot over each teammate seen through
	-- walls (on the loadout screen it always shows); both fade in and out in FadeSeconds
	ShowKey = Enum.KeyCode.V,
	FadeSeconds = 0.12,
	Dot = { size = 10, above = 3.2 }, -- the teammate dot: pixels across, studs above the head's centre
	-- the open points' world marker (its diamond is the spec's PinHQ, its label PinLabel): pixels wide x tall, studs
	-- above the flagpole's top
	Marker = { size = { 44, 52 }, above = 3 },
	-- Point Capture: the move warning
	Warning = "THE ZONE MOVES IN %d",
}

return table.freeze(ModeHud)
