--!strict
-- The results screen at a match's end (src/client/Results, src/shared/ui/Results.json, Rules/MatchStats; user
-- 2026-10-31: Normal "R3 map table", FFA "F1 standings ledger"). Data only.
local Results = {
	-- Normal: the map replays the match's captures in order, each arrow drawn over `draw` seconds; the first `lead` in,
	-- the last done `tail` before `seconds`, which ends before the next match (Config/Frontline.ResultsSeconds; user:
	-- "the animation should be finished before the next match is ready")
	Replay = { seconds = 7, lead = 0.4, tail = 1.2, draw = 0.7 },
	-- an arrow: from `from` of the way from the neighbour it came from to the point it took, to `to`; bent `bend` of its
	-- length to one side (alternating), `thick` of the map's width; the head's two strokes `head` of its length, `spread`
	-- degrees off it; its time `stamp` of the map's width tall, `lift` of that over the arrow's bend
	Arrow = {
		from = 0.25,
		to = 0.86,
		bend = 0.18,
		thick = 0.009,
		head = 0.25,
		spread = 28,
		stamp = 0.036,
		lift = 0.9,
		steps = 12,
	},
	-- the winning capture ringed in red pencil, `ring` times the point's radius
	Win = { ring = 2.2, thick = 0.007 },
	-- FFA: the standings by score, the first `Standings` and you; each row's bar filling over `fill` seconds, one after
	-- another `stagger` apart from the first at `lead`
	Standings = 8,
	Ledger = { lead = 0.3, stagger = 0.6, fill = 0.8 },
	-- the honours, each with its rune (Config/Runes) and the word after the name
	Honours = {
		{ key = "Kills", rune = "tiwaz", word = "kills" },
		{ key = "Healed", rune = "berkanan", word = "HP healed" },
		{ key = "Built", rune = "algiz", word = "HP built" },
	},
	NoWinner = "NO VICTOR", -- a match ended with no winner (the admin's End match now)
	Takes = "TAKES THE FIELD",
	DisplayOrder = 7, -- over the loadout and title screens (src/client/Menus)
}

return table.freeze(Results)
