--!strict
local Cfg = require("../src/shared/Config/Spells")
local Spells = require("../src/shared/Rules/Spells")

return {
	["stages: a tap is stage 1, longer holds reach later stages"] = function()
		assert(Spells.stage(Cfg.Stages, 0) == 1)
		assert(Spells.stage(Cfg.Stages, 0.1) == 1)
		assert(Spells.stage(Cfg.Stages, Cfg.Stages[2].hold) == 2)
		assert(Spells.stage(Cfg.Stages, Cfg.Stages[3].hold + 5) == 3)
	end,
	["stage holds rise and start at zero"] = function()
		assert(Cfg.Stages[1].hold == 0)
		for i = 2, #Cfg.Stages do
			assert(Cfg.Stages[i].hold > Cfg.Stages[i - 1].hold, `stage {i} holds no longer than {i - 1}`)
		end
		assert(Cfg.Stages[2].hold == 1 and Cfg.Stages[3].hold == 3, "stage 2 at 1 s, stage 3 at 3 s (user 2026-10-20)")
	end,
	["an unbuilt stage fires the highest built one below it"] = function()
		local built = { Quick = true }
		assert(Spells.firing(Cfg.Stages, built, 0) == 1)
		assert(Spells.firing(Cfg.Stages, built, 99) == 1)
		assert(Spells.firing(Cfg.Stages, { Quick = true, Full = true }, 99) == 3)
		assert(Spells.firing(Cfg.Stages, {}, 0) == nil)
	end,
	["charging slows the walk more and more, and stops it once the last stage is ready"] = function()
		local S = Cfg.Staff
		local full = Cfg.Stages[#Cfg.Stages].hold
		local prev = math.huge
		for k = 0, 9 do
			local v = Spells.chargeSpeed(Cfg.Stages, S.Charge, full * k / 10)
			assert(v < prev and v > 0, `charge speed must fall and stay above 0 before ready ({v})`)
			prev = v
		end
		assert(Spells.chargeSpeed(Cfg.Stages, S.Charge, full) == 0, "ready: no moving")
		assert(Spells.charge(Cfg.Stages, full * 2) == 1)
	end,
	["each stage's shot costs more: longer cooldowns, slower walking"] = function()
		local S = Cfg.Staff
		assert(#S.Cooldown == #Cfg.Stages and #S.Slow == #Cfg.Stages)
		for i = 2, #Cfg.Stages do
			assert(S.Cooldown[i] > S.Cooldown[i - 1], `stage {i} cooldown`)
			assert(S.Slow[i] < S.Slow[i - 1], `stage {i} slow`)
		end
		assert(S.TwoHands == Cfg.Stages[2].hold, "two hands on once stage 2 is reached (user 2026-10-20)")
		assert(S.LeftShows > 0 and S.LeftShows < S.TwoHands, "first person: the left arm shows as it comes up")
		assert(S.Veil >= 0 and S.Veil < 1)
		assert(S.OlderVeil >= 0 and S.OlderVeil < 1, "older circles: more see-through, never invisible")
		for i, v in S.StageVeils do
			assert(v > 0 and v < 1, `stage {i} veil`)
			assert(i == 1 or v < S.StageVeils[i - 1], "each stage more solid than the one before")
		end
	end,
	["hip fire spreads wider while walking"] = function()
		local hip = Cfg.Staff.Hip
		assert(Spells.spread(hip, 1) > Spells.spread(hip, 0))
		assert(Spells.spread(hip, 5) == Spells.spread(hip, 1), "capped at full walk")
	end,
	["ragdoll joints and knocks are sane"] = function()
		local R = require("../src/shared/Config/Ragdoll")
		for name, j in R.Joints do
			assert(j.swing > 0 and j.swing <= 180 and j.twist >= 0 and j.twist <= 180, `{name}: bad limits`)
		end
		assert(R.minDown < R.maxDown and R.still > 0)
		for name, k in R.Knocks do
			assert(k.push >= 0 and k.lift >= 0 and k.getUp >= 0, `{name}: bad knock`)
		end
		assert(R.Knocks.StaffRecoil.getUp == 0.5, "the staff's knock: up half a second after landing (user)")
	end,
	["the charge animation follows the hold, then loops its ready shake"] = function()
		local full = Cfg.Stages[#Cfg.Stages].hold
		local loop = Cfg.Staff.ChargeLoop
		assert(Spells.chargeTime(Cfg.Stages, loop, 1) == 1)
		assert(Spells.chargeTime(Cfg.Stages, loop, full) == full)
		for _, extra in { 0.1, 0.59, 0.61, 5 } do
			local t = Spells.chargeTime(Cfg.Stages, loop, full + extra)
			assert(t >= full and t < full + loop, `held {full + extra}: {t} outside the ready loop`)
		end
		local F = Cfg.Staff.Float
		assert(F.rise > 0 and F.descend > 0 and F.descend < F.rise, "floating: rises slowly, sinks slower still")
		assert(F.hover == 5, "sinks after 5 s of floating (user)")
	end,
	["mana: 6 quick shots, 3 charged, 1 mega that burns the bar out"] = function()
		local C = Cfg.Mana
		local m = Spells.mana(C)
		for _ = 1, 6 do
			assert(Spells.spend(m, C, 1, 0), "quick shot")
		end
		assert(not Spells.spend(m, C, 1, 0), "a 7th quick shot")
		m = Spells.mana(C)
		for _ = 1, 3 do
			assert(Spells.spend(m, C, 2, 0), "charged shot")
		end
		assert(Spells.affordable(m, C) == 0)
		m = Spells.mana(C)
		assert(Spells.affordable(m, C) == 3 and Spells.spend(m, C, 3, 0) and m.locked, "mega: burnt out")
		-- burnt out: nothing until it's full again, and it only starts after the longer delay
		assert(not Spells.refill(m, C, C.burnout.delay - 0.1, 1) and m.value == 0, "still smouldering")
		local now, unlocked = C.burnout.delay, false
		while not unlocked and now < 60 do
			assert(Spells.affordable(m, C) == 0, "nothing fires while burnt out")
			unlocked = Spells.refill(m, C, now, 0.1)
			now += 0.1
		end
		assert(unlocked and m.value == C.max, "full again, unlocked")
		assert(now > C.delay + C.max / C.regen, "the mega's cooldown is longer than a normal refill")
		-- a partial bar refills after the delay (charging or not: a waiting charge goes on once it can pay)
		m = Spells.mana(C)
		Spells.spend(m, C, 1, 0)
		Spells.refill(m, C, C.delay / 2, 1)
		assert(m.value == C.max - 1, "not during the delay")
		Spells.refill(m, C, 5, 1)
		assert(m.value == C.max, "refilled")
	end,
	["a charge stops short of the stage it can't pay for"] = function()
		local opens = { 0, 0.45, 0.6 }
		assert(Spells.capHeld(opens, 1, 2) < 0.45)
		assert(Spells.capHeld(opens, 2, 2) < 0.6)
		assert(Spells.capHeld(opens, 3, 2) == 2)
		assert(Spells.capHeld(opens, 1, 0.2) == 0.2)
	end,
	["each team's magic has its own scheme"] = function()
		local Vfx = require("../src/shared/Config/Vfx")
		local Palette = require("../src/shared/Config/Palette")
		local S = Cfg.Staff
		local U = require("../src/shared/Config/Uniforms")
		local used = {}
		for _, kit in U.Teams do
			local name = Spells.scheme(kit, S.Teams, S.Scheme)
			assert(not used[name], "two teams share " .. name)
			used[name] = true
			local scheme = (Vfx.Schemes :: any)[name]
			assert(scheme, "no scheme " .. name)
			for role, color in scheme do
				for _, c in (if type(color) == "table" then color else { color }) :: { string } do
					assert((Palette.Magic :: any)[c], name .. "." .. role .. ": no color " .. c)
				end
			end
		end
		assert(Spells.scheme(nil, S.Teams, S.Scheme) == S.Scheme, "no kit: the default")
		assert(Spells.scheme("dummy", S.Teams, S.Scheme) == S.Scheme, "unknown kit: the default")
	end,
}
