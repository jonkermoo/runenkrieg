--!strict
local Cfg = require("../src/shared/Config/Look")
local Settings = require("../src/shared/Config/Settings")
local G = require("../src/shared/Rules/Grade")

return {
	["day share: 0 at night, 1 by day, eased between"] = function()
		assert(G.dayShare(-1, Cfg.NightAt, Cfg.DayAt) == 0)
		assert(G.dayShare(1, Cfg.NightAt, Cfg.DayAt) == 1)
		local mid = G.dayShare((Cfg.NightAt + Cfg.DayAt) / 2, Cfg.NightAt, Cfg.DayAt)
		assert(math.abs(mid - 0.5) < 1e-9)
		assert(Cfg.NightAt < Cfg.DayAt)
	end,
	["mix: the night tone at 0, the day tone at 1"] = function()
		local g = Cfg.Levels.Normal.grade
		local n, d = G.mix(g.night, g.day, 0), G.mix(g.night, g.day, 1)
		assert(n.saturation == g.night.saturation and n.tint[3] == g.night.tint[3])
		assert(d.contrast == g.day.contrast and d.tint[1] == g.day.tint[1])
	end,
	["every Effects level but Off has a look; bloom keeps the magic threshold"] = function()
		for _, level in Settings.Options.Effects.values do
			local l = (Cfg.Levels :: any)[level]
			assert(level == "Off" or l, "no look for " .. level)
			if l then
				assert(l.bloom.threshold >= 2, level .. ": bloom would glow the flat colours")
				for _, tone in { l.grade.day, l.grade.night } do
					assert(#tone.tint == 3, level .. " tint")
					for _, c in tone.tint do
						assert(c >= 0 and c <= 255, level .. " tint channel")
					end
				end
			end
		end
	end,
}
