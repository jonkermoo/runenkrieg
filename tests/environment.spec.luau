--!strict
local Cfg = require("../src/shared/Config/Environment")
local E = require("../src/shared/Rules/Environment")

local Day = Cfg.Day

local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end

local base = { density = 0.38, haze = 0.8, color = { 206, 218, 226 }, decay = { 126, 146, 160 } }

return {
	["the clock starts at the start clock"] = function()
		assert(near(E.clockAt(0, Day), Day.startClock), `{E.clockAt(0, Day)}`)
	end,
	["a full cycle comes back to the same time"] = function()
		assert(near(E.clockAt(Day.length, Day), Day.startClock, 1e-4))
		assert(near(E.clockAt(Day.length * 3 + 100, Day), E.clockAt(100, Day), 1e-4))
	end,
	["day takes dayShare of the cycle, night the rest"] = function()
		local fromRise = Day.length - E.phaseOf(Day.startClock, Day) -- seconds from the start to the next sunrise
		local rise = E.clockAt(fromRise, Day)
		assert(near(rise, Day.sunrise, 1e-4) or near(rise, Day.sunrise + 24, 1e-4), `sunrise at {rise}`)
		local set = E.clockAt(fromRise + Day.length * Day.dayShare, Day)
		assert(near(set, Day.sunset, 1e-4), `sunset at {set}`)
		assert(Day.length * Day.dayShare == 840, "14 min of day (user 2026-10-22)")
		assert(Day.length == 1200, "a 20 min day (user 2026-10-22)")
	end,
	["the clock only moves forward and wraps at 24"] = function()
		local last = E.clockAt(0, Day)
		local wraps = 0
		for t = 1, Day.length do
			local c = E.clockAt(t, Day)
			assert(c >= 0 and c < 24, `clock {c}`)
			if c < last then
				wraps += 1
			end
			last = c
		end
		assert(wraps == 1, `wrapped {wraps} times in one cycle`)
	end,
	["daylight: full at noon, none at midnight, eases at dawn"] = function()
		assert(E.daylight(12, Day) == 1)
		assert(E.daylight(0, Day) == 0 and E.daylight(23.5, Day) == 0)
		local dawn = E.daylight(Day.sunrise, Day)
		assert(dawn > 0.4 and dawn < 0.6, `dawn {dawn}`)
		assert(E.daylight(Day.sunrise - 0.5, Day) < E.daylight(Day.sunrise + 0.5, Day))
	end,
	["weather odds: rare fog and rain (user 2026-10-22)"] = function()
		local n = { Fog = 0, Rain = 0, Clear = 0 }
		for i = 0, 999 do
			local k = E.pick(i / 1000, Cfg.Weather.odds)
			n[k] += 1
		end
		assert(n.Fog == 250 and n.Rain == 150 and n.Clear == 600, `{n.Fog} {n.Rain} {n.Clear}`)
		assert(Cfg.Weather.clear.min == 480 and Cfg.Weather.clear.max == 900)
	end,
	["an event eases in and out and is zero outside"] = function()
		local fade = Cfg.Weather.fade
		assert(E.strength(99, 100, 400, fade) == 0 and E.strength(401, 100, 400, fade) == 0)
		assert(E.strength(100 + fade, 100, 400, fade) == 1 and E.strength(250, 100, 400, fade) == 1)
		local a, b = E.strength(110, 100, 400, fade), E.strength(130, 100, 400, fade)
		assert(a > 0 and a < b and b < 1, `{a} {b}`)
		assert(near(E.strength(120, 100, 400, fade), E.strength(380, 100, 400, fade)), "fade out mirrors fade in")
		local short = E.strength(105, 100, 110, fade) -- shorter than two fades: peaks in the middle
		assert(short == 1, `{short}`)
	end,
	["night is about a third of the day's light, and bluer"] = function()
		local day, night = E.look(1, "Clear", 0, base, Cfg), E.look(0, "Clear", 0, base, Cfg)
		local k = night.outdoorAmbient[1] / day.outdoorAmbient[1]
		assert(k > 0.3 and k < 0.4, `night outdoor ambient x{k}`)
		assert(night.outdoorAmbient[3] > night.outdoorAmbient[1], "moonlight is blue")
		assert(night.color[1] < day.color[1], "the haze darkens at night")
		assert(day.density == base.density and day.rain == 0 and day.wet == 1, "clear day = the map's own haze")
	end,
	["fog thickens the haze, rain darkens and wets"] = function()
		local fog = E.look(1, "Fog", 1, base, Cfg)
		assert(fog.density > base.density and fog.haze > base.haze and fog.rain == 0)
		local rain = E.look(1, "Rain", 1, base, Cfg)
		assert(rain.rain == 1 and rain.wet < 1 and rain.brightness < E.look(1, "Clear", 0, base, Cfg).brightness)
		local half = E.look(1, "Rain", 0.5, base, Cfg)
		assert(half.density > base.density and half.density < rain.density)
	end,
}
