--!strict
local R = require("../src/shared/Rules/ModeHud")

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-9
end

return {
	["front: the share of the chain West holds, a neutral sector half"] = function()
		assert(near(R.front({ 1, 1, 0, -1, -1 }), 0.5))
		assert(near(R.front({ 1, 1, 1, 1, 1 }), 1))
		assert(near(R.front({ -1, -1, -1, -1, -1 }), 0))
		assert(near(R.front({ 1, 1, 0.5, -1, -1 }), 0.55), "slides with the fought-over sector's control")
		assert(near(R.front({}), 0.5))
		assert(near(R.front({ 3, -3 }), 0.5), "control out of range is clamped")
	end,
	["slot and front: the viewer's own side always on the left"] = function()
		assert(R.slot(1, 5, "West") == 1 and R.slot(5, 5, "West") == 5)
		assert(R.slot(1, 5, "East") == 5 and R.slot(5, 5, "East") == 1)
		assert(R.slot(2, 7, nil) == 2, "no side: as the map lies")
		assert(near(R.seenFront(0.3, "East"), 0.7) and near(R.seenFront(0.3, "West"), 0.3))
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
	["zone line and look: the live zone's state as the viewer sees it"] = function()
		assert(R.zoneLine("Held", true, "Mira") == "HELD BY YOU")
		assert(R.zoneLine("Held", false, "Mira_K") == "HELD BY MIRA_K")
		assert(R.zoneLine("Contested", false, nil) == "CONTESTED")
		assert(R.zoneLine(nil, false, nil) == "ZONE FREE" and R.zoneLine("Free", false, nil) == "ZONE FREE")
		assert(R.zoneLook("Held", true) == "Mine" and R.zoneLook("Held", false) == "Theirs")
		assert(R.zoneLook("Contested", false) == "Contested" and R.zoneLook("Free", false) == "Free")
	end,
}
