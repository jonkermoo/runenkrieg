--!strict
local Cfg = require("../src/shared/Config/ZoneMatch")
local R = require("../src/shared/Rules/ZoneMatch")
local T = require("../src/shared/Rules/Teams")

return {
	["occupancy: nobody free, one holds, two or more contest"] = function()
		local s, h = R.occupancy({})
		assert(s == "Free" and h == nil)
		s, h = R.occupancy({ 7 })
		assert(s == "Held" and h == 7)
		s, h = R.occupancy({ 7, 9 })
		assert(s == "Contested" and h == nil)
		s, h = R.occupancy({ 1, 2, 3 })
		assert(s == "Contested" and h == nil)
	end,
	["inside: within the radius and the height, not past either"] = function()
		assert(R.inside(0, 0, 0, 0, 0, 0, Cfg))
		assert(R.inside(Cfg.Radius, 0, 0, 0, 0, 0, Cfg), "on the edge counts")
		assert(not R.inside(Cfg.Radius + 0.01, 0, 0, 0, 0, 0, Cfg))
		assert(not R.inside(0, Cfg.Height + 0.01, 0, 0, 0, 0, Cfg), "high over it")
		assert(not R.inside(0, -Cfg.Height - 0.01, 0, 0, 0, 0, Cfg), "under it")
	end,
	["the zone always moves to another spot, reaching every other"] = function()
		for count = 2, 6 do
			for cur = 1, count do
				local seen = {}
				for k = 0, 99 do
					local n = R.nextSpot(cur, count, k / 100)
					assert(n ~= cur and n >= 1 and n <= count, `{cur} of {count} -> {n}`)
					seen[n] = true
				end
				for i = 1, count do
					assert(i == cur or seen[i], `{cur} of {count} never moves to {i}`)
				end
			end
		end
		assert(R.nextSpot(1, 1, 0.5) == 1, "one spot stays")
		local first = R.nextSpot(nil, 5, 0.99)
		assert(first >= 1 and first <= 5)
	end,
	["spawn: farthest from the others, never by the zone if any point is clear"] = function()
		local pts = { { 0, 0 }, { 100, 0 }, { 200, 0 } }
		assert(R.pickSpawn(pts, { { 0, 0 } }, nil, 60) == 3, "away from the other soldier")
		assert(R.pickSpawn(pts, { { 210, 0 } }, nil, 60) == 1)
		assert(R.pickSpawn(pts, { { 0, 0 } }, { 200, 0 }, 60) == 2, "the far point is by the zone")
		assert(R.pickSpawn(pts, {}, { 0, 0 }, 60) == 3, "alone: farthest from the zone")
		assert(R.pickSpawn({ { 0, 0 } }, { { 1, 0 } }, { 0, 0 }, 60) == 1, "no point clear: any")
	end,
	["capture: at the hold time, once per live spot"] = function()
		local need = Cfg.CaptureSeconds
		assert(need == 10, "user 2026-10-27: 10 s")
		assert(not R.captured(need - 0.01, need, false))
		assert(R.captured(need, need, false))
		assert(not R.captured(need * 3, need, true), "only once")
	end,
	["ranking: highest first, ties by id"] = function()
		local r = R.ranking({ [5] = 10, [2] = 30, [9] = 10 })
		assert(r[1] == 2 and r[2] == 5 and r[3] == 9)
		assert(#R.ranking({}) == 0)
	end,
	["clock: m:ss, never under 0"] = function()
		assert(R.clock(480) == "8:00")
		assert(R.clock(61.2) == "1:02")
		assert(R.clock(9) == "0:09")
		assert(R.clock(-3) == "0:00")
	end,
	["free-for-all: nobody is a teammate, not even the same uniform"] = function()
		assert(T.same("uniform1", "uniform1"), "teams outside it")
		assert(not T.same("uniform1", "uniform1", true))
		assert(not T.spared("uniform1", "uniform1", false, true), "hits land")
	end,
	["config: sane numbers"] = function()
		assert(Cfg.Warning < Cfg.MoveEvery and Cfg.MoveEvery < Cfg.MatchSeconds)
		assert(Cfg.SpawnProtection > 0 and Cfg.SpawnProtection <= 5, "a short spawn protection (user: 3 s)")
		assert(Cfg.Radius > 0 and Cfg.Height > 0 and Cfg.PointsPerSecond > 0 and Cfg.Tick > 0)
		for _, k in { "Free", "Mine", "Theirs", "Contested", "Post" } do
			assert(Cfg.Marker.Colors[k], `no {k} colour`)
		end
	end,
}
