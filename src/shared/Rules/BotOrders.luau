--!strict
-- A side's bot orders in Normal as plain numbers (Config/Bots.Normal; src/server/Bots gives them). Each side's commander
-- looks at the sectors (who holds each, its control, the soldiers in each zone) and sends its bots to two places at
-- most: the sector the side attacks (Rules/Frontline.target) and, while one of its own sectors is being taken, that
-- sector to defend. A bot keeps its order while the share allows, so orders don't flicker between ticks.

local BotOrders = {}

export type Order = "Attack" | "Defend"
export type Plan = { attack: number?, defend: number?, share: number, keep: number? }

local function enemy(side: string): string
	return if side == "West" then "East" else "West"
end

-- Whether the enemy is taking `side`'s sector `i`: enemies in its zone, and either more of them than defenders or its
-- control off `side`'s end (control runs from 1, West's, to -1, East's).
local function underAttack(side: string, control: number, counts: { West: number, East: number }): boolean
	local foes = (counts :: any)[enemy(side)]
	local own = (counts :: any)[side]
	if foes <= 0 then
		return false
	end
	local rest = if side == "West" then 1 else -1
	return foes > own or math.abs(control - rest) > 1e-3
end

-- Where `side`'s bots go: `target` (the sector it attacks, nil when none) and, while an own sector is under attack,
-- that one with `share` (Config/Bots.Normal.defendShare) of the bots: the one with most enemies in it, the frontmost
-- on a tie (nearest the enemy's end). With none under attack and a `front` (the side's sector nearest the enemy),
-- `hold` of the bots hold it (and dig in there: Rules/BotTrenches; user 2026-11-02: "dig in at once").
function BotOrders.plan(
	side: string,
	owner: { string },
	control: { number },
	counts: { { West: number, East: number } },
	target: number?,
	share: number,
	front: number?,
	hold: number?
): Plan
	local defend: number? = nil
	local most = 0
	local n = #owner
	for k = 1, n do
		-- from the side's front backwards: the frontmost wins a tie
		local i = if side == "West" then n + 1 - k else k
		if owner[i] == side and counts[i] and underAttack(side, control[i], counts[i]) then
			local foes = (counts[i] :: any)[enemy(side)]
			if foes > most then
				most = foes
				defend = i
			end
		end
	end
	if not target and defend then
		return { attack = nil, defend = defend, share = 1 }
	end
	if not defend and target and front and hold and hold > 0 then
		return { attack = target, defend = front, share = hold }
	end
	return { attack = target, defend = defend, share = if defend then share else 0 }
end

-- How many of `bots` defend at `share`: rounded, at least one when there is a share and two bots or more, never all
-- while there is a sector to attack.
function BotOrders.defenders(bots: number, share: number, attacking: boolean): number
	if share <= 0 or bots <= 0 then
		return 0
	end
	if not attacking then
		return bots
	end
	local d = math.floor(bots * share + 0.5)
	if bots >= 2 then
		d = math.clamp(d, 1, bots - 1)
	else
		d = 0
	end
	return d
end

-- The orders for `ids` (in a steady order) given each one's `current` order: `defenders` of them Defend, the rest
-- Attack, moving as few as it can (the defenders kept first, then the next in line).
function BotOrders.assign(ids: { any }, current: { [any]: Order }, defenders: number): { [any]: Order }
	local out: { [any]: Order } = {}
	local left = defenders
	for _, id in ids do
		if current[id] == "Defend" and left > 0 then
			out[id] = "Defend"
			left -= 1
		end
	end
	for _, id in ids do
		if out[id] == nil then
			if left > 0 then
				out[id] = "Defend"
				left -= 1
			else
				out[id] = "Attack"
			end
		end
	end
	return out
end

-- Offensives and the initiative (Config/Bots.Offensive) ------------------------------------------------------------

export type Phase = "Gather" | "Barrage" | "Go" | "Exploit"
export type Offensive = {
	sector: number, -- the sector it attacks
	phase: Phase,
	since: number, -- when this phase began
	began: number,
	counter: boolean, -- a counter-attack into a sector the side just lost (a short gather)
	goAt: number?, -- when it went
	went: number, -- lives that went in since Go (each living attacker once a life)
	lost: number, -- of those, the ones lost
}
export type OffFacts = {
	now: number,
	ready: number, -- share of its attack squads' living members at their jump-off (0..1)
	ours: number, -- its heads in the target's zone
	theirs: number, -- the enemy's there
	waveEvery: number, -- seconds between respawn waves (Config/Frontline.Waves.every)
}

-- The side that took a sector between two looks at the owners (a sector turning "West" or "East" from anything
-- else), nil when none did; `was` nil (the first look): none.
function BotOrders.capturedBy(was: { string }?, now: { string }): string?
	if not was then
		return nil
	end
	for i, o in now do
		if was[i] ~= o and (o == "West" or o == "East") then
			return o
		end
	end
	return nil
end

-- Who holds the initiative after a look: a side whose offensive captured hands it to the loser (the counter-attack);
-- a side that captured without it (the race at the start, or the defender) takes it; a spent offensive hands it over.
function BotOrders.initiative(holder: string?, capturedBy: string?, spent: boolean): string?
	if capturedBy then
		return if holder == capturedBy then enemy(capturedBy) else capturedBy
	end
	if spent and holder then
		return enemy(holder)
	end
	return holder
end

-- A new offensive on sector `sector` at `now`; `counter` when the side lost that sector under Offensive.counterWithin s
-- ago.
function BotOrders.newOffensive(sector: number, now: number, counter: boolean): Offensive
	return {
		sector = sector,
		phase = "Gather",
		since = now,
		began = now,
		counter = counter,
		goAt = nil,
		went = 0,
		lost = 0,
	}
end

local function enter(o: Offensive, phase: Phase, now: number)
	o.phase, o.since = phase, now
	if phase == "Go" and not o.goAt then
		o.goAt = now
	end
end

-- One step of an offensive (Config/Bots.Offensive `cfg`): its phase moved on. Returns true once it is spent.
function BotOrders.offensive(o: Offensive, f: OffFacts, cfg: any): boolean
	local t = f.now - o.since
	if o.phase == "Gather" then
		local most = if o.counter then cfg.counterGather else cfg.gatherSeconds
		-- (a counter-attack waits its whole gather: the side that just took the sector digs in meanwhile)
		local least = if o.counter then most else math.min(cfg.gatherWaves * f.waveEvery, most)
		if t >= most or (t >= least and f.ready >= cfg.ready) then
			enter(o, "Barrage", f.now)
		end
		return false
	elseif o.phase == "Barrage" then
		if t >= cfg.barrageSeconds then
			enter(o, "Go", f.now)
		end
		return false
	end
	if o.phase == "Go" and f.ours >= cfg.exploitAt and f.ours > f.theirs then
		enter(o, "Exploit", f.now)
	elseif o.phase == "Exploit" and f.ours <= 0 then
		enter(o, "Go", f.now)
	end
	local since = f.now - (o.goAt or f.now)
	local limit = cfg.maxSeconds + (if o.phase == "Exploit" then cfg.exploitMore else 0)
	return since >= limit or (o.went > 0 and o.lost >= cfg.spentShare * o.went)
end

-- Whether a side's offensive holds its squads back (gathering or under its barrage): no push into the zone yet.
function BotOrders.waiting(o: Offensive?): boolean
	return o ~= nil and (o.phase == "Gather" or o.phase == "Barrage")
end

-- Whether a side's offensive has gone (all its squads in together).
function BotOrders.going(o: Offensive?): boolean
	return o ~= nil and (o.phase == "Go" or o.phase == "Exploit")
end

-- `side`'s plan (BotOrders.plan's) for the side without the initiative (Config/Bots.Offensive `cfg`): everyone
-- defends the sector under attack, else its front, but `cfg.screen` squads of `size` who keep attacking (`keep`).
-- (The side with it plans with the smaller `cfg.hold` for its front; in the race at the start both plan as before.)
function BotOrders.holdBack(p: Plan, front: number?, cfg: any, size: number): Plan
	local at = p.defend or front
	if not at then
		return p
	end
	return { attack = p.attack, defend = at, share = 1, keep = if p.attack then cfg.screen * size else 0 }
end

-- How many of `bots` defend under plan `p`: all but its `keep` attackers when set, else BotOrders.defenders.
function BotOrders.defendersFor(p: Plan, bots: number): number
	local keep = p.keep
	if keep ~= nil then
		return math.max(0, bots - keep)
	end
	return BotOrders.defenders(bots, p.share, p.attack ~= nil)
end

-- Whether a squad's `holdN`th holder (1-based) of a sector its side took `since` seconds ago holds a spot inside the
-- zone rather than a fire step (Config/Bots.Offensive.dig: for `dig.hold` s, every `dig.every`th holder, the first
-- among them): the flag itself held against the counter-attack, not only the trenches round it.
function BotOrders.digIn(holdN: number, since: number, dig: { hold: number, every: number }): boolean
	return since < dig.hold and (holdN - 1) % dig.every == 0
end

-- The squads (in a steady order, `n` of them) that hold the zone while exploiting: the first `share` of them (at
-- least one). Whether squad `index` is one.
function BotOrders.holdsZone(index: number, n: number, share: number): boolean
	return index <= math.max(1, math.ceil(n * share - 1e-9))
end

return BotOrders
