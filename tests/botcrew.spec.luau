--!strict
local Cfg = require("../src/shared/Config/Bots")
local R = require("../src/shared/Rules/BotCrew")

local C = Cfg.Crew

return {
	["assign: each gun its nearest gunner, nearest pairs first"] = function()
		local guns = { { x = 0, z = 0 }, { x = 100, z = 0 } }
		local gunners = {
			{ x = 90, z = 0, crew = false },
			{ x = 10, z = 0, crew = false },
			{ x = 50, z = 0, crew = false },
		}
		local got = R.assign(guns, gunners, 4, C)
		assert(got[1] == 2 and got[2] == 1)
	end,
	["assign: no more than the room, nobody past the walk"] = function()
		local guns = { { x = 0, z = 0 }, { x = 100, z = 0 } }
		local gunners = { { x = 10, z = 0, crew = false }, { x = 90, z = 0, crew = false } }
		local got = R.assign(guns, gunners, 1, C)
		local n = 0
		for _ in got do
			n += 1
		end
		assert(n == 1, "one gunner")
		assert(next(R.assign(guns, { { x = 0, z = C.walk + 150, crew = false } }, 4, C)) == nil, "too far")
	end,
	["assign: an Engineer on gun duty goes before a nearer soldier"] = function()
		local guns = { { x = 0, z = 0 } }
		local gunners = { { x = 20, z = 0, crew = false }, { x = 20 + C.crewFirst / 2, z = 0, crew = true } }
		assert(R.assign(guns, gunners, 4, C)[1] == 2)
	end,
	["assign: guns with enemies in reach before nearer idle ones"] = function()
		local guns = { { x = 0, z = 0, idle = true }, { x = 100, z = 0 } }
		local got = R.assign(guns, { { x = 5, z = 0, crew = false } }, 4, C)
		assert(got[2] == 1 and got[1] == nil, "the one gunner goes to the gun that can reach")
		local both = R.assign(guns, { { x = 5, z = 0, crew = false }, { x = 90, z = 0, crew = false } }, 4, C)
		assert(both[1] == 1 and both[2] == 2, "idle guns still get a gunner when there are enough")
		local room = R.assign(guns, { { x = 5, z = 0, crew = false }, { x = 90, z = 0, crew = false } }, 1, C)
		assert(room[2] == 2 and room[1] == nil, "room for one: not the idle gun")
	end,
	["assign: a gunner who just left a gun that couldn't reach takes no idle gun"] = function()
		local guns = { { x = 0, z = 0, idle = true }, { x = 100, z = 0 } }
		local got = R.assign(guns, { { x = 5, z = 0, crew = false, busyOnly = true } }, 4, C)
		assert(got[2] == 1 and got[1] == nil, "the gun that can reach")
		local none = R.assign({ guns[1] }, { { x = 5, z = 0, crew = false, busyOnly = true } }, 4, C)
		assert(next(none) == nil, "back to its duty")
	end,
	["inReach: between the gun's nearest and furthest only"] = function()
		assert(R.inReach(0, 0, { { x = 300, z = 0 } }, 20, 400))
		assert(R.inReach(0, 0, { { x = 400, z = 0 } }, 20, 400), "the very edge")
		assert(not R.inReach(0, 0, { { x = 500, z = 0 } }, 20, 400), "too far")
		assert(not R.inReach(0, 0, { { x = 10, z = 0 } }, 20, 400), "too near")
		assert(R.inReach(0, 0, { { x = 500, z = 0 }, { x = 0, z = 100 } }, 20, 400), "any one will do")
		assert(not R.inReach(0, 0, {}, 20, 400), "nothing known")
	end,
	["leaves: only once idle for the full time"] = function()
		assert(not R.leaves(29.9, 30))
		assert(R.leaves(30, 30))
	end,
	["repairOrder: built guns under half first, wherever they are, then the usual repairs"] = function()
		local keep = require("../src/shared/Config/Artillery").Man.keep
		local pieces = {
			{ gun = false, built = true, held = true, hp = 10, max = 100 }, -- a trench, badly hurt
			{ gun = true, built = true, held = true, hp = 49, max = 100 }, -- out of service
			{ gun = true, built = true, held = true, hp = 50, max = 100 }, -- still in service
			{ gun = true, built = false, held = true, hp = 20, max = 100 }, -- being built
			{ gun = true, built = true, held = true, hp = 100, max = 240 }, -- the howitzer, out of service
			{ gun = true, built = true, held = false, hp = 10, max = 100 }, -- on the enemy's ground
		}
		local order, fix = R.repairOrder(pieces, { 3, 2, 1 }, keep)
		assert(#order == 4 and order[1] == 2 and order[2] == 5 and order[3] == 3 and order[4] == 1)
		assert(fix[2] and fix[5] and not fix[3] and not fix[1] and not fix[4] and not fix[6])
	end,
	["repairOrder: a broken gun of no use isn't fixed first, one not looked at is"] = function()
		local keep = require("../src/shared/Config/Artillery").Man.keep
		local pieces = {
			{ gun = true, built = true, held = true, hp = 10, max = 100, useful = false }, -- can't reach the enemy
			{ gun = true, built = true, held = true, hp = 10, max = 100, useful = true },
			{ gun = true, built = true, held = true, hp = 10, max = 100 }, -- not looked at yet
		}
		local order, fix = R.repairOrder(pieces, { 1 }, keep)
		assert(not fix[1] and fix[2] and fix[3], "only the useful and the unknown fixed first")
		assert(
			#order == 3 and order[1] == 2 and order[2] == 3 and order[3] == 1,
			"the useless one only as a usual repair"
		)
	end,
	["captured: used when its shot is clear and it stands safe, else wrecked"] = function()
		assert(R.captured(true, true) == "use")
		assert(R.captured(false, true) == "wreck", "blocked")
		assert(R.captured(true, false) == "wreck", "unsafe")
		assert(R.captured(false, false) == "wreck")
	end,
	["safeSpot: not out past its sector's middle toward the enemy, no enemy close"] = function()
		local S = C.captured.safe
		-- (the enemy's way +x from a sector middle at 0, 0)
		assert(R.safeSpot(-50, 10, 0, 0, 1, 0, {}, S), "behind the middle")
		assert(R.safeSpot(S.ahead, 0, 0, 0, 1, 0, {}, S), "just at the edge allowed")
		assert(not R.safeSpot(S.ahead + 1, 0, 0, 0, 1, 0, {}, S), "out toward the enemy")
		assert(not R.safeSpot(-50, 0, 0, 0, 1, 0, { { x = -50 + S.threat - 1, z = 0 } }, S), "an enemy close")
		assert(R.safeSpot(-50, 0, 0, 0, 1, 0, { { x = -50 + S.threat + 1, z = 0 } }, S))
	end,
	["sectorAt: the nearest sector's index"] = function()
		local sectors = { { x = 0, z = 0 }, { x = 400, z = 0 }, { x = 800, z = 30 } }
		assert(
			R.sectorAt(190, 50, sectors) == 1 and R.sectorAt(210, 0, sectors) == 2 and R.sectorAt(900, 0, sectors) == 3
		)
		assert(R.sectorAt(0, 0, {}) == nil)
	end,
	["groups: the biggest cluster first, its middle"] = function()
		local pts = {
			{ x = 0, z = 0 },
			{ x = 4, z = 0 },
			{ x = 0, z = 4 },
			{ x = 200, z = 0 },
		}
		local g = R.groups(pts, C.cluster)
		assert(#g == 2)
		assert(g[1].n == 3 and math.abs(g[1].x - 4 / 3) < 1e-6 and math.abs(g[1].z - 4 / 3) < 1e-6)
		assert(g[2].n == 1 and g[2].x == 200)
		assert(#R.groups({}, C.cluster) == 0)
	end,
	["clear: holds with a teammate within the radius"] = function()
		local friends = { { x = 30, z = 0 } }
		assert(R.clear(0, 0, friends, 25))
		assert(not R.clear(0, 0, friends, 40))
		assert(R.clear(0, 0, {}, 40))
	end,
	["danger: the howitzer's shell holds wider"] = function()
		assert(R.danger(2.5, C.hold) == C.hold.small)
		assert(R.danger(100, C.hold) == C.hold.big)
	end,
	["scatter: within the radius"] = function()
		for _, u in { { 0, 0 }, { 0.99, 0.3 }, { 0.5, 0.75 } } do
			local x, z = R.scatter(10, 20, C.scatter, u[1], u[2])
			assert(math.sqrt((x - 10) ^ 2 + (z - 20) ^ 2) <= C.scatter + 1e-6)
		end
		local x, z = R.scatter(10, 20, C.scatter, 0, 0.5)
		assert(x == 10 and z == 20, "u1 0: the middle")
	end,
	["burst: held, let go, held again"] = function()
		local B = C.burst
		assert(R.burst(0, B))
		assert(R.burst(B.on * 0.9, B))
		assert(not R.burst(B.on + B.off * 0.5, B))
		assert(R.burst(B.on + B.off + 0.01, B))
		assert(not R.burst(-1, B))
	end,
}
