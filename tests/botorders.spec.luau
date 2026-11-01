--!strict
local R = require("../src/shared/Rules/BotOrders")

local function counts(list: { { number } }): { { West: number, East: number } }
	local out = {}
	for i, c in list do
		out[i] = { West = c[1], East = c[2] }
	end
	return out
end

local OWNER = { "West", "West", "Neutral", "East", "East" }
local REST = { 1, 1, 0, -1, -1 }

return {
	["plan: all attack the target while no own sector is under attack"] = function()
		local p = R.plan("West", OWNER, REST, counts({ { 3, 0 }, { 2, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.attack == 3 and p.defend == nil and p.share == 0)
	end,
	["plan: an own sector the enemy leads in, or is draining, is defended"] = function()
		local p = R.plan("West", OWNER, REST, counts({ { 0, 0 }, { 1, 2 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == 2 and p.share == 0.5 and p.attack == 3)
		local control = { 1, 0.7, 0, -1, -1 }
		p = R.plan("West", OWNER, control, counts({ { 0, 0 }, { 3, 1 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == 2, "fewer enemies, but the control is slipping")
		p = R.plan("West", OWNER, REST, counts({ { 0, 0 }, { 3, 1 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == nil, "held firmly by more defenders")
	end,
	["plan: the sector with most enemies, the frontmost on a tie; East counts from its own end"] = function()
		local p = R.plan("West", OWNER, REST, counts({ { 0, 3 }, { 0, 1 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == 1)
		p = R.plan("West", OWNER, REST, counts({ { 0, 2 }, { 0, 2 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), 3, 0.5)
		assert(p.defend == 2, "frontmost on a tie")
		p = R.plan("East", OWNER, REST, counts({ { 0, 0 }, { 0, 0 }, { 0, 0 }, { 2, 0 }, { 2, 0 } }), 3, 0.5)
		assert(p.defend == 4, "East's front is S4")
	end,
	["plan: no target left, everyone defends"] = function()
		local p = R.plan("West", OWNER, REST, counts({ { 0, 2 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }), nil, 0.5)
		assert(p.attack == nil and p.defend == 1 and p.share == 1)
	end,
	["defenders: rounded share, at least one, never all while attacking"] = function()
		assert(R.defenders(20, 0.5, true) == 10)
		assert(R.defenders(3, 0.5, true) == 2)
		assert(R.defenders(2, 0.1, true) == 1)
		assert(R.defenders(2, 0.99, true) == 1)
		assert(R.defenders(1, 0.5, true) == 0)
		assert(R.defenders(5, 0, true) == 0)
		assert(R.defenders(5, 1, false) == 5)
	end,
	["assign: keeps current defenders first, moves as few as it can"] = function()
		local ids = { 1, 2, 3, 4 }
		local a = R.assign(ids, { [3] = "Defend", [4] = "Defend" }, 1)
		assert(a[3] == "Defend" and a[4] == "Attack" and a[1] == "Attack" and a[2] == "Attack")
		a = R.assign(ids, { [3] = "Defend" }, 2)
		assert(a[3] == "Defend" and a[1] == "Defend" and a[2] == "Attack" and a[4] == "Attack")
		a = R.assign(ids, {}, 0)
		for _, id in ids do
			assert(a[id] == "Attack")
		end
	end,
}
