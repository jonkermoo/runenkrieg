--!strict
local C = require("../src/shared/Config/Artillery")
local A = require("../src/shared/Rules/Artillery")
local Assets = require("../src/shared/Config/Assets")
local Map1 = require("../src/shared/Config/Maps/Map1")
local Playtest = require("../src/shared/Config/Maps/Playtest")

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
	["a bot's BotId is told from a player's UserId"] = function()
		assert(A.botGunner(-3) and not A.botGunner(12345) and not A.botGunner(nil) and not A.botGunner("x"))
	end,
	["a bot gunner's tracks each name a priority over the hold, in a player's order"] = function()
		local rank = { Action = 1, Action2 = 2, Action3 = 3, Action4 = 4 }
		local P = C.BotPose
		for _, key in { "brace", "load", "reload", "crank", "stand" } do
			assert(rank[(P :: any)[key]] and rank[(P :: any)[key]] > 1, key)
		end
		assert(rank[P.brace] > rank[P.load] and rank[P.load] > rank[P.crank] and P.stand == P.crank)
	end,
	["a bot gunner's brace lands its pull on the shot"] = function()
		assert(near(A.braceWait(10, 10, 2, 0.45) :: number, 1.55), "the howitzer: the pull at its charge's end")
		assert(A.braceWait(10, 10, 0.3, 0.45) == 0, "a charge shorter than the pull: at once")
		assert(near(A.braceWait(10, 11, 2, 0.45) :: number, 0.55), "seen part way: the rest")
		assert(A.braceWait(10, 11.6, 2, 0.45) == 0, "seen late: at once")
		assert(A.braceWait(10, 12.5, 2, 0.45) == nil, "the shot gone: none")
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
	["the howitzer's ring mount turns right round, held past the back (user 2026-11-02)"] = function()
		-- holding the turn key: the client's aim leads the laid yaw by Aim.lead
		local s = { yaw = 0, traverse = 0, elevation = HOW.elevation[1] }
		for _ = 1, math.ceil(400 / (HOW.traverseRate * 0.05)) do
			s = A.lay(s, A.wrap(s.yaw + s.traverse + C.Aim.lead), s.elevation, HOW, 0.05)
		end
		assert(s.yaw == 0 and s.traverse > 380, "on past 180 and round again: " .. s.traverse)
		-- an aim just behind it goes the short way, from either side
		s = A.lay({ yaw = 0, traverse = 175, elevation = 45 }, -175, 45, HOW, 1)
		assert(near(s.traverse, 175 + HOW.traverseRate), "on through 180, not back round")
		s = A.lay({ yaw = 0, traverse = 540, elevation = 45 }, 170, 45, HOW, 100)
		assert(near(A.wrap(s.yaw + s.traverse), 170, 1e-4) and near(s.traverse, 530), "a whole turn on: still short")
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
	["the howitzer recharges with nobody on it; the field gun and MG start their reload over (user 2026-11-03)"] = function()
		assert(HOW.keepsReload == true, "the howitzer's crystal fills unmanned")
		assert(not QF.keepsReload and not C.Guns.mg08.keepsReload, "user 2026-11-01: restarted if cancelled")
	end,
	["the howitzer's breech clears its turntable even at full elevation"] = function()
		local c = HOW.recoilClear
		local e = HOW.elevation[2]
		local r = A.recoilLength(HOW.recoil, e, HOW.trunnion[2], c)
		local a = math.rad(e)
		assert(HOW.trunnion[2] - (c.along + r) * math.sin(a) - c.below * math.cos(a) >= c.floor - 1e-6)
	end,
	["a shell misses by a little: mostly half its radius, rarely on the aim, never past it"] = function()
		assert(QF.miss and HOW.miss and C.Guns.mg08.miss == nil, "the field gun and howitzer only")
		local right, beyond = A.miss(36, 1, 1, 0)
		assert(near(right, 0) and near(beyond, 36), "the most: straight beyond")
		right, beyond = A.miss(36, 0.5, 0.5, 0.25)
		assert(near(right, 18) and near(beyond, 0, 1e-9), "half the radius, to the right")
		math.randomseed(7)
		local close, off, n = 0, 0, 4000
		for _ = 1, n do
			local x, z = A.miss(36, math.random(), math.random(), math.random())
			local d = math.sqrt(x * x + z * z)
			assert(d <= 36 + 1e-9)
			if d < 3.6 then
				close += 1
			end
			off += d
		end
		assert(close / n < 0.05, "rarely right on the aim")
		assert(near(off / n, 18, 1), "mostly about half off")
	end,
	["a miss is turned into a lay: beyond is faster, right is a turn to the right"] = function()
		local yaw, speed = A.missLay(1000, 0, 210)
		assert(near(yaw, 0) and near(speed, math.sqrt(1.21)))
		local x, z = A.landing(BORE, { yaw = 0, traverse = 0, elevation = 10 }, 0, 0)
		local reach = math.sqrt((x :: number) ^ 2 + (z :: number) ^ 2)
		yaw = A.missLay(reach, 30, 0)
		local x2 = A.landing(BORE, { yaw = 0, traverse = yaw, elevation = 10 }, 0, 0)
		assert(near((x2 :: number) - (x :: number), 30, 1), "30 studs to the right (+X facing -Z)")
		assert(select(2, A.missLay(0, 5, 5)) == 1, "no reach: no change")
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
		assert(math.ceil(HOW.hp / (hit / HOW.armour)) >= 4) -- "4+ DIRECT cannon shots"
		-- every gun on the 100 scale like every structure (its armour keeping the howitzer's old 240 in hits)
		assert(QF.hp == 100 and HOW.hp == 100 and (QF.armour or 1) == 1 and near(HOW.hp * HOW.armour, 240))
		assert(A.gunHit(H.direct + 0.01, field, H.direct) < hit / 5) -- the ground beside it: far less
		assert(A.gunHit(field.reach, field, H.direct) == 0)
		assert(A.gunHit(H.direct + 2, field, H.direct) > A.gunHit(H.direct + 6, field, H.direct))
		assert(A.gunHit(0, A.hitSource(nil, HOW.kg, H), H.direct) >= QF.hp) -- a howitzer shell on a field gun
		-- full staff beams straight on (user 2026-10-27: a lot more damage to built things, 5-6 for a trench)
		local beams = math.ceil(QF.hp / A.gunHit(0, H.staff3, H.direct))
		assert(beams >= 5 and beams <= 6, `5-6 full beams wreck a field gun ({beams})`)
		assert(A.gunHit(0, H.staff3, H.direct) < hit, "a beam is still less than a cannon shell")
	end,
	["a gun's damage stages every 25%"] = function()
		local at = C.Wreck.at
		assert(A.wreckStage(100, 100, at) == 0 and A.wreckStage(76, 100, at) == 0)
		assert(A.wreckStage(75, 100, at) == 1 and A.wreckStage(50, 100, at) == 2)
		assert(A.wreckStage(24, 100, at) == 3 and A.wreckStage(0, 100, at) == 4)
		assert(#C.Wreck.scorch == #at and #C.Wreck.tilt == #at and #C.Wreck.sink == #at)
	end,
	["the Rune howitzer is semi dug: a shallow pit inside its sandbag ring, walked out of up its ramp"] = function()
		-- user 2026-11-02: "we can keep the howizer semi dugged, but have sandbags around it"
		local Build = require("../src/shared/Config/Build")
		local d = HOW.dig :: any
		local n = Build.GunRing.artillery_howitzer
		local ring = n.ring.bag / (2 * math.sin(math.pi / n.ring.sides))
		local inner = ring - n.ring.bag / 4 -- (a bag lies ~1.6 deep across the ring's line)
		assert(d.depth <= 4 and d.rim == 0 and d.rimHeight == 0 and not d.slabs, "shallow, no mound, no slabs")
		local top = d.radius + d.depth / math.tan(math.rad(d.wall))
		assert(top < inner, `the pit's wall top {top} inside the bags {inner}`)
		-- the ramp is up at the ground before the bags (their ground stays whole), walkable (under 50 degrees), two
		-- voxels wide
		assert(d.radius + d.ramp.length < inner)
		assert(math.deg(math.atan(d.depth / d.ramp.length)) < 50 and d.ramp.width >= 8)
		-- the gunner stands on the turntable inside the pit's floor
		assert(math.sqrt(HOW.crew[1] ^ 2 + HOW.crew[2] ^ 2) + 1 < d.radius)
	end,
	["the howitzer's barrel engravings rise through the charge-up and fade after the shot (user 2026-11-02)"] = function()
		local E = C.Crystal.engraving
		assert(table.find(HOW.barrel, E.part), "they recoil with the barrel")
		local charge = HOW.charge
		assert(A.engravingShown(-1, charge, 100, E.fade) == 0, "unseen before the charge-up")
		assert(near(A.engravingShown(charge / 2, charge, 100, E.fade), 0.5))
		assert(A.engravingShown(charge * 0.99, charge, 100, E.fade) > 0.95, "nearly full by the shot")
		assert(near(A.engravingShown(charge, charge, 0, E.fade), 1), "lit at the shot")
		assert(near(A.engravingShown(charge + E.fade / 2, charge, E.fade / 2, E.fade), 0.5))
		assert(A.engravingShown(charge + E.fade, charge, E.fade, E.fade) == 0, "gone again")
		assert(A.engravingShown(1e9, charge, 5, E.fade) == 0, "unseen through the reload")
	end,
	["the Rune howitzer hits harder than the field gun, over less ground (user 2026-11-02)"] = function()
		-- "make it stronger than the field cannon, but less AOE but keep direct damage strong, just scale it with the
		-- lowered AOE radius", "it should still be a deadly weapon": its blast kills further out than the field gun's
		-- fragments, but hurts over less ground than they do, and less than the 42 cm's 340 kg did
		local Blast = require("../src/shared/Rules/Blast")
		local D = require("../src/shared/Config/Damage").Blast
		local kill = Blast.reachOf(D.Soldier.kill, HOW.kg, D)
		local hurt = Blast.reachOf(D.Soldier.from, HOW.kg, D)
		assert(kill > QF.fragments.lethal and kill > HOW.fragments.lethal, `kills to {kill}`)
		assert(hurt < QF.fragments.wound and HOW.fragments.wound <= hurt + 1, `hurts to {hurt}`)
		assert(hurt < Blast.reachOf(D.Soldier.from, 340, D))
		assert(math.abs(HOW.zone - hurt) < 2, "its impact zone is where its blast still hurts")
		-- trenches: it still buries what it hits, over a smaller reach than before
		local S = require("../src/shared/Config/Build").Structures
		assert(S.howitzer.hit >= 100 and S.howitzer.reach < 20 and S.howitzer.hit > S.field.hit)
		assert(C.Hits.howitzer.direct > C.Hits.field.direct and C.Hits.howitzer.reach < 30)
	end,
	["the MG gunner's stances blend by the lay: level at 0, all low or high at its stops"] = function()
		local MG = C.Guns.mg08
		local lim = MG.elevation
		local a, b, c = A.mgStand(0, lim)
		assert(a == 0 and b == 1 and c == 0)
		a, b, c = A.mgStand(lim[1], lim)
		assert(near(a, 1) and near(b, 0) and c == 0)
		a, b, c = A.mgStand(lim[2], lim)
		assert(a == 0 and near(b, 0) and near(c, 1))
		a, b, c = A.mgStand(lim[2] / 2, lim)
		assert(near(a + b + c, 1) and near(c, 0.5))
		assert(MG.mg.stand.low and MG.mg.stand.level and MG.mg.stand.high)
	end,
	["the MG's box reload: the box off its tray into the hands, put down, the full one up and on, the belt fed"] = function()
		local MG = C.Guns.mg08
		local r = MG.mg.reload
		assert(r.lift < r.drop and r.drop < r.take and r.take < r.set and r.set < r.fed and r.fed < MG.reload)
		local on, held, belt = A.mgReloadShows(-1, r, 100)
		assert(on and not held and belt == nil, "no reload: as the box holds")
		on, held, belt = A.mgReloadShows((r.lift + r.drop) / 2, r, 100)
		assert(not on and held and belt == 0, "the empty box in the hands")
		on, held = A.mgReloadShows((r.drop + r.take) / 2, r, 100)
		assert(not on and not held, "put down, the full one not yet taken")
		on, held = A.mgReloadShows((r.take + r.set) / 2, r, 100)
		assert(not on and held, "the full one carried")
		on, held, belt = A.mgReloadShows((r.set + r.fed) / 2, r, 100)
		assert(on and not held and belt == 0, "on its tray, the belt not yet in")
		_, _, belt = A.mgReloadShows(r.fed, r, 100)
		assert(belt == 100, "fed")
	end,
	["the MG's jolt is small and settled before its next shot"] = function()
		local J, MG = C.Fx.Jolt.MG, C.Guns.mg08
		assert(J.time < A.mgInterval(MG.mg.rate), "done between shots: full auto never stacks it")
		assert(J.lift < C.Fx.Jolt.Field.lift / 4 and J.back < C.Fx.Jolt.Field.back / 4)
	end,
	["a stray's pixels on screen grow with its angle and the screen, and shrink with the field of view"] = function()
		assert(near(A.mgPixels(0, 70, 1000), 0))
		local p = A.mgPixels(1, 70, 1000)
		assert(p > 0 and A.mgPixels(2, 70, 1000) > p and A.mgPixels(1, 70, 2000) > p and A.mgPixels(1, 90, 1000) < p)
		assert(near(A.mgPixels(35, 70, 1000), 500, 1e-6), "half the field of view reaches the screen's edge")
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
	["manned once built to 100 HP, then while at or above half (players and bots)"] = function()
		-- user 2026-11-03: "available until CONTRUCTION to 100 HP. after constructed, it can still be operated until low
		-- HP (50%)"
		local M = C.Man
		assert(M.built == 100 and M.keep == 50)
		assert(not A.mannable(99, 100, false, M), "still being built")
		assert(A.mannable(100, 100, false, M), "built")
		assert(A.mannable(100, 100, true, M) and A.mannable(50, 100, true, M), "built, at half")
		assert(not A.mannable(49.9, 100, true, M), "under half")
		assert(A.mannable(120, 240, true, M) and not A.mannable(119, 240, true, M), "the howitzer's 240 HP")
		assert(not A.mannable(0, 0, true, M))
	end,
	["digging fixes a gun in its repair swings, usable again at half, never past whole"] = function()
		-- user 2026-10-27: "make it so you can fix a artillery by digging too"; 2026-11-03: operated down to 50%
		local R = { usable = C.Man.keep }
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
			assert(usableAt and usableAt >= g.hp * 0.5 - 1e-6, key)
			assert(A.mannable(usableAt, g.hp, true, C.Man), key)
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
	["the MG fires 450 a minute from a box of 100 and swaps the box in 12 s (the design)"] = function()
		local MG = C.Guns.mg08
		local m = assert(MG.mg)
		assert(m.rate == 450 and m.box == 100 and MG.reload == 12)
		assert(near(A.mgInterval(m.rate), 60 / 450))
		assert(A.mgReady(1, nil, 0) and A.mgReady(5, 10, 10) and not A.mgReady(0, nil, 0) and not A.mgReady(5, 10, 9.9))
		local D = require("../src/shared/Config/Damage")
		local t = D.Weapons[m.class]
		assert(t and t.Torso * 3 >= 100 and t.Torso * 2 < 100, "three body hits")
	end,
	["one click is one MG shot, held fire goes at its rate one shot a frame"] = function()
		-- user 2026-11-01: "one click is one shot. two shouldnt come out at once, two shouldnt be fired sequenttially"
		local m = C.Guns.mg08.mg :: any
		local gap = A.mgInterval(m.rate)
		assert(m.tap > gap and m.tap <= 0.3, "a click's length gives one shot, a hold still goes full auto")
		-- a click after a long quiet: one shot, nothing more that frame or while it is held for a normal click
		local fires, nextShot = A.mgShot(0, true, true, 100, gap, m.tap)
		assert(fires and near(nextShot, 100 + m.tap))
		local again = A.mgShot(nextShot, false, true, 100, gap, m.tap)
		assert(not again, "no second shot in the same frame")
		assert(not A.mgShot(nextShot, false, true, 100 + m.tap - 0.01, gap, m.tap), "nor while the click is held")
		assert(not A.mgShot(nextShot, false, false, 100 + 5, gap, m.tap), "let go: never")
		-- held on: full auto at its rate, one shot a frame, no burst saved up after a slow frame
		local t, shots = 100 + m.tap, 0
		while t < 100 + m.tap + 1 do
			local f
			f, nextShot = A.mgShot(nextShot, false, true, t, gap, m.tap)
			if f then
				shots += 1
			end
			t += 1 / 60
		end
		assert(math.abs(shots - 1 / gap) <= 1, `{shots} a second held`)
		local _, late = A.mgShot(100, false, true, 105, gap, m.tap)
		assert(late == 105, "a hitch fires once and keeps going from now")
		-- a pull right after a shot waits for it, then fires its own one
		assert(not A.mgShot(100.1, true, false, 100.05, gap, m.tap))
		assert((A.mgShot(100.1, true, false, 100.1, gap, m.tap)))
	end,
	["the MG's barrel kick is big enough to see and home before the next round"] = function()
		local MG = C.Guns.mg08
		assert(MG.recoil >= 0.25, "visible")
		assert(MG.recoilTimes[1] + MG.recoilTimes[2] < A.mgInterval(MG.mg.rate), "settled between shots")
		assert(A.recoilAt(MG.recoilTimes[1], MG.recoil, MG.recoilTimes) == MG.recoil)
		assert(A.recoilAt(MG.recoilTimes[1] + MG.recoilTimes[2], MG.recoil, MG.recoilTimes) == 0)
	end,
	["the MG's spread grows over a burst and settles when it stops"] = function()
		local s = C.Guns.mg08.mg.spread
		assert(near(A.mgSpread(0, s), s.min) and near(A.mgSpread(1, s), s.max))
		local heat = 0
		for _ = 1, 100 do
			heat = A.mgHeat(heat, 1, A.mgInterval(450), s)
		end
		assert(heat > 0.5 and heat <= 1, "a long burst runs hot")
		assert(A.mgHeat(heat, 0, 10, s) == 0, "and cools off")
		for _ = 1, 50 do
			local dy, de = A.mgStray(2, math.random(), math.random())
			assert(dy * dy + de * de <= 4 + 1e-9)
		end
	end,
	["the MG (the M2) goes up tripod, gun, ammo can, belt, each appearing in its quarter"] = function()
		local MG = C.Guns.mg08
		local order = { "Carriage", "Cradle", "Box", "Belt" }
		for i, g in MG.assembly do
			assert(g.at == i and g.names[1] == order[i], `quarter {i} sets up {order[i]}`)
		end
	end,
	["a barrel warms with each shot and cools off, glowing from the tip back"] = function()
		local H = C.Guns.mg08.heat :: any
		local heat = 0
		for _ = 1, 30 do
			heat = A.heatStep(heat, 1, 0, H.per, H.cool)
		end
		assert(heat > 0.3 and heat < 1, "warm after a burst")
		assert(A.heatStep(heat, 0, 60, H.per, H.cool) == 0, "cold a minute later")
		assert(A.heatStep(0.9, 50, 0, H.per, H.cool) == 1, "never past hot")
		local n, lead = H.segments, C.Heat.lead
		assert(A.heatGlow(0.2, 1, n, lead) > 0 and A.heatGlow(0.2, n, n, lead) == 0, "the tip glows first")
		for i = 1, n do
			assert(A.heatGlow(0, i, n, lead) == 0 and A.heatGlow(1, i, n, lead) == 1)
		end
	end,
	["the MG's count goes down with each shot seen, and is full the moment its reload ends"] = function()
		assert(A.mgShown(60, 100, 0, nil, 10, 11) == 60)
		assert(A.mgShown(60, 100, 3, nil, 10, 11) == 57, "three shots seen since the server's 60")
		assert(A.mgShown(2, 100, 5, nil, 10, 11) == 0, "never under empty")
		assert(A.mgShown(0, 100, 0, 20, 10, 19) == 0, "still reloading")
		assert(A.mgShown(0, 100, 0, 20, 10, 20.01) == 100, "the reload over, before the server's refill lands")
		assert(A.mgShown(97, 100, 1, 20, 21, 22) == 96, "firing again after the refill")
	end,
	["the MG's ammo can stands still as the gun turns, named all the same"] = function()
		local MG = C.Guns.mg08
		for _, name in { "BoxKit", "BoxTrim", "BoxFittings", "Belt" } do
			assert(table.find(MG.fixed :: any, name) and not table.find(MG.mount, name), name)
		end
		assert(
			table.find(MG.mount, "Rounds01") and table.find(MG.mount, "Links01"),
			"the belt's rounds still bend to the feed"
		)
	end,
	["the MG throws off a spent case and a link, from belt parts it has, each with a clink"] = function()
		local Cases = require("../src/shared/Config/Cases")
		local MG = C.Guns.mg08
		local spent = (MG.mg :: any).spent
		assert(spent.case and spent.link)
		for key, piece in spent do
			assert(table.find(MG.mount, piece.part), key)
			assert(Cases.Sounds[piece.sound] and #Cases.Sounds[piece.sound].variants > 0, key)
		end
		assert(spent.case.push[2] < 0, "the M2's case drops out of the bottom")
		assert(spent.link.push[1] < 0, "fed from the right, its links go out of the left")
	end,
	["the MG's reload sounds play in order, all within the reload, each a hand's noise"] = function()
		local MG = C.Guns.mg08
		local R = (MG.mg :: any).reload
		local last = -1
		for _, step in R.sounds do
			assert(step.at > last and step.at < MG.reload, step.at)
			last = step.at
			local layers = if step.sound.id then { step.sound } else step.sound
			assert(#layers >= 1, step.at)
			for _, s in layers do
				assert(s.id and s.profile == "Mechanism", `{step.at}: a hand's noise, heard close by (no gunshot)`)
				assert(not s.stop or s.stop > (s.start or 0), step.at)
			end
		end
		assert(last >= MG.reload - 1.5, "on into the hands back on the grips")
		assert((MG.mg :: any).boom.id and (MG.mg :: any).jingle.id)
	end,
	["the MG and the field gun warm and kick their gunner, the howitzer neither"] = function()
		for _, key in { "mg08", "artillery_qf18" } do
			local g = C.Guns[key]
			assert(g.heat and g.kick, key)
		end
		assert(not C.Guns.artillery_howitzer.heat and not C.Guns.artillery_howitzer.kick)
	end,
	["the MG gunner's eye is behind the rear sight on the sight line, and lifts with the gun"] = function()
		local MG = C.Guns.mg08
		local x, y, z = A.eye(MG, 0, 0)
		assert(near(x, 0) and near(y, MG.mg.eye[2]) and near(z, MG.mg.eye[3]))
		local _, yUp = A.eye(MG, 0, 10)
		assert(yUp < y, "the eye is behind the trunnion: raising the muzzle lowers it")
		local xl = A.eye(MG, 15, 0)
		assert(xl > 0, "turned left the eye (behind) swings right")
	end,
	["the MG gunner's hip eye sees over the shield at the gun's lowest, and turns with the mount"] = function()
		local MG = C.Guns.mg08
		local _, y, z = A.over(MG, 0)
		local S = MG.mg.shield
		local drop = (z - S.z) * math.tan(math.rad(-MG.elevation[1]))
		assert(y - drop > S.top, "the line down the lay at its lowest clears the shield's top")
		local _, yt = A.over(MG, 15)
		assert(near(yt, y), "the gun's traverse leaves its height")
		assert(A.over(MG, 15) > 0, "turned left the eye (behind) swings right")
	end,
	["the mouse lays the MG within its stops, never swinging the gun"] = function()
		local MG = C.Guns.mg08
		local y, e = A.mgLay(30, 0, 30, -10, 0, MG)
		assert(near(y, 30 + 10 * MG.mg.look) and e == 0, "the mouse moved left turns it left (yaw up)")
		y = A.mgLay(30, 0, 30, -1e6, 0, MG)
		assert(near(y, 30 + MG.traverse), "stops at its traverse")
		y = A.mgLay(170, 0, 170, -1e6, 0, MG)
		assert(near(y, A.wrap(170 + MG.traverse)), "across 180")
		local _, up = A.mgLay(0, 0, 0, 0, -1e6, MG)
		assert(up == MG.elevation[2])
		local _, down = A.mgLay(0, 0, 0, 0, 1e6, MG)
		assert(down == MG.elevation[1])
	end,
	["solve finds the low and high arcs that land on a point, nil past the reach"] = function()
		local v, g = 400, GRAVITY
		local low = A.solve(v, g, 500, 0, false) :: number
		local high = A.solve(v, g, 500, 0, true) :: number
		assert(low < 45 and high > 45 and near(low + high, 90, 1e-6), "on flat ground the two arcs add up to 90")
		assert(near(A.range(v, low, g), 500, 1e-3) and near(A.range(v, high, g), 500, 1e-3))
		assert(A.solve(v, g, v * v / g + 1, 0, false) == nil, "past the 45 degree range")
		assert((A.solve(v, g, 500, 50, false) :: number) > low, "a point up a hill takes a higher lay")
	end,
	["layFor lays each gun within its limits, the howitzer on its high arc"] = function()
		for key, g in C.Guns do
			if g.mg then
				continue
			end
			local mid = (g.elevation[1] + g.elevation[2]) / 2
			local d = A.range(g.speed, mid + (g.aimTilt or 0), g.gravity)
			local e = A.layFor(g, d, 0)
			assert(e and near(e, mid, 1e-6), key .. " lays where that range is")
			assert(A.layFor(g, g.speed * g.speed / g.gravity * 1.01, 0) == nil, key .. " out of reach")
		end
		local e = A.layFor(HOW, A.range(HOW.speed, 60, HOW.gravity), 0) :: number
		assert(
			near(e + (HOW.aimTilt or 0), 60, 1e-6),
			"the howitzer lays the high arc (its low one is under its limits)"
		)
	end,
	["no shell lands past one sector's spacing plus the margin, on either map (user 2026-11-03)"] = function()
		local R = C.Reach
		assert(R.sectors == 1 and R.margin == 90)
		for _, name in { "Map1", "LanternMeadows" } do
			local map = require(`../src/shared/Config/Maps/{name}`) :: any
			local span = A.sectorSpan(map.sectors)
			assert(span > 400 and span < 450, `{name} span {span}`)
			local cap = A.reachCap(span, R)
			for key, g in { qf = QF, how = HOW } do
				local lims = A.capped(g, cap)
				assert(lims[1] >= g.elevation[1] and lims[2] <= g.elevation[2] and lims[1] <= lims[2], key)
				-- every lay within the limits lands within the cap, and the limit itself lands right at it
				for k = 0, 10 do
					local e = lims[1] + (lims[2] - lims[1]) * k / 10
					assert(A.range(g.speed, e + (g.aimTilt or 0), g.gravity) <= cap + 1e-3, `{name} {key} {e}`)
				end
				local edge = if g == HOW then lims[1] else lims[2]
				assert(near(A.range(g.speed, edge + (g.aimTilt or 0), g.gravity), cap, 1e-3), `{name} {key} edge`)
				-- out past it: no lay; inside it: a lay within the limits
				assert(A.layFor(g, cap + 20, 0, lims) == nil, `{name} {key} past the cap`)
				local e = A.layFor(g, cap - 20, 0, lims)
				assert(e and e >= lims[1] - 1e-6 and e <= lims[2] + 1e-6, `{name} {key} within it`)
			end
			-- the field gun still reaches its shortest ~300: one sector's worth of lay, raised only part of its dial
			local q = A.capped(QF, cap)
			assert(q[1] == QF.elevation[1] and q[2] < 0, "the field gun stops low on its dial")
			assert(A.capped(HOW, cap)[1] > 55, "the howitzer stops high")
		end
		-- ground lower out there (a gun on a hill firing into a valley): it stops lower, its shell coming down at the
		-- cap on that ground; higher ground: it may raise further
		local cap = 500
		local flat, down, up = A.capped(QF, cap), A.capped(QF, cap, -15), A.capped(QF, cap, 30)
		assert(down[2] < flat[2] and up[2] > flat[2])
		local launch = down[2] + QF.aimTilt
		local vx, vy = QF.speed * math.cos(math.rad(launch)), QF.speed * math.sin(math.rad(launch))
		local t = cap / vx
		assert(near(vy * t - QF.gravity * t * t / 2, -15, 1e-3), "it comes down on that ground at the cap")
		assert(A.capped(HOW, cap, -40)[1] > A.capped(HOW, cap)[1], "the howitzer stops higher over lower ground")
		-- the lay stops at the limits, a machine gun keeps its own
		local lims = { -5, -2.5 }
		local lay = A.lay({ yaw = 0, traverse = 0, elevation = -3 }, 0, 16, QF, 10, lims)
		assert(near(lay.elevation, -2.5, 1e-6))
		local MG = C.Guns.mg08
		local m = A.capped(MG, 100)
		assert(m[1] == MG.elevation[1] and m[2] == MG.elevation[2])
		assert(A.sectorSpan({ { x = 0, z = 0 } }) == 0)
	end,
	["the field gun's shell arcs a touch higher and slower, the same shortest shot (user 2026-11-03)"] = function()
		-- "just the TINIEST more arc": 420 studs/s with +8.5 (was 450 with +8)
		assert(QF.speed == 420 and QF.aimTilt == 8.5)
		local function shot(speed: number, d: number): (number, number)
			local e = A.solve(speed, QF.gravity, d, 0, false) :: number
			local vy = speed * math.sin(math.rad(e))
			return vy * vy / (2 * QF.gravity), 2 * vy / QF.gravity -- (its top, its flight)
		end
		local top, t = shot(420, 420)
		local top0, t0 = shot(450, 420)
		assert(top > top0 * 1.1 and top < top0 * 1.2, "a little higher")
		assert(t > t0 * 1.05 and t < t0 * 1.1, "a little slower")
	end,
	["layFor on a machine gun is the straight line within its range and limits"] = function()
		local MG = C.Guns.mg08
		local e = A.layFor(MG, 100, 0) :: number
		assert(near(e + (MG.aimTilt or 0), 0))
		assert(A.layFor(MG, MG.mg.range + 1, 0) == nil, "past its range")
		assert(A.layFor(MG, 10, 100) == nil, "past its elevation")
		assert(A.mgTurns(MG, 0, MG.traverse) and not A.mgTurns(MG, 0, MG.traverse + 1))
		assert(A.mgTurns(MG, 170, A.wrap(170 + MG.traverse)), "across 180")
	end,
	["laid: within the tolerance of the wanted world yaw and elevation"] = function()
		local lay = { yaw = 170, traverse = 15, elevation = 10 }
		assert(A.laid(lay, -175, 10, 0.5), "across 180")
		assert(not A.laid(lay, -170, 10, 0.5) and not A.laid(lay, -175, 12, 0.5))
	end,
	["only a teammate takes a gun over from a bot"] = function()
		assert(A.mayTakeOver("uniform1", "uniform1"))
		assert(not A.mayTakeOver("uniform2", "uniform1") and not A.mayTakeOver(nil, nil))
	end,
	["a shot comes down along its lay, its range out from the muzzle"] = function()
		for _, g in { QF, HOW } do
			local e = (g.elevation[1] + g.elevation[2]) / 2
			local mx, _, mz = A.muzzle(g, 0, e)
			local r = A.range(g.speed, e + (g.aimTilt or 0), g.gravity)
			local x, z = A.landing(g, { yaw = 0, traverse = 0, elevation = e }, 100, 50)
			assert(x and z and near(x, 100 + mx, 1e-3) and near(z, 50 + mz - r, 1e-3))
			-- turned a quarter round (whole gun or mount alike): toward -X
			local x2, z2 = A.landing(g, { yaw = 60, traverse = 30, elevation = e }, 0, 0)
			assert(x2 and z2 and x2 < -r * 0.9 and math.abs(z2) < r * 0.1)
		end
	end,
	["near a spawn: within the margin of a spawn zone or round a wave line"] = function()
		local zones = { West = { minX = 0, maxX = 10, minZ = 0, maxZ = 10 } }
		assert(A.nearSpawn(5, 5, zones, {}, 0) and A.nearSpawn(-19, 5, zones, {}, 20))
		assert(A.nearSpawn(24, 24, zones, {}, 20) and not A.nearSpawn(25, 25, zones, {}, 20))
		assert(not A.nearSpawn(-21, 5, zones, {}, 20))
		local lines = { { 500, 0, 24 } }
		assert(A.nearSpawn(543, 0, {}, lines, 20) and not A.nearSpawn(545, 0, {}, lines, 20))
		-- every map's spawn zones count (one rule for every map)
		for _, map in { Map1, Playtest } :: { any } do
			for _, r in map.spawnZones do
				assert(A.nearSpawn((r.minX + r.maxX) / 2, (r.minZ + r.maxZ) / 2, map.spawnZones, {}, C.SpawnGuard.gap))
			end
		end
	end,
	["the gunner's sight: points over the screen box, fades eased both ways (user 2026-11-02)"] = function()
		local F = C.ViewFade
		local pts = A.sightPoints(F.cols, F.rows, F.box)
		assert(#pts == F.cols * F.rows)
		assert(pts[1][1] == F.box[1] and pts[1][2] == F.box[2], "top left first")
		assert(pts[#pts][1] == F.box[3] and pts[#pts][2] == F.box[4], "bottom right last")
		local one = A.sightPoints(1, 1, { 0, 0, 1, 1 })
		assert(#one == 1 and one[1][1] == 0.5 and one[1][2] == 0.5, "one point: the middle")
		assert(A.fadeStep(0, 0.8, 4, 0.1) == 0.4 and A.fadeStep(0.7, 0.8, 4, 0.1) == 0.8, "toward it, not past")
		assert(A.fadeStep(0.8, 0, 4, 0.1) == 0.4 and A.fadeStep(0.1, 0, 4, 0.1) == 0, "back, not past")
		assert(F.see > 0 and F.see < 1, "faded, not gone")
	end,
}
