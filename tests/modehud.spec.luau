--!strict
local R = require("../src/shared/Rules/ModeHud")

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

return {
	["slot: the viewer's own side always on the left"] = function()
		assert(R.slot(1, 5, "West") == 1 and R.slot(5, 5, "West") == 5)
		assert(R.slot(1, 5, "East") == 5 and R.slot(5, 5, "East") == 1)
		assert(R.slot(2, 7, nil) == 2, "no side: as the map lies")
	end,
	["fade: a steady step toward the target, never past it"] = function()
		assert(near(R.fade(0, 1, 0.05, 0.1), 0.5))
		assert(R.fade(0.9, 1, 0.05, 0.1) == 1, "stops at shown")
		assert(near(R.fade(1, 0, 0.025, 0.1), 0.75))
		assert(R.fade(0.1, 0, 0.05, 0.1) == 0, "stops at hidden")
		assert(R.fade(0, 1, 0.01, 0) == 1, "no fade time: at once")
	end,
	["pin: filled toward the side the control leans to, as far as it goes"] = function()
		local p = R.pin("West", 1, 0, 0)
		assert(p.fillSide == "West" and p.fill == 1 and p.state == "Held")
		p = R.pin("East", -0.4, 0, 0)
		assert(p.fillSide == "East" and near(p.fill, 0.4))
		p = R.pin("Neutral", 0, 0, 0)
		assert(p.fillSide == nil and p.fill == 0 and p.state == "Neutral", "a neutral sector: an empty diamond")
		p = R.pin("Neutral", 0.62, 3, 1)
		assert(p.fillSide == "West" and near(p.fill, 0.62) and p.state == "Neutral", "being taken from neutral")
	end,
	["pin: contested on even numbers, attacked when the holder is outnumbered"] = function()
		assert(R.pin("West", 0.5, 2, 2).state == "Contested")
		assert(R.pin("Neutral", 0, 1, 1).state == "Contested")
		assert(R.pin("West", 0.5, 0, 0).state == "Held", "an empty zone is not contested")
		assert(R.pin("West", 0.5, 1, 2).state == "Attacked")
		assert(R.pin("East", -0.5, 1, 0).state == "Attacked")
		assert(R.pin("East", -0.5, 0, 1).state == "Held", "defenders alone in their own zone")
	end,
	["zone line: the live zone's state as the viewer sees it"] = function()
		assert(R.zoneLine("Held", true, "Mira") == "HELD BY YOU")
		assert(R.zoneLine("Held", false, "Mira_K") == "HELD BY MIRA_K")
		assert(R.zoneLine("Contested", false, nil) == "CONTESTED")
		assert(R.zoneLine(nil, false, nil) == "ZONE FREE" and R.zoneLine("Free", false, nil) == "ZONE FREE")
	end,
	["leader line: the point leader and their score, the winner in the results"] = function()
		assert(R.leaderLine("Mira_K", false, 18, false) == "LEADER: MIRA_K (18)")
		assert(R.leaderLine("Mira_K", true, 18, false) == "LEADER: YOU (18)")
		assert(R.leaderLine(nil, false, 0, false) == "NO LEADER YET")
		assert(R.leaderLine("Mira_K", false, 40, true) == "MIRA_K WINS")
		assert(R.leaderLine("Mira_K", true, 40, true) == "YOU WIN")
		assert(R.leaderLine(nil, false, 0, true) == "NO WINNER")
	end,
}
