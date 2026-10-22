--!strict
-- Staff spell stages from the hold time (Config/Spells). Pure.

local Spells = {}

export type Stage = { name: string, hold: number }

-- The stage reached after holding left click `held` seconds: the last one whose `hold` it passed.
function Spells.stage(stages: { Stage }, held: number): number
	local reached = 1
	for i, s in stages do
		if held >= s.hold then
			reached = i
		end
	end
	return reached
end

-- The stage that actually fires: the reached one if it is built, else the highest built one below it.
function Spells.firing(stages: { Stage }, built: { [string]: boolean }, held: number): number?
	for i = Spells.stage(stages, held), 1, -1 do
		if built[stages[i].name] then
			return i
		end
	end
	return nil
end

-- How far into the charge `held` is: 0 at the press, 1 once the last stage is ready.
function Spells.charge(stages: { Stage }, held: number): number
	local full = stages[#stages].hold
	return if full > 0 then math.clamp(held / full, 0, 1) else 1
end

-- Where the charge animation is after holding `held` seconds: the hold time itself up to the last stage's, then round
-- and round its last `loop` seconds (the shake at its peak once ready).
function Spells.chargeTime(stages: { Stage }, loop: number, held: number): number
	local full = stages[#stages].hold
	if held <= full or loop <= 0 then
		return held
	end
	return full + (held - full) % loop
end

-- The walk speed share while charging (Config/Spells.Staff.Charge): from `from` at the press down to `to` just before
-- the last stage is ready, 0 once it is (no moving).
function Spells.chargeSpeed(stages: { Stage }, c: { from: number, to: number }, held: number): number
	local p = Spells.charge(stages, held)
	if p >= 1 then
		return 0
	end
	return c.from + (c.to - c.from) * p
end

-- The hip-fire cone (degrees) for a walking share 0..1 (Config/Spells.Staff.Hip).
function Spells.spread(hip: { spread: number, walkSpread: number }, walking: number): number
	return hip.spread + hip.walkSpread * math.clamp(walking, 0, 1)
end

-- Mana (Config/Spells.Mana). `locked`: burnt out by a mega shot, nothing fires until it's full again.
export type Mana = { value: number, locked: boolean, spentAt: number }
export type ManaCfg = {
	max: number,
	cost: { number },
	regen: number,
	delay: number,
	burnout: { delay: number, regen: number },
}

function Spells.mana(cfg: ManaCfg): Mana
	return { value = cfg.max, locked = false, spentAt = -math.huge }
end

-- The highest stage the mana pays for (0: none, or burnt out).
function Spells.affordable(m: Mana, cfg: ManaCfg): number
	if m.locked then
		return 0
	end
	local best = 0
	for i, c in cfg.cost do
		if m.value >= c - 1e-6 then
			best = i
		end
	end
	return best
end

-- Spends a stage's shot; false if it can't be paid. The last stage (the mega shot) burns the bar out.
function Spells.spend(m: Mana, cfg: ManaCfg, stage: number, now: number): boolean
	if Spells.affordable(m, cfg) < stage then
		return false
	end
	m.value = math.max(0, m.value - cfg.cost[stage])
	m.spentAt = now
	if stage == #cfg.cost then
		m.locked = true
	end
	return true
end

-- Refills for `dt` seconds (only `delay` after a shot; burnt out: slower, after a longer delay). It refills while
-- charging too: a charge waiting at a stage it can't pay for goes on once the mana is there (user 2026-10-13: it
-- froze). Returns true the moment a burnt-out bar is full again.
function Spells.refill(m: Mana, cfg: ManaCfg, now: number, dt: number): boolean
	local wait = if m.locked then cfg.burnout.delay else cfg.delay
	if now - m.spentAt >= wait then
		m.value = math.min(cfg.max, m.value + (if m.locked then cfg.burnout.regen else cfg.regen) * dt)
	end
	if m.locked and m.value >= cfg.max then
		m.locked = false
		return true
	end
	return false
end

-- The hold time a charge may reach with only `stages` stages paid for: kept short of when the next stage's circle
-- starts to open (`opens`, seconds of hold per stage), so it never appears.
function Spells.capHeld(opens: { number }, stages: number, held: number): number
	local next = opens[stages + 1]
	return if next then math.min(held, math.max(next - 0.01, 0)) else held
end

-- the look of a caster's magic: its kit's team scheme (Config/Spells.Staff.Teams), else `default`
function Spells.scheme(kit: any, teams: { [string]: string }, default: string): string
	return if type(kit) == "string" and teams[kit] then teams[kit] else default
end

return Spells
