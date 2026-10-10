--!strict
local B = require("../src/shared/Config/Buildings")
local D = require("../src/shared/Config/Destruction")
local M = require("../src/shared/Config/Metrics")
local O = require("../src/shared/Rules/Openings")

local cfg = { margin = B.OpeningMargin, post = B.FramePost, sectionWidth = D.SectionWidth }
local Bm = M.Building

local function overlaps(a1: number, a2: number, b1: number, b2: number): boolean
	return a1 < b2 and b1 < a2
end

-- keep-outs for a ThatchCottage-like wall: quoins at both ends (+ optional chimney in the middle)
local function cottageKeepOuts(L: number, chimney: boolean): { { number } }
	local q = B.Quoin.long - 0.25
	local k = { { -L / 2, -L / 2 + q }, { L / 2 - q, L / 2 } }
	if chimney then
		table.insert(k, { -2.1, 2.1 })
	end
	return k
end

local function check(L: number, keep: { { number } }, doors: { any }?, maxW: number): ({ any }, { any })
	local sections, openings = O.layout(L, keep, doors, Bm.WindowWidth, maxW, cfg)
	local total = 0
	for _, s in sections do
		total += s.w
	end
	assert(math.abs(total - L) < 1e-6, `sections sum to {total}, not {L}`)
	for i, o in openings do
		local a, b = o.center - o.extent / 2, o.center + o.extent / 2
		assert(a >= -L / 2 - 1e-6 and b <= L / 2 + 1e-6, "opening sticks out of the wall")
		for _, k in keep do
			assert(not overlaps(a, b, k[1], k[2]), `{o.kind} frame overlaps a keep-out`)
		end
		for j = i + 1, #openings do
			local p = openings[j]
			assert(not overlaps(a, b, p.center - p.extent / 2, p.center + p.extent / 2), "openings overlap")
		end
	end
	for _, s in sections do
		if s.opening then
			assert(s.w >= s.opening.extent - 1e-6, "section narrower than its opening")
		end
	end
	return sections, openings
end

local function count(openings: { any }, kind: string): number
	local n = 0
	for _, o in openings do
		if o.kind == kind then
			n += 1
		end
	end
	return n
end

return {
	["cottage front: door + a window each side, clear of the corner stones"] = function()
		local _, o = check(20, cottageKeepOuts(20, false), { { center = 0, w = Bm.DoorWidth } }, 2)
		assert(count(o, "door") == 1 and count(o, "window") == 2, `front got {count(o, "window")} windows`)
	end,
	["cottage back: two windows"] = function()
		local _, o = check(20, cottageKeepOuts(20, false), nil, 2)
		assert(count(o, "window") == 2, `back got {count(o, "window")} windows`)
	end,
	["cottage side: one window; chimney side: none rather than overlapping"] = function()
		local inner = 14 - 2 * 1.4
		local _, plain = check(inner, cottageKeepOuts(inner, false), nil, 1)
		assert(count(plain, "window") == 1, "plain side should get one window")
		check(inner, cottageKeepOuts(inner, true), nil, 1) -- any count, but never overlapping
	end,
	["no room means no window"] = function()
		local _, o = check(3, {}, nil, 2)
		assert(#o == 0, "a 3-stud wall cannot hold a framed window")
	end,
	["long cottage front: two doors and three windows, none overlapping"] = function()
		local doors = { { center = -6, w = Bm.DoorWidth }, { center = 6, w = Bm.DoorWidth } }
		local _, o = check(32, cottageKeepOuts(32, false), doors, 3)
		assert(
			count(o, "door") == 2 and count(o, "window") == 3,
			`got {count(o, "door")} doors, {count(o, "window")} windows`
		)
	end,
	["barn: a wide door still leaves the frame clear"] = function()
		local _, o = check(28, {}, { { center = 0, w = 7, h = 9 } }, 2)
		assert(count(o, "door") == 1, "barn door missing")
	end,
}
