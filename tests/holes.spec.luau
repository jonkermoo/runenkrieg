--!strict
local F = require("../src/shared/Config/Firing")
local R = require("../src/shared/Rules/Holes")

return {
	["a hole stays a while, then fades out inside its life"] = function()
		local h = F.Effects.Hole
		local hold, fade = R.timing(h)
		assert(fade > 0 and hold > fade, "mostly whole, then a short fade")
		assert(math.abs(hold + fade - h.life) < 1e-9, "gone at its life")
		local hold2, fade2 = R.timing({ life = 2, fade = 5, max = 1 })
		assert(hold2 == 0 and fade2 == 2, "a fade longer than the life starts at once")
	end,
	["past the cap the oldest go"] = function()
		local h = F.Effects.Hole
		assert(h.max > 0)
		assert(R.excess(h.max, h.max) == 0, "at the cap: none")
		assert(R.excess(h.max + 1, h.max) == 1, "one over: the oldest")
		assert(R.excess(3, 0) == 3 and R.excess(0, 10) == 0)
	end,
	["reshaped ground takes the holes on it"] = function()
		local m = F.Effects.Hole.margin
		assert(m >= 0)
		assert(R.reshaped(2, 3, m) and R.reshaped(3 + m, 3, m))
		assert(not R.reshaped(3.5 + m, 3, m))
	end,
}
