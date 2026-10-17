--!strict
local Cfg = require("../src/shared/Config/Spells")
local N = require("../src/shared/Rules/StaffNet")

local Send = Cfg.Send
local LAST = #Cfg.Stages

return {
	["finite takes real numbers only"] = function()
		assert(N.finite(0) and N.finite(-3.5))
		assert(not N.finite(0 / 0))
		assert(not N.finite(math.huge) and not N.finite(-math.huge))
		assert(not N.finite("1") and not N.finite(nil))
	end,
	["a stage is a whole number from 1 to the last"] = function()
		assert(N.stage(1, LAST) == 1 and N.stage(LAST, LAST) == LAST)
		assert(N.stage(0, LAST) == nil and N.stage(LAST + 1, LAST) == nil)
		assert(N.stage(1.5, LAST) == nil and N.stage(0 / 0, LAST) == nil and N.stage("2", LAST) == nil)
	end,
	["only the three ways of firing are taken"] = function()
		assert(N.mode("Hip") == "Hip" and N.mode("Pulse") == "Pulse" and N.mode("Release") == "Release")
		assert(N.mode("hip") == nil and N.mode(1) == nil and N.mode(nil) == nil)
	end,
	["a charge time is nil, clamped, or refused"] = function()
		assert(N.held(nil, Send.MaxHeld) == nil)
		assert(N.held(-1, Send.MaxHeld) == 0)
		assert(N.held(1.2, Send.MaxHeld) == 1.2)
		assert(N.held(1e9, Send.MaxHeld) == Send.MaxHeld)
		assert(N.held(0 / 0, Send.MaxHeld) == false and N.held("1", Send.MaxHeld) == false)
	end,
	["the stages paid for are clamped to 0..last"] = function()
		assert(N.cap(2, LAST) == 2 and N.cap(-4, LAST) == 0 and N.cap(99, LAST) == LAST and N.cap(1.9, LAST) == 1)
		assert(N.cap(0 / 0, LAST) == nil and N.cap(nil, LAST) == nil)
	end,
	["the token bucket allows a burst, then the rate"] = function()
		local b = { tokens = Send.Events, at = 0 }
		local n = 0
		for _ = 1, 100 do
			if N.take(b, 0, Send.Events) then
				n += 1
			end
		end
		assert(n == Send.Events, `burst {n}`)
		assert(not N.take(b, 0.01, Send.Events))
		assert(N.take(b, 1 / Send.Events + 0.01, Send.Events))
		-- a long wait never fills past the burst
		N.take(b, 1000, Send.Events)
		assert(b.tokens <= Send.Events)
	end,
	["updates go at most at the rate, the server with slack"] = function()
		assert(not N.due(0, 0.05, Send.AimRate, 1))
		assert(N.due(0, 0.1, Send.AimRate, 1))
		assert(N.due(0, 0.05, Send.AimRate, Send.AimSlack))
		assert(not N.due(0, 0.01, Send.AimRate, Send.AimSlack))
	end,
	["a shot waits for the last one's cooldown, less the slack"] = function()
		local cd = Cfg.Staff.Cooldown
		local s = Send.CooldownSlack
		assert(N.cooled(nil, nil, 0, cd, s))
		assert(not N.cooled(0, 3, cd[3] - s - 0.05, cd, s))
		assert(N.cooled(0, 3, cd[3] - s, cd, s))
		assert(N.cooled(0, 1, cd[1], cd, s))
	end,
	["a charged shot must have been charged that long since its circle opened"] = function()
		local st, slack = Cfg.Stages, Send.ChargeSlack
		assert(N.charged(1, "Hip", nil, 0, st, slack), "a tap needs no charge")
		assert(not N.charged(3, "Hip", nil, 10, st, slack), "a tap can't be stage 3")
		assert(not N.charged(2, "Pulse", 0, 10, st, slack), "a pulse is stage 1 only")
		assert(not N.charged(3, "Release", nil, 10, st, slack), "no circle opened: no charged shot")
		assert(not N.charged(3, "Release", 0, st[3].hold - slack - 0.1, st, slack), "released too soon")
		assert(N.charged(3, "Release", 0, st[3].hold, st, slack), "charged in full")
		assert(N.charged(2, "Release", 5, 5 + st[2].hold, st, slack))
		assert(not N.charged(4, "Release", 0, 100, st, slack), "no stage 4")
	end,
	["the charge runs on between updates, but only so far"] = function()
		local opens = { 0, 0.45, 2 }
		assert(N.heldNow(1, 0.1, Send.Ahead, opens, 3) == 1.1)
		assert(N.heldNow(1, 5, Send.Ahead, opens, 3) == 1 + Send.Ahead)
		assert(N.heldNow(1, -1, Send.Ahead, opens, 3) == 1) -- a clock step back doesn't rewind it
	end,
	["the charge never runs into a stage the caster can't pay for"] = function()
		local opens = { 0, 0.45, 2 }
		assert(N.heldNow(1.9, 0.2, Send.Ahead, opens, 2) < 2)
		assert(N.heldNow(0.3, 0.2, Send.Ahead, opens, 1) < 0.45)
		assert(N.heldNow(1.9, 0.2, Send.Ahead, opens, 3) > 2)
	end,
	["the send numbers make sense"] = function()
		assert(Send.AimRate > 0 and Send.Events > 0)
		assert(Send.AimSlack > 0 and Send.AimSlack <= 1)
		assert(Send.Ahead >= 1 / Send.AimRate, "the charge must run on at least until the next update")
		assert(Send.Reach > 0 and Send.Range > 0 and Send.MaxHeld >= Cfg.Stages[LAST].hold)
	end,
}
