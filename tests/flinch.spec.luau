--!strict
local D = require("../src/shared/Config/Damage")
local G = require("../src/shared/Config/Grenades")
local F = require("../src/shared/Config/Flinch")
local Blast = require("../src/shared/Rules/Blast")
local Flinch = require("../src/shared/Rules/Flinch")

local B = D.Blast

local function band(kg: number, wound: number?): (number, number)
	return Flinch.band(Blast.reachOf(B.Soldier.from, kg, B), wound, Blast.reachOf(F.kpa, kg, B), F)
end

local function w(d: number, knock: number, outer: number): number?
	return Flinch.weight(d, knock, outer, false, false, false, F)
end

return {
	["the band starts where a blast stops hurting and knocking soldiers"] = function()
		local kg = D.Staff.Charge[3]
		local knock, outer = band(kg)
		-- just inside the knock edge the blast still hurts (and so flings); just past it, nothing
		assert(Blast.soldierDamage(Blast.kpa(knock - 0.1, kg, B), B.Soldier) > 0, "hurts inside the edge")
		assert(Blast.soldierDamage(Blast.kpa(knock + 0.1, kg, B), B.Soldier) == 0, "no hurt past the edge")
		assert(outer > knock * 2 and outer < knock * 3, `stage 3: {knock} -> {outer}`)
	end,
	["a grenade's band starts past its splinters"] = function()
		local t = G.Types.grenade_mills
		local knock, outer = band(t.kg, t.fragments.wound)
		assert(knock == t.fragments.wound, "the splinters' reach is the knock edge")
		assert(math.abs(outer - knock * F.beyond) < 1e-6, "a small charge: beyond x the edge")
	end,
	["bigger blasts reach further"] = function()
		local _, small = band(0.5)
		local _, mid = band(10)
		local _, big = band(400)
		assert(small < mid and mid < big)
	end,
	["full at the knock edge, fading to least, none past the band"] = function()
		assert(w(10, 15, 38) == 1, "inside the edge (behind cover): full")
		assert(w(15, 15, 38) == 1)
		local half = w(26.5, 15, 38) :: number
		assert(math.abs(half - (1 + F.least) / 2) < 1e-6, `halfway {half}`)
		assert(math.abs((w(38, 15, 38) :: number) - F.least) < 1e-6)
		assert(w(38.1, 15, 38) == nil)
		assert(w(5, 0, 0) == nil, "no band, no flinch")
		assert(w(0, 0, 0) == 1)
	end,
	["never knocked, armed or down soldiers"] = function()
		assert(Flinch.weight(20, 15, 38, true, false, false, F) == nil, "knocked")
		assert(Flinch.weight(20, 15, 38, false, true, false, F) == nil, "something in the hands")
		assert(Flinch.weight(20, 15, 38, false, false, true, F) == nil, "ragdolled or dead")
	end,
}
