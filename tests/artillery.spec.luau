--!strict
local C = require("../src/shared/Config/Artillery")
local A = require("../src/shared/Rules/Artillery")
local Assets = require("../src/shared/Config/Assets")

local GRAVITY = 196.2 -- Roblox's default workspace.Gravity
local function near(a: number, b: number, eps: number?): boolean
	return math.abs(a - b) <= (eps or 1e-6)
end
local QF, HOW = C.Guns.artillery_qf18, C.Guns.artillery_howitzer
local BORE = table.clone(QF) :: any -- the field gun with its shell leaving along the bore (no aimTilt)
BORE.aimTilt = nil

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
		local x, y, z, dx, dy, dz = A.muzzle(BORE, 0, 0)
		assert(near(x, QF.muzzle[1]) and near(y, QF.muzzle[2]) and near(z, QF.muzzle[3]))
		assert(near(dx, 0) and near(dy, 0) and near(dz, -1))
	end,
	["elevation lifts the muzzle about the trunnion, traverse turns it left"] = function()
		local _, y, _, _, dy = A.muzzle(BORE, 0, 16)
		assert(y > QF.muzzle[2] and near(dy, math.sin(math.rad(16))))
		local _, _, _, dx = A.muzzle(BORE, 4.5, 0)
		assert(dx < 0)
		-- the muzzle stays as far from the trunnion
		local t = QF.trunnion
		local x2, y2, z2 = A.muzzle(BORE, 0, 12)
		local d0 = math.sqrt((QF.muzzle[2] - t[2]) ^ 2 + (QF.muzzle[3] - t[3]) ^ 2)
		assert(near(math.sqrt(x2 ^ 2 + (y2 - t[2]) ^ 2 + (z2 - t[3]) ^ 2), d0, 1e-6))
	end,
	["yawOf agrees with the traverse's turn"] = function()
		local _, _, _, dx, _, dz = A.muzzle(BORE, 30, 0)
		assert(near(A.yawOf(dx, dz), 30, 1e-6))
	end,
	["the agreed ranges: field gun ~1,500 at full elevation, the howitzer a short-arc mortar"] = function()
		-- (user 2026-10-26: "angles it slightly (not visibly at all) up, since it will be a mid range weapon (only can
		-- hit enemy sectors)", the shortest ~300: one sector): the shell leaves aimTilt over the bore
		local tilt = QF.aimTilt :: number
		local low = A.range(QF.speed, QF.elevation[1] + tilt, QF.gravity)
		assert(tilt > 0 and tilt <= 10 and math.abs(low - 300) < 20, low)
		local _, _, _, _, dy = A.muzzle(QF, 0, 0)
		assert(near(dy, math.sin(math.rad(tilt))))
		assert(A.range(QF.speed, QF.elevation[2] + tilt, QF.gravity) > 1500)
		assert(HOW.elevation[1] >= 45) -- it only lobs
		assert(math.abs(A.range(HOW.speed, HOW.elevation[1], HOW.gravity) - 590) < 20)
		assert(A.range(HOW.speed, HOW.elevation[2], HOW.gravity) < 250)
		-- slower than under Roblox's gravity (user 2026-10-21): the flights are longer
		local function flight(g: any, e: number): number
			return 2 * g.speed * math.sin(math.rad(e)) / g.gravity
		end
		assert(flight(QF, 16) > 3 and flight(HOW, 45) > 5)
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
		-- full at its lowest lay, cut short at its highest (Bertha: the gem's point over the turntable)
		assert(near(A.recoilLength(full, HOW.elevation[1], HOW.trunnion[2], HOW.recoilClear), full))
		local top = A.recoilLength(full, HOW.elevation[2], HOW.trunnion[2], HOW.recoilClear)
		assert(top < full and top >= 0)
		-- the breech's low point stays on or over the floor
		local c = HOW.recoilClear
		local a = math.rad(HOW.elevation[2])
		local low = HOW.trunnion[2] - (c.along + top) * math.sin(a) - c.below * math.cos(a)
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
	["the crystal flares, drains, comes back to life, blooms, then breathes ready"] = function()
		local c = C.Crystal
		local state, glow = A.crystal(0.1, 0, 30, 30, c)
		assert(state == "Fired" and glow > 1)
		-- just after the flare: nearly dark
		state, glow = A.crystal(c.flare + 0.05, 0, 30, 30, c)
		assert(state == "Charging" and glow < 0.2)
		-- rising overall: late is brighter than early (sampled over a beat)
		local function mean(t0: number): number
			local sum = 0
			for k = 0, 19 do
				local _, g = A.crystal(t0 + k * 0.1, 0, 30, 30, c)
				sum += g
			end
			return sum / 20
		end
		assert(mean(25) > mean(8) and mean(8) > mean(1))
		for t = 1, 29, 0.37 do
			local _, g = A.crystal(t, 0, 30, 30, c)
			assert(g >= 0 and g <= 1)
		end
		state, glow = A.crystal(30.1, 0, 30, 30, c)
		assert(state == "Awake" and glow > 1)
		state, glow = A.crystal(40, 0, 30, 30, c)
		assert(state == "Ready" and glow <= 1 and glow >= 1 - c.breath)
	end,
	["the runes wake one after another as it charges"] = function()
		assert(A.runeLit(1, 8, 0, 0.1) == 0 and A.runeLit(1, 8, 0.1, 0.1) == 1)
		assert(A.runeLit(8, 8, 0.8, 0.1) < 0.5 and A.runeLit(8, 8, 1, 0.1) == 1)
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
	["direct hits wreck a field gun in two and the howitzer in four; near-misses only chip"] = function()
		local H = C.Hits
		local field = A.hitSource(nil, QF.kg, H)
		assert(field == H.field and A.hitSource(nil, HOW.kg, H) == H.howitzer)
		assert(A.hitSource("grenade", 0.3, H) == H.grenade and A.hitSource("staff3", 10, H) == H.staff3)
		local hit = A.gunHit(0, field, H.direct)
		assert(QF.hp / hit > 1 and QF.hp / hit <= 2) -- "a direct cannon hit or two"
		assert(math.ceil(HOW.hp / hit) >= 4) -- "4+ DIRECT cannon shots"
		assert(A.gunHit(H.direct + 0.01, field, H.direct) < hit / 5) -- the ground beside it: far less
		assert(A.gunHit(field.reach, field, H.direct) == 0)
		assert(A.gunHit(H.direct + 2, field, H.direct) > A.gunHit(H.direct + 6, field, H.direct))
		assert(A.gunHit(0, A.hitSource(nil, HOW.kg, H), H.direct) >= QF.hp) -- a howitzer shell on a field gun
		-- full staff beams straight on (user 2026-10-27: a lot more damage to built things, 5-6 for a trench)
		local beams = math.ceil(QF.hp / A.gunHit(0, H.staff3, H.direct))
		assert(beams >= 5 and beams <= 6, `5-6 full beams wreck a field gun ({beams})`)
		assert(A.gunHit(0, H.staff3, H.direct) < hit, "a beam is still less than a cannon shell")
	end,
	["a gun's damage stages every 25%, unusable from half"] = function()
		local at = C.Wreck.at
		assert(A.wreckStage(100, 100, at) == 0 and A.wreckStage(76, 100, at) == 0)
		assert(A.wreckStage(75, 100, at) == 1 and A.wreckStage(50, 100, at) == 2)
		assert(A.wreckStage(24, 100, at) == 3 and A.wreckStage(0, 100, at) == 4)
		assert(C.Wreck.unusable == 2 and at[C.Wreck.unusable] == 50) -- user 2026-10-25: "let's say 50%"
		assert(#C.Wreck.scorch == #at and #C.Wreck.tilt == #at and #C.Wreck.sink == #at)
	end,
	["the howitzer's mound is player height or less"] = function()
		local d = HOW.dig :: any
		assert(d.rimHeight <= 5) -- user 2026-10-25: "the mound should be player height or less"
		assert(d.depth + d.rimHeight >= 14.8) -- as much cover over the bed as before
	end,
	["the whole gun's jolt kicks back, settles and is done after its time"] = function()
		for _, J in C.Fx.Jolt do
			assert(A.joltAt(-0.1, J) == 0 and A.joltAt(J.time, J) == 0)
			assert(near(A.joltAt(J.rise, J), 1))
			assert(math.abs(A.joltAt(J.time - 1e-3, J)) < 0.05, "settled before it stops")
		end
	end,
	["the shot's looks and layers use real colours and every gun's look"] = function()
		local Palette = require("../src/shared/Config/Palette")
		local V = require("../src/shared/Config/Vfx").Muzzle
		for name, L in V.Looks do
			for _, c in { L.flash, L.glint, L.embers, L.ring or L.flash, table.unpack(L.fire) } do
				assert((Palette.Magic :: any)[c], `{name}: {c}`)
			end
			assert(C.Fx.Sound[name] and C.Fx.Sound.runout[name] and C.Fx.Jolt[name], name)
		end
		assert(V.Looks.Field.ring == nil and V.Looks.Magic.ring, "only the magic gun's smoke ring has runes")
	end,
	["the field gun stands on levelled bare earth with its hitbox, the howitzer keeps its block"] = function()
		-- user 2026-10-27: "the field cannon shouldnt have a platform ... make the ground its on lose its grass"
		local L = QF.level :: any
		local Foliage = require("../src/shared/Config/Foliage")
		assert(L and L.pad >= 0 and L.blend > 0 and QF.platform)
		assert(not table.find(Foliage.Materials, L.material) and L.material ~= "Water")
		assert(HOW.level == nil and HOW.dig)
	end,
	["the levelled ground is flat on the footprint and eases back to the ground past it"] = function()
		local lo, hi = { -2, -5 }, { 2, 5 }
		assert(A.levelAt(0, 0, lo, hi, 8, 10, 14) == 10)
		assert(A.levelAt(2, -5, lo, hi, 8, 10, 14) == 10, "its edge is still flat")
		assert(near(A.levelAt(6, 0, lo, hi, 8, 10, 14) :: number, 12), "half way out: half way back")
		assert(A.levelAt(10, 0, lo, hi, 8, 10, 14) == nil and A.levelAt(0, 13.1, lo, hi, 8, 10, 6) == nil)
		-- downhill too, and it only ever moves toward the ground as it was
		local last = 10
		for x = 2, 9.9, 0.1 do
			local h = A.levelAt(x, 0, lo, hi, 8, 10, 4) :: number
			assert(h <= last + 1e-9 and h >= 4, x)
			last = h
		end
		-- a corner measures from the box's corner
		assert(near(A.levelAt(2 + 3, 5 + 4, lo, hi, 10, 0, 10) :: number, 5))
	end,
	["a gun's ground is the box under it, craters stay off it"] = function()
		local lo, hi = { -2, -5 }, { 2, 5 }
		assert(A.onGround(0, 0, lo, hi) and A.onGround(2, 5, lo, hi) and A.onGround(-2, -5, lo, hi))
		assert(not A.onGround(2.1, 0, lo, hi) and not A.onGround(0, -5.1, lo, hi))
	end,
	["digging fixes a gun in its repair swings, usable again at 75%, never past whole"] = function()
		-- user 2026-10-27: "make it so you can fix a artillery by digging too", "damaged but usable status at 75%"
		local R = C.Repair
		assert(R.usable == 75)
		for key, g in C.Guns do
			assert(g.repair >= 1, key)
			local hp, what, n, usableAt = 0, nil, 0, nil
			while what ~= "whole" do
				hp, what = A.repaired(hp, g.hp, g.hp / g.repair, R.usable, usableAt == nil)
				n += 1
				if what == "usable" then
					usableAt = hp
				end
				assert(n <= g.repair, key)
			end
			assert(n == g.repair and hp == g.hp, key)
			assert(usableAt and usableAt >= g.hp * 0.75 - 1e-6, key)
			-- usable again past the stage it stopped being usable at
			assert(A.wreckStage(usableAt, g.hp, C.Wreck.at) < C.Wreck.unusable, key)
		end
		local hp, what = A.repaired(95, 100, 10, 75, false)
		assert(hp == 100 and what == "whole")
		hp, what = A.repaired(60, 100, 10, 75, false)
		assert(hp == 70 and what == nil, "not broken: nothing to say")
		hp, what = A.repaired(60, 100, 10, 75, true)
		assert(hp == 70 and what == nil, "broken under 75%: still broken")
		hp, what = A.repaired(70, 100, 10, 75, true)
		assert(hp == 80 and what == "usable")
	end,
}
