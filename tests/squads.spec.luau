--!strict
local R = require("../src/shared/Rules/Squads")
local Cfg = require("../src/shared/Config/Squads")

local function eq(a: any, b: any, what: string)
	assert(a == b, `{what}: expected {tostring(b)}, got {tostring(a)}`)
end

return {
	["squads hold six and have a name per rune"] = function()
		eq(Cfg.Max, 6, "max")
		eq(R.name(Cfg, 1), "Fehu", "first")
		eq(R.name(Cfg, 5), "Raidho", "fifth")
		eq(R.name(Cfg, #Cfg.Names + 1), "?", "past the list")
		for _, rune in Cfg.Names do
			local Runes = require("../src/shared/Config/Runes") :: any
			assert(Runes[rune], `{rune} is a rune`)
		end
		for _, s in Cfg.Status do
			assert(type(s.text) == "string" and type(s.ink) == "string", "status words and ink")
		end
	end,
	["keys round trip"] = function()
		local t, n = R.parse(R.key("uniform2", 3))
		eq(t, "uniform2", "team")
		eq(n, 3, "number")
		eq(R.parse("nope"), nil, "not a key")
		eq(R.parse(nil), nil, "nil")
	end,
	["a new squad takes the lowest free name"] = function()
		local counts = R.counts({ "uniform1:1", "uniform1:1", "uniform1:3", "uniform2:2", nil })
		eq(counts["uniform1:1"], 2, "count")
		eq(R.free(Cfg, counts, "uniform1"), 2, "first gap")
		eq(R.free(Cfg, counts, "uniform2"), 1, "other team")
		local all = {}
		for n = 1, #Cfg.Names do
			all[R.key("uniform1", n)] = 1
		end
		eq(R.free(Cfg, all, "uniform1"), nil, "all taken")
	end,
	["joining: own team, not full, not empty, not already in"] = function()
		local counts = { ["uniform1:1"] = 6, ["uniform1:2"] = 2, ["uniform2:1"] = 1 }
		eq(R.blocked(Cfg, counts, "uniform1", nil, "uniform1:2"), nil, "room")
		eq(R.blocked(Cfg, counts, "uniform1", nil, "uniform1:1"), "Full", "six in it")
		eq(R.blocked(Cfg, counts, "uniform1", nil, "uniform2:1"), "Other", "enemy squad")
		eq(R.blocked(Cfg, counts, "uniform1", "uniform1:2", "uniform1:2"), "Already", "in it")
		eq(R.blocked(Cfg, counts, "uniform1", nil, "uniform1:4"), "Empty", "nobody there")
		eq(R.blocked(Cfg, counts, nil, nil, "uniform1:2"), "NoTeam", "free-for-all")
		eq(R.blocked(Cfg, counts, "uniform1", nil, "uniform1:99"), "Unknown", "past the names")
		eq(R.blocked(Cfg, counts, "uniform1", nil, 5), "Unknown", "not a key")
	end,
	["a team change leaves the squad"] = function()
		assert(R.keeps("uniform1:2", "uniform1"), "same team")
		assert(not R.keeps("uniform1:2", "uniform3"), "changed team")
		assert(not R.keeps("uniform1:2", nil), "no team")
		assert(not R.keeps(nil, "uniform1"), "no squad")
	end,
	["status: fallen, down, wave, in action, awaiting"] = function()
		local s = { exists = true, alive = true, down = false, wave = false }
		eq(R.status(s), "Action", "fighting")
		eq(R.status({ exists = false, alive = false, down = false, wave = false }), "Awaiting", "in the menu")
		eq(R.status({ exists = true, alive = false, down = true, wave = false }), "Fallen", "dead")
		eq(R.status({ exists = true, alive = true, down = true, wave = true }), "Down", "knocked down")
		eq(R.status({ exists = true, alive = true, down = false, wave = true }), "Wave", "in the wave line")
		for _, k in { "Action", "Awaiting", "Fallen", "Down", "Wave" } do
			assert(Cfg.Status[k], `{k} has words`)
		end
	end,
	["the list: own team's squads in order, yourself first"] = function()
		local rows = R.list(Cfg, "uniform1", {
			{ name = "zed", key = "uniform1:3" },
			{ name = "Bob", key = "uniform1:1" },
			{ name = "amy", key = "uniform1:1" },
			{ name = "Me", key = "uniform1:1", me = true },
			{ name = "foe", key = "uniform2:1" },
			{ name = "loner" },
		})
		eq(#rows, 2, "two squads")
		eq(rows[1].name, "Fehu", "first squad")
		eq(rows[2].n, 3, "second squad's number")
		eq(rows[1].members[1].name, "Me", "yourself first")
		eq(rows[1].members[2].name, "amy", "then by name")
		eq(rows[1].members[3].name, "Bob", "case-blind")
	end,
}
