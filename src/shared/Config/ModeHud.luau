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
	-- Point Capture: the move warning, the results line ("<NAME> WINS"), how many names on the board
	Warning = "THE ZONE MOVES IN %d",
	BoardTitle = "TOP SCORES",
	BoardSize = 3,
}

return table.freeze(ModeHud)
