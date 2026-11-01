--!strict
local Cfg = require("../src/shared/Config/Bots")
local U = require("../src/shared/Config/Uniforms")
local R = require("../src/shared/Rules/BotCallouts")

local C = Cfg.Callouts

return {
	["can: silent with no player near, or on a failed chance"] = function()
		local s = R.new()
		assert(not R.can(s, 1, "West", "Hit", 0, C.near + 1, 0, C), "nobody near")
		assert(R.can(s, 1, "West", "Hit", 0, 10, 0.99, C), "Hit always")
		assert(not R.can(s, 1, "West", "Reload", 0, 10, 0.99, C), "Reload only sometimes")
		assert(not R.can(s, 1, "West", "Nonsense", 0, 10, 0, C), "an event with no chance")
	end,
	["can: each bot, each event and each side wait between callouts"] = function()
		local s = R.new()
		R.said(s, 1, "West", "Hit", 0)
		assert(not R.can(s, 1, "West", "Spotted", C.botEvery - 0.1, 10, 0, C), "the bot's own wait")
		assert(not R.can(s, 2, "West", "Spotted", C.sideEvery - 0.1, 10, 0, C), "the side's wait")
		assert(R.can(s, 2, "West", "Spotted", C.sideEvery + 0.1, 10, 0, C), "another bot after the side's wait")
		assert(R.can(s, 3, "East", "Spotted", 0.1, 10, 0, C), "the other side isn't held up")
		assert(not R.can(s, 1, "West", "Hit", C.botEvery + 0.1, 10, 0, C), "the same event waits longer")
		assert(R.can(s, 1, "West", "Hit", C.sameEvery + 0.1, 10, 0, C))
		R.forget(s, 1)
		assert(R.can(s, 1, "West", "Hit", C.sideEvery + 0.1, 10, 0, C), "forgotten")
	end,
	["line: picks one, fills the name, skips name lines without a name"] = function()
		local lines = { "Man down!", "They've got {name}!" }
		assert(R.line(lines, 0.99, "Hughes") == "They've got Hughes!")
		assert(R.line(lines, 0.99, nil) == "Man down!", "no name: the plain one")
		assert(R.line({ "{name}!" }, 0.5, nil) == nil)
		assert(R.line(nil, 0.5, nil) == nil)
	end,
	["config: every team has a line for every event with a chance, in plain short words"] = function()
		local teams = {}
		for _, k in U.Kits do
			teams[k.team] = true
		end
		for team in teams do
			local L = C.Lines[team]
			assert(L, `lines for {team}`)
			for event in C.chance do
				assert(L[event] and #L[event] > 0, `{team} {event}`)
				for _, l in L[event] do
					assert(#l <= 40, `short: {l}`)
				end
			end
		end
		assert(C.hear >= C.near and C.botEvery >= C.sideEvery)
	end,
}
