--!strict
-- Player squads (user 2026-11-06: "add an extra panel that let's players join a squad, which always leaves an indicator
-- above your squad mate. make squads max 6. it should also include the status of the squad"). Players only: bots keep
-- their own squads (src/server/Bots, the Commander; user 2026-11-06 "Players only"). Rules/Squads decides,
-- src/server/Squads keeps who is in which squad, src/client/SquadPanel shows the panel (src/shared/ui/SquadPanel.json)
-- and src/client/SquadMarkers the marker over each squadmate. Data only.
-- A squad belongs to one team (the kit its members fight in, Rules/Teams) and is named after its rune. A player's
-- squad is their "Squad" attribute ("<kit>:<number>"); the server also writes the team they can join squads on as
-- "SquadTeam" (none in a free-for-all). Leaving the team (a team change, a new match's sides) leaves the squad; an
-- emptied squad is gone.

local Squads = {
	Max = 6, -- soldiers in a squad
	-- one rune per squad, in the order new squads take them (the lowest free first); also the most squads per team
	Names = { "fehu", "uruz", "thurisaz", "ansuz", "raidho", "kaunan", "gebo", "wunjo" },
	Attribute = "Squad", -- on the Player (and, for the admin's test mates, on a bot's or dummy's model)
	TeamAttribute = "SquadTeam", -- on the Player: the team whose squads it may join
	NameAttribute = "SquadMate", -- on a test mate's model (src/server/Squads.fill): the name shown over it
	Check = 0.5, -- seconds between the server's team checks
	AskGap = 0.3, -- seconds between a player's squad requests the server takes (rate limit)

	-- Each member's status (Rules/Squads.status), in the order checked: the words and the panel's ink
	-- (Palette.UI.Grimoire.Notebook names). Fallen: dead, the body still down; Down: alive but knocked down (ragdolled);
	-- Wave: standing in the wave line (the character's Config/Frontline.HoldAttribute); In action:
	-- alive in the field; Awaiting: no soldier in the field (in the loadout menu).
	Status = {
		Fallen = { text = "Fallen", ink = "pencil" },
		Down = { text = "Down", ink = "pencil" },
		Wave = { text = "Waiting for the wave", ink = "wave" },
		Action = { text = "In action", ink = "text" },
		Awaiting = { text = "Awaiting deployment", ink = "textDim" },
	},
	Open = "Open slot", -- an empty place in your squad

	-- The panel (src/client/SquadPanel): opened by the loadout menu's Squad button or the Squad key (Config/Settings
	-- Key_Squad); refreshed every `Refresh` seconds while open.
	Panel = { DisplayOrder = 11, Refresh = 0.5 }, -- (over the loadout menu and the HUD, beside the settings menu)

	-- The marker over each squadmate (src/client/SquadMarkers): a BillboardGui drawn over everything (AlwaysOnTop, no
	-- distance limit), `Above` studs over the head, the same size at any range: a diamond `Diamond` px square with an
	-- ink edge (`Edge` px) in the squad colour (Palette.UI.Squad: `mate`, `down` when knocked down), the name in `TextSize`
	-- px over it. Hidden for the fallen, during the match cutscenes and while the admin panel hides the game HUD.
	Marker = { Above = 2.2, Diamond = 13, Edge = 2, TextSize = 14, Width = 160, Height = 40 },

	-- Admin panel (Config/DevTools, game rule 8): "Fill squad" makes up to Max - 1 of your team's nearest bot soldiers
	-- (or dummies) test mates of your squad for markers and statuses (shown, never ordered); "Clear test mates" drops them.
	Fill = { range = 2000 },
}

return table.freeze(Squads)
