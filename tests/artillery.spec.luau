--!strict
local C = require("../src/shared/Config/Artillery")
local A = require("../src/shared/Rules/Artillery")
local Assets = require("../src/shared/Config/Assets")

local GRAVITY = 196.2 -- Roblox's default workspace.Gravity
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end
local QF, HOW = C.Guns.artillery_qf18, C.Guns.artillery_howitzer

return {
	["every gun names a real asset and sane limits"] = function()
		for key, g in C.Guns do
			assert(g.asset == key and Assets.Entries[g.asset], key)
			assert(g.elevation[1] < g.elevation[2] and g.traverse > 0 and g.swing > 0, key)
			assert(g.reload > g.breechTimes[1] + g.breechTimes[2], key)
			assert(g.kg > 0 and g.speed > 0, key)
		end
		assert(QF.reload == 10 and HOW.reload == 30) -- user 2026-10-20
	end,
	["wrap keeps angles in -180..180"] = function()
		assert(near(A.wrap(190), -170) and near(A.wrap(-190), 170) and near(A.wrap(45), 45))
	end,
	["the mount traverses within its stops at its rate"] = function()
		local s = A.lay({ yaw = 0, traverse = 0, elevation = 0 }, 3, 0, QF, 0.25)
		assert(near(s.traverse, QF.traverseRate * 0.25) and s.yaw == 0)
		s = A.lay(s, 3, 0, QF, 10)
		assert(near(s.traverse, 3) and s.yaw == 0)
	end,
	["past the stop the whole gun swings, never past the aim"] = function()
		local s = { yaw = 0, traverse = QF.traverse, elevation = 0 }
		s = A.lay(s, 40, 0, QF, 1)
		assert(near(s.traverse, QF.traverse) and near(s.yaw, QF.swing))
		for _ = 1, 20 do
			s = A.lay(s, 40, 0, QF, 1)
		end
		assert(near(s.yaw + s.traverse, 40, 1e-4))
		-- the other way, across 180
		s = { yaw = 170, traverse = -QF.traverse, elevation = 0 }
		s = A.lay(s, -170, 0, QF, 0.1) -- 20 degrees to the left: past the stop
		assert(s.traverse > -QF.traverse) -- first the mount goes toward +4.5
	end,
	["elevation goes toward the aim, clamped to the limits"] = function()
		local s = A.lay({ yaw = 0, traverse = 0, elevation = 0 }, 0, 80, HOW, 100)
		assert(near(s.elevation, HOW.elevation[2]))
		s = A.lay(s, 0, -40, QF, 100)
		assert(near(s.elevation, QF.elevation[1]))
		s = A.lay({ yaw = 0, traverse = 0, elevation = 0 }, 0, 10, QF, 1)
		assert(near(s.elevation, QF.elevationRate))
	end,
	["level and straight the muzzle is the model's, along -Z"] = function()
		local x, y, z, dx, dy, dz = A.muzzle(QF, 0, 0)
		assert(near(x, QF.muzzle[1]) and near(y, QF.muzzle[2]) and near(z, QF.muzzle[3]))
		assert(near(dx, 0) and near(dy, 0) and near(dz, -1))
	end,
	["elevation lifts the muzzle about the trunnion, traverse turns it left"] = function()
		local _, y, _, _, dy = A.muzzle(QF, 0, 16)
		assert(y > QF.muzzle[2] and near(dy, math.sin(math.rad(16))))
		local _, _, _, dx = A.muzzle(QF, 4.5, 0)
		assert(dx < 0)
		-- the muzzle stays as far from the trunnion
		local t = QF.trunnion
		local x2, y2, z2 = A.muzzle(QF, 0, 12)
		local d0 = math.sqrt((QF.muzzle[2] - t[2]) ^ 2 + (QF.muzzle[3] - t[3]) ^ 2)
		assert(near(math.sqrt(x2 ^ 2 + (y2 - t[2]) ^ 2 + (z2 - t[3]) ^ 2), d0, 1e-6))
	end,
	["yawOf agrees with the traverse's turn"] = function()
		local _, _, _, dx, _, dz = A.muzzle(QF, 30, 0)
		assert(near(A.yawOf(dx, dz), 30, 1e-6))
	end,
	["the agreed ranges: field gun ~1,500 at full elevation, the howitzer a short-arc mortar"] = function()
		assert(math.abs(A.range(QF.speed, QF.elevation[2], GRAVITY) - 1500) < 50)
		assert(HOW.elevation[1] >= 45) -- it only lobs
		assert(math.abs(A.range(HOW.speed, HOW.elevation[1], GRAVITY) - 590) < 20)
		assert(A.range(HOW.speed, HOW.elevation[2], GRAVITY) < 250)
	end,
	["the mortar's breech clears its platform even at full elevation"] = function()
		local c = HOW.recoilClear
		local e = HOW.elevation[2]
		local r = A.recoilLength(HOW.recoil, e, HOW.trunnion[2], c)
		local a = math.rad(e)
		assert(HOW.trunnion[2] - (c.along + r) * math.sin(a) - c.below * math.cos(a) >= c.floor - 1e-6)
	end,
	["scatter stays within its most and is nothing for even numbers"] = function()
		local y, e, s = A.scatter(QF.scatter, { 0.5, 0.5, 0.5, 0.5, 0.5, 0.5 })
		assert(near(y, 0) and near(e, 0) and near(s, 1))
		y, e, s = A.scatter(QF.scatter, { 1, 1, 0, 0, 1, 1 })
		assert(near(y, QF.scatter.yaw) and near(e, -QF.scatter.elevation) and near(s, 1 + QF.scatter.speed))
	end,
	["the recoil goes back fast and runs out again"] = function()
		local t = QF.recoilTimes
		assert(A.recoilAt(-1, 3, t) == 0)
		assert(near(A.recoilAt(t[1], 3, t), 3))
		assert(near(A.recoilAt(t[1] + t[2], 3, t), 0))
		assert(A.recoilAt(t[1] + t[2] / 2, 3, t) < 1.5)
	end,
	["the howitzer's recoil is cut short at high elevation, never below nothing"] = function()
		local full = HOW.recoil
		assert(near(A.recoilLength(full, 0, HOW.trunnion[2], HOW.recoilClear), full))
		local at55 = A.recoilLength(full, 55, HOW.trunnion[2], HOW.recoilClear)
		assert(at55 < 1 and at55 >= 0)
		-- the breech's low point stays on or over the floor
		local c = HOW.recoilClear
		local a = math.rad(55)
		local low = HOW.trunnion[2] - (c.along + at55) * math.sin(a) - c.below * math.cos(a)
		assert(low >= c.floor - 1e-6)
		assert(A.recoilLength(full, 30, HOW.trunnion[2], c) <= full)
		assert(near(A.recoilLength(full, 16, QF.trunnion[2], QF.recoilClear), full))
	end,
	["the reload share fills from the shot to ready"] = function()
		assert(near(A.loaded(0, 10, 10), 0) and near(A.loaded(5, 10, 10), 0.5) and near(A.loaded(12, 10, 10), 1))
	end,
	["the breech opens after the shot and shuts before ready"] = function()
		local times = QF.breechTimes
		assert(A.breechAt(0.5, 0, 10, times, 0.3) == 0)
		assert(near(A.breechAt(5, 0, 10, times, 0.3), 1))
		assert(A.breechAt(9.9, 0, 10, times, 0.3) == 0)
	end,
	["the crystal flares, charges, then pulses ready"] = function()
		local c = C.Crystal
		local state, glow = A.crystal(0.1, 0, 30, 30, c)
		assert(state == "Fired" and glow > 0.5)
		state, glow = A.crystal(15, 0, 30, 30, c)
		assert(state == "Charging" and near(glow, 0.5))
		state, glow = A.crystal(31, 0, 30, 30, c)
		assert(state == "Ready" and glow <= 1 and glow >= 1 - c.pulseShare)
	end,
	["a shell comes down to level ground when its height is spent"] = function()
		local t = A.fall(0, 100, GRAVITY) :: number
		assert(near(t, 200 / GRAVITY))
		local t2 = A.fall(10, 0, GRAVITY) :: number
		assert(near(0.5 * GRAVITY * t2 * t2, 10))
		assert(A.fall(-10, 0, GRAVITY) == nil)
	end,
	["the server takes only real aims"] = function()
		assert(A.aimOk(10, 5) and not A.aimOk(0 / 0, 1) and not A.aimOk(1, 100) and not A.aimOk("1", 2))
	end,
}
