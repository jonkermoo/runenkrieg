--!strict
-- Teammates' health over their heads (user 2026-11-03: "can we add teammate HP being visible (when close) when holding
-- M?"). While the map key is held (Config/Settings Key_Map, with the map and the teammate dots: src/client/ModeHud),
-- each teammate in Range (players and bots; Rules/Teams) gets a small bar over the head: knocked down it turns red with
-- Down over it, hurt enough for a bandage (Config/Healing.MedPackFrom) amber, so a medic finds who needs them.
-- Client only (src/client/TeamHealth, Rules/TeamHealth); colours in Config/Palette.UI.Hud health*. Data only.

local TeamHealth = {
	Range = 80, -- studs from your root to a teammate's root
	Refresh = 0.2, -- seconds between looks at the teammates (health is the Humanoid's own, already replicated)
	-- the bar: pixels wide x tall, its dark edge, studs above the head's centre (under the teammate dot,
	-- Config/ModeHud.Dot.above); the Down word's pixels over it
	Bar = { width = 44, height = 6, edge = 1, above = 2.3 },
	Down = { text = "DOWN", size = 12, tall = 14 },
}

return table.freeze(TeamHealth)
