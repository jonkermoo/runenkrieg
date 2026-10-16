--!strict
-- The staff cast shown to other players (Net "StaffCast", Config/Spells.Send): what a client's message is allowed to
-- say, how often, and how far the charge runs on between updates on other clients. Pure: numbers and tables only.

local StaffNet = {}

export type Bucket = { tokens: number, at: number }

local MODES = { Hip = true, Pulse = true, Release = true }

-- a real number (not NaN, not infinite)
function StaffNet.finite(v: unknown): boolean
	return type(v) == "number" and v == v and math.abs(v) < math.huge
end

-- a stage number 1..last, or nil
function StaffNet.stage(v: unknown, last: number): number?
	if not StaffNet.finite(v) then
		return nil
	end
	local n = v :: number
	if n ~= math.floor(n) or n < 1 or n > last then
		return nil
	end
	return n
end

-- how a shot was fired: "Hip" (opened and fired at once), "Pulse" (stage 1 from a held circle, which stays open) or
-- "Release" (the held cast fires and closes); nil for anything else
function StaffNet.mode(v: unknown): string?
	if type(v) == "string" and MODES[v] then
		return v
	end
	return nil
end

-- a charge time: nil (not charging) stays nil, a number is clamped to 0..max; false for a bad value (drop the message)
function StaffNet.held(v: unknown, max: number): number? | false
	if v == nil then
		return nil
	end
	if not StaffNet.finite(v) then
		return false
	end
	return math.clamp(v :: number, 0, max)
end

-- the stages paid for: a whole number 0..last (clamped), or nil for a bad value
function StaffNet.cap(v: unknown, last: number): number?
	if not StaffNet.finite(v) then
		return nil
	end
	return math.clamp(math.floor(v :: number), 0, last)
end

-- a token bucket: `rate` tokens a second up to `rate`; true (and one spent) when one is left
function StaffNet.take(b: Bucket, now: number, rate: number): boolean
	b.tokens = math.min(rate, b.tokens + math.max(0, now - b.at) * rate)
	b.at = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

-- whether an update may go (client) or be taken (server, with slack < 1): at most `rate` a second
function StaffNet.due(lastAt: number, now: number, rate: number, slack: number): boolean
	return now - lastAt >= slack / rate
end

-- a shot after one of stage `lastStage` at `lastAt`: not before that stage's cooldown, less `slack`
function StaffNet.cooled(lastAt: number?, lastStage: number?, now: number, cooldown: { number }, slack: number): boolean
	if not lastAt or not lastStage then
		return true
	end
	return now - lastAt >= (cooldown[lastStage] or 0) - slack
end

-- other clients: the charge time to show `since` seconds after an "Aim" said `held`: it runs on for at most `ahead`,
-- and never into a stage the caster can't pay for (`opens`: when each stage's circle starts to open, `cap` stages paid
-- for; Rules/Spells.capHeld)
function StaffNet.heldNow(held: number, since: number, ahead: number, opens: { number }, cap: number): number
	local h = held + math.clamp(since, 0, ahead)
	local next = opens[cap + 1]
	return if next then math.min(h, math.max(next - 0.01, held, 0)) else h
end

return StaffNet
