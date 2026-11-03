--!strict
-- The telegraph wires' spans (Rules/PoleWires, src/server/PoleWires; user 2026-11-03).
local Cfg = require("../src/shared/Config/Destruction").Wires
local R = require("../src/shared/Rules/PoleWires")

-- a sagging span from `a` to `b` in `n` segments, as src/dev/Props.wire builds it
local function span(a: { number }, b: { number }, n: number): { R.Segment }
	local function at(t: number): { number }
		return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t - 4.8 * t * (1 - t), a[3] + (b[3] - a[3]) * t }
	end
	local out = {}
	for i = 0, n - 1 do
		table.insert(out, { a = at(i / n), b = at((i + 1) / n) })
	end
	return out
end

return {
	["spans: two wires between three poles are four spans, each from pole to pole, split at the middle pole"] = function()
		local segs = {}
		for _, s in { span({ 0, 20, -2 }, { 48, 20, -2 }, 4), span({ 0, 20, 2 }, { 48, 20, 2 }, 4) } do
			for _, x in s do
				table.insert(segs, x)
			end
		end
		for _, s in { span({ 48, 20, -2 }, { 96, 21, -2 }, 4), span({ 48, 20, 2 }, { 96, 21, 2 }, 4) } do
			for _, x in s do
				table.insert(segs, x)
			end
		end
		local insulators = { { 0, 20, -2 }, { 0, 20, 2 }, { 48, 20, -2 }, { 48, 20, 2 }, { 96, 21, -2 }, { 96, 21, 2 } }
		local spans = R.spans(segs, Cfg.join, insulators)
		assert(#spans == 4, `{#spans} spans`)
		for _, s in spans do
			assert(#s.members == 4)
			local xs = { s.a[1], s.b[1] }
			table.sort(xs)
			assert(math.abs(xs[2] - xs[1] - 48) < 1e-6, "from one pole to the next")
		end
		-- (without the insulators the spans either side of a pole would run on as one: the whole line would fall)
		assert(#R.spans(segs, Cfg.join, {}) == 2)
	end,
	["spans: a span alone has its two pole ends; shuffled segments make the same span"] = function()
		local segs = span({ 0, 20, 0 }, { 40, 20, 0 }, 4)
		segs[1], segs[3] = segs[3], segs[1]
		local spans = R.spans(segs, Cfg.join, { { 0, 20, 0 }, { 40, 20, 0 } })
		assert(#spans == 1 and #spans[1].members == 4)
		local s = spans[1]
		assert(s.a[1] + s.b[1] == 40 and s.a[2] == 20 and s.b[2] == 20)
	end,
	["held: an end hangs on while an insulator is there, falls once none is"] = function()
		local p = { 10, 20, 2 }
		assert(R.held(p, { { 10, 20, 2 + Cfg.reach / 2 } }, Cfg.reach))
		assert(not R.held(p, { { 10, 20, 2 + Cfg.reach * 2 } }, Cfg.reach))
		assert(not R.held(p, {}, Cfg.reach))
		assert(Cfg.join < Cfg.reach and Cfg.reach < 1, "a span's end sits on its insulator")
	end,
}
