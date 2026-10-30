--!strict
local T = require("../src/shared/Rules/Teams")
local U = require("../src/shared/Config/Uniforms")
local DamageCfg = require("../src/shared/Config/Damage")
local Cfg = require("../src/shared/Config/Teams")

return {
	["the same kit is the same team"] = function()
		for _, kit in U.Teams do
			assert(T.same(kit, kit), `{kit} with {kit}`)
		end
	end,
	["different kits are enemies"] = function()
		for _, a in U.Teams do
			for _, b in U.Teams do
				if a ~= b then
					assert(not T.same(a, b), `{a} with {b}`)
				end
			end
		end
	end,
	["an unknown kit is nobody's teammate"] = function()
		assert(not T.same(nil, nil), "both unknown")
		assert(not T.same(nil, "uniform1"), "one unknown")
		assert(not T.same("uniform1", nil), "the other unknown")
		assert(not T.same("", ""), "empty")
		assert(not T.same(1, 1), "not a kit name")
	end,
	["no friendly fire: teammates spared, enemies and unknowns hit"] = function()
		assert(DamageCfg.FriendlyFire == false, "friendly fire is off (user 2026-10-26)")
		for _, a in U.Teams do
			for _, b in U.Teams do
				assert(T.spared(a, b, false) == (a == b), `{a} on {b}`)
				assert(not T.spared(a, b, true), `{a} on {b} with friendly fire on`)
			end
		end
		assert(not T.spared(nil, "uniform1", false) and not T.spared("uniform1", nil, false), "unknown kit is hit")
	end,
	["every team has its nation's names and a flag, none shared"] = function()
		local seen = {}
		for _, kit in U.Teams do
			local k = (U.Kits :: any)[kit]
			assert(
				type(k.team) == "string" and k.team ~= "" and type(k.army) == "string" and k.army ~= "",
				`{kit}: names`
			)
			assert(k.flag and k.flag.full > 0 and k.flag.pole > 0 and k.flag.full ~= k.flag.pole, `{kit}: flag ids`)
			for _, v in { k.team, k.army, k.flag.full, k.flag.pole } do
				assert(not seen[v], `{kit}: {v} used twice`)
				seen[v] = true
			end
		end
	end,
	["head counts per team, strangers not counted"] = function()
		local c = T.counts({ "uniform1", "uniform2", "uniform1", nil, "nope", 5 } :: { unknown }, U.Teams)
		assert(c.uniform1 == 2 and c.uniform2 == 1 and c.uniform3 == 0, "counted")
		assert(c.nope == nil, "not a team")
	end,
	["100 players over three teams: room for 34 each (user 2026-10-27)"] = function()
		assert(Cfg.MaxPlayers == 100 and T.room(Cfg.MaxPlayers, #U.Teams) == 34)
		assert(T.room(100, 2) == 50 and T.room(10, 0) == 10)
	end,
	["only to a smaller team (user 2026-10-27)"] = function()
		assert(Cfg.Gap == 1, "the user's rule")
		local c = { uniform1 = 3, uniform2 = 2, uniform3 = 3 }
		assert(T.blocked(c, "uniform1", "uniform2", Cfg.Gap, 34) == nil, "3 -> 2 evens it")
		assert(T.blocked(c, "uniform1", "uniform3", Cfg.Gap, 34) == "Bigger", "3 -> 3 would make it 2 / 4")
		assert(T.blocked(c, "uniform2", "uniform1", Cfg.Gap, 34) == "Bigger", "the smallest can't leave")
		assert(T.blocked(c, "uniform1", "uniform1", Cfg.Gap, 34) == "Own")
		assert(
			T.blocked(c, "uniform1", "nope", Cfg.Gap, 34) == "Unknown"
				and T.blocked(c, "uniform1", nil, 1, 34) == "Unknown"
		)
		local alone = { uniform1 = 1, uniform2 = 0, uniform3 = 0 }
		assert(T.blocked(alone, "uniform1", "uniform3", Cfg.Gap, 34) == nil, "alone: to an empty team")
		local even = { uniform1 = 1, uniform2 = 1, uniform3 = 0 }
		assert(T.blocked(even, "uniform1", "uniform2", Cfg.Gap, 34) == "Bigger", "two players: never onto one team")
		assert(T.blocked(even, "uniform1", "uniform3", Cfg.Gap, 34) == nil)
		assert(T.blocked({ uniform1 = 3, uniform2 = 0, uniform3 = 0 }, "uniform1", "uniform2", 1, 0) == "Full")
		assert(T.blocked({ uniform1 = 0, uniform2 = 1, uniform3 = 0 }, nil, "uniform2", 1, 34) == nil, "no team yet")
	end,
	["Normal mode: only the match's two teams are in play"] = function()
		assert(table.concat(T.playing(U.Teams, "uniform3,uniform1"), ",") == "uniform3,uniform1")
		assert(#T.playing(U.Teams, nil) == #U.Teams, "no match: all of them")
		assert(#T.playing(U.Teams, "uniform1,uniform1") == #U.Teams and #T.playing(U.Teams, "uniform1,x") == #U.Teams)
	end,
	["a newcomer joins the smallest team, a tie broken at random"] = function()
		assert(T.smallest({ uniform1 = 2, uniform2 = 1, uniform3 = 2 }, U.Teams, 0.99) == "uniform2")
		local tie = { uniform1 = 1, uniform2 = 0, uniform3 = 0 }
		assert(T.smallest(tie, U.Teams, 0) == "uniform2" and T.smallest(tie, U.Teams, 0.99) == "uniform3")
		assert(T.smallest({}, U.Teams, 0) == "uniform1", "nobody yet")
	end,
}
