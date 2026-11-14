--!strict
-- Limited ammunition and the Supplier's bag (user 2026-11-14): Rules/Firing spare rounds, Rules/Supply.
local Cfg = require("../src/shared/Config/Firing")
local C = require("../src/shared/Config/Classes")
local SupplyCfg = require("../src/shared/Config/Supply")
local F = require("../src/shared/Rules/Firing")
local R = require("../src/shared/Rules/Supply")
local W = require("../src/shared/Config/Weapons")

local function gun(capacity: number, clip: string, extra: { [string]: any }?): F.Gun
	local g: any = {
		capacity = capacity,
		clip = clip,
		boltTime = 0.9,
		reloadTime = 2,
		fireTime = 0.15,
		openAt = Cfg.BoltCycle.back,
		reloadOpenAt = Cfg.ReloadCycle.back,
		singleOpen = 0.3,
		singleRound = 0.4,
		singleClose = 0.3,
	}
	for k, v in extra or {} do
		g[k] = v
	end
	return g
end

-- fires every round in the gun (working the action between shots); returns the time after
local function empty(s: F.State, g: F.Gun, t: number): number
	while F.rounds(s) > 0 or s.spent do
		local n = F.next(s, t)
		if n == "Fire" then
			F.fire(s, g, t)
		elseif n == "Bolt" then
			F.bolt(s, g, t)
		elseif n == "Open" or n == "Dry" then
			break
		end
		t += 5
	end
	return t
end

return {
	["the user's spare rounds (2026-11-14): bolt 8 clips, semi 5, pistol 6, shotgun 25 shells, the staff none"] = function()
		local want = {
			rifle_g98 = 40,
			rifle_smle = 40,
			rifle_m91 = 48,
			rifle_mondragon = 40,
			rifle_remington8 = 50,
			rifle_winchester1907 = 75,
			pistol_c96 = 36,
			pistol_webley = 36,
			pistol_nagant = 42,
			shotgun_m1897 = 25,
		}
		for name, n in want do
			local w = W[name] :: any
			assert(F.spareFor(w.class, w.ammo.capacity, Cfg.Spare) == n, `{name}: {n} spare rounds`)
		end
		assert(F.spareFor("Staff", 0, Cfg.Spare) == nil, "the staff keeps its mana")
		assert(F.new(gun(5, "Stripper")).spare == nil, "no spare given: unlimited (bots)")
	end,
	["a clip reload takes its rounds from the spare, short when the spare is"] = function()
		local g = gun(5, "Stripper")
		local s = F.new(g, 7)
		local t = empty(s, g, 0)
		assert(F.reload(s, g, t), "a full clip")
		assert(F.rounds(s) == 5 and s.spare == 2, `5 in, 2 left (got {F.rounds(s)}, {s.spare})`)
		t = empty(s, g, t + 10)
		assert(F.reload(s, g, t), "the short clip")
		assert(F.rounds(s) == 2 and s.spare == 0, "the last 2")
		t = empty(s, g, t + 10)
		local ok, why = F.reload(s, g, t)
		assert(not ok and why == "no spare" and not F.canReload(s, g), "nothing left to load")
	end,
	["an en-bloc clip and a box: the same"] = function()
		local carcano = gun(6, "Enbloc")
		local s = F.new(carcano, 4)
		local t = empty(s, carcano, 0)
		assert(F.reload(s, carcano, t) and F.rounds(s) == 4 and s.spare == 0, "a short clip of 4")
		local box = gun(15, "Box", { auto = true })
		local b = F.new(box, 20)
		F.fire(b, box, 0)
		F.fire(b, box, 1)
		assert(F.reload(b, box, 2) and b.magazine == 15 and b.spare == 18, "a top-up takes only the 2 fired")
	end,
	["single rounds go in only as many as the spare holds, taken as they go in"] = function()
		local g = gun(5, "Loose")
		local s = F.new(g, 2)
		F.fire(s, g, 0)
		F.bolt(s, g, 1)
		F.fire(s, g, 2)
		F.bolt(s, g, 3)
		F.fire(s, g, 4)
		F.bolt(s, g, 5) -- 3 fired: room for 3, but 2 spare
		assert(F.reload(s, g, 10))
		assert(s.load and s.load.room == 2, "room limited to the spare")
		F.settle(s, 100)
		assert(s.magazine == 4 and s.spare == 0, `2 in, none left (got {s.magazine}, {s.spare})`)
	end,
	["a live round thrown out by a reload goes back into the spare"] = function()
		local g = gun(5, "Stripper")
		local s = F.new(g, 10)
		F.fire(s, g, 0)
		F.bolt(s, g, 1) -- 4 in the magazine, one chambered
		assert(F.reload(s, g, 5))
		assert(s.spare == 11, "the chambered round back in the pouch")
		F.settle(s, 100)
		-- 1 pushed in (room for 1), then the bolt closes on one: 4 + 1, as before, and that round wasn't lost
		assert(F.rounds(s) == 5 and s.spare == 10, `topped up (got {F.rounds(s)}, {s.spare})`)
	end,
	["a top-break revolver: the live rounds go back into the spare before six go in"] = function()
		local g = gun(6, "BreakOpen")
		local s = F.new(g, 1)
		for i = 1, 4 do
			F.fire(s, g, i)
		end
		assert(F.rounds(s) == 2)
		assert(F.reload(s, g, 10) and F.rounds(s) == 3 and s.spare == 0, "2 kept + the last spare")
	end,
	["the bag fills the spare back to full, and says when it gave nothing"] = function()
		local g = gun(5, "Stripper")
		local s = F.new(g, 40)
		assert(not F.refill(s, 40), "already full")
		s.spare = 3
		assert(F.refill(s, 40) and s.spare == 40)
		assert(not F.refill(F.new(g), 40), "unlimited: nothing to give")
	end,
	["the bag: teammates only, never the Supplier, a wait between takes"] = function()
		assert(R.canTake(1, "uniform1", 2, "uniform1", 0, nil))
		assert(select(2, R.canTake(2, "uniform1", 2, "uniform1", 0, nil)) == "own")
		assert(select(2, R.canTake(1, "uniform2", 2, "uniform1", 0, nil)) == "enemy")
		assert(select(2, R.canTake(1, nil, 2, "uniform1", 0, nil)) == "enemy")
		assert(select(2, R.canTake(1, "uniform1", 2, "uniform1", 10, 70)) == "wait")
		assert(R.canTake(1, "uniform1", 2, "uniform1", 70, 70), "the wait over")
		assert(R.shown("uniform1", 2, 1, "uniform1") and not R.shown("uniform1", 2, 2, "uniform1"))
		assert(not R.shown("uniform1", 2, 1, "uniform2"), "hidden from the enemy")
		assert(SupplyCfg.cooldown == 60 and C.Earn.Resupply == 4, "the user's numbers: 60 s, 4 Marks")
		assert(C.Defs[SupplyCfg.Class], "the bag's class exists")
	end,
}
