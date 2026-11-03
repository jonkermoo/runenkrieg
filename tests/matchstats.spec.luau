--!strict
local R = require("../src/shared/Rules/MatchStats")
local Cfg = require("../src/shared/Config/Results")
local Table = require("../src/shared/Config/Cutscenes").Table

local rows = {
	{ id = 1, name = "Kessel", kit = "uniform2", Kills = 27, Healed = 0, Built = 400, Points = 900 },
	{ id = 2, name = "Maxwell", kit = "uniform1", Kills = 4, Healed = 1840, Built = 0, Points = 900 },
	{ id = 3, name = "Grabenbau", kit = "uniform2", Kills = 27, Healed = 10, Built = 6215.4, Points = 300 },
	{ id = 4, name = "Me", kit = "uniform1", Kills = 1, Healed = 0, Built = 0, Points = 50 },
}

return {
	["honours: most kills, HP healed and HP built; a tie to the name first in the alphabet"] = function()
		local k = R.best(rows, "Kills")
		assert(k and k.name == "Grabenbau" and k.value == 27, "27 each: Grabenbau before Kessel")
		local h = R.best(rows, "Healed")
		assert(h and h.name == "Maxwell" and h.value == 1840 and h.kit == "uniform1")
		local b = R.best(rows, "Built")
		assert(b and b.name == "Grabenbau" and b.value == 6215, "rounded HP")
		assert(R.best(rows, "Nothing") == nil and R.best({}, "Kills") == nil, "nobody: no honour")
	end,
	["FFA standings: the top few by points, you added with your place (user 2026-10-31, F1)"] = function()
		local s = R.standings(rows, "Points", 2, 4)
		assert(#s == 3, "two and you")
		assert(s[1].name == "Kessel" and s[2].name == "Maxwell" and s[1].place == 1, "900 each: by name")
		assert(s[3].name == "Me" and s[3].place == 4 and s[3].me)
		local all = R.standings(rows, "Points", Cfg.Standings, 1)
		assert(#all == 4 and all[1].me and not all[2].me, "you in the top: once")
	end,
	["the replay: each capture in turn, done before the next match (user 2026-10-31)"] = function()
		local r = Cfg.Replay
		local n = 6
		assert(R.replayAt(1, n, r.seconds, r.lead, r.tail) == r.lead)
		local last = R.replayAt(n, n, r.seconds, r.lead, r.tail)
		assert(math.abs(last - (r.seconds - r.tail)) < 1e-9)
		assert(
			last + r.draw <= r.seconds and r.seconds < Table.most,
			"the last arrow drawn while the battle table is shown"
		)
		assert(R.replayAt(1, 1, r.seconds, r.lead, r.tail) == r.lead, "one capture")
		-- a long match: its last few captures, a point taken back and forth timed once (its latest)
		local log = {}
		for k = 1, 12 do
			table.insert(log, { index = if k % 2 == 0 then 3 else k % 5 + 1, t = k })
		end
		local shown, timed = R.replayLog(log, 8)
		assert(#shown == 8 and shown[1].t == 5 and shown[8].t == 12, "the last 8")
		local seen = {}
		for k = #shown, 1, -1 do
			if timed[k] then
				assert(not seen[shown[k].index], "one time a point")
				seen[shown[k].index] = true
			end
		end
		assert(timed[8] and seen[3], "the latest at the point is timed")
		local few = R.replayLog({ { index = 2 } }, 8)
		assert(#few == 1, "a short match whole")
	end,
	["the match clock"] = function()
		assert(R.clock(872) == "14:32" and R.clock(5) == "0:05" and R.clock(-3) == "0:00")
	end,
}
