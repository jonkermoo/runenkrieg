--!strict
local Cfg = require("../src/shared/Config/Healing")
local A = require("../src/shared/Config/Assets")
local Palette = require("../src/shared/Config/Palette")
local H = require("../src/shared/Rules/Healing")

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

return {
	["the med pack from 70 up, the bandage below, nothing at full or dead"] = function()
		assert(H.kind(70, 100, Cfg) == "MedPack", "70: med pack")
		assert(H.kind(99, 100, Cfg) == "MedPack", "99: med pack")
		assert(H.kind(69.9, 100, Cfg) == "Bandage", "69.9: bandage")
		assert(H.kind(1, 100, Cfg) == "Bandage", "1: bandage")
		assert(H.kind(100, 100, Cfg) == nil, "full: nothing")
		assert(H.kind(0, 100, Cfg) == nil, "dead: nothing")
	end,
	["heal time grows with the health healed and never passes 5 s"] = function()
		assert(near(H.duration(0, 100, Cfg), 5), "a whole bar: 5 s")
		assert(near(H.duration(70, 100, Cfg), 1.5), "30 points: 1.5 s")
		assert(near(H.duration(90, 100, Cfg), 0.5), "10 points: 0.5 s")
		assert(H.duration(1, 100, Cfg) <= Cfg.MaxSeconds, "never past the cap")
		assert(H.duration(1, 400, Cfg) <= Cfg.MaxSeconds + 1e-9, "a bigger bar still caps at 5 s")
		assert(H.duration(100, 100, Cfg) == 0, "nothing to heal")
	end,
	["a heal step fills toward full and stops there"] = function()
		assert(near(H.step(50, 100, 1, Cfg), 70), "20 a second")
		assert(H.step(95, 100, 1, Cfg) == 100, "never past full")
	end,
	["slow recovery waits after a hit and stops at 70"] = function()
		local r = Cfg.Recovery
		assert(H.recover(40, r.delay - 0.1, 1, Cfg) == 40, "still waiting")
		assert(near(H.recover(40, r.delay, 1, Cfg), 40 + r.rate), "recovering")
		assert(H.recover(69.5, 20, 1, Cfg) == 70, "capped at 70")
		assert(H.recover(80, 20, 1, Cfg) == 80, "above the cap: unchanged, never lowered")
		assert(H.recover(0, 20, 1, Cfg) == 0, "dead stays dead")
	end,
	["wraps go on left arm, right leg, head, then no more"] = function()
		assert((H.nextWrap(0, Cfg) :: any).part == "Left Arm", "first: left arm")
		assert((H.nextWrap(1, Cfg) :: any).part == "Right Leg", "second: right leg")
		assert((H.nextWrap(2, Cfg) :: any).part == "Head", "third: head")
		assert(H.nextWrap(3, Cfg) == nil, "after the third: none")
	end,
	["reach to start and to keep healing"] = function()
		assert(H.inReach(Cfg.Range, Cfg.Range), "at the range")
		assert(not H.inReach(Cfg.Range + 0.1, Cfg.Range), "past it")
		assert(H.inReach(Cfg.Range + 1, Cfg.Range, Cfg.StartSlack), "lag slack")
		assert(not H.inReach(0 / 0, Cfg.Range), "NaN is never in reach")
		assert(Cfg.Break > Cfg.Range, "a heal started at the range doesn't break at once")
	end,
	["every wrap and held item is a registered asset with palette colours"] = function()
		for _, w in Cfg.Wraps do
			assert(A.Entries[w.entry], w.entry .. " registered")
		end
		for _, h in Cfg.Held do
			assert(A.Entries[h.entry], h.entry .. " registered")
		end
		for _, k in { "Cloth", "Canvas", "Thread", "Cross" } do
			assert(Palette.Medical[k], k .. " in Palette.Medical")
		end
	end,
}
