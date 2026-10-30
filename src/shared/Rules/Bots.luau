--!strict
-- The AI soldiers' rules as plain numbers (Config/Bots; src/server/Bots drives them):
-- - wanted: how many bots a mode runs for the players on (fill the empty places, never over the server's budget);
-- - the brain, a small state machine stepped several times a second from what the bot senses:
--   Advance (to the objective) -> Engage (an enemy in sight: react, aim, shoot, work the bolt) -> Reload (empty, or low
--   with nothing in sight) -> Retreat (hurt while under fire: fall back a while, still shooting back);
-- - sight (range and view cone; the line-of-sight ray is the server's), target choice, the aim's error and lead.

local Bots = {}

export type State = "Advance" | "Engage" | "Reload" | "Retreat"
export type Move = "Objective" | "Hold" | "Strafe" | "Hunt" | "Away"

-- what the bot knows this step
export type Senses = {
	now: number,
	health: number, -- share of the most
	magazine: number,
	chambered: boolean,
	spent: boolean, -- a fired case in the chamber (a bolt rifle wants its bolt worked)
	busy: boolean, -- the action under way (a shot's fire time, the bolt, a reload)
	loading: boolean, -- single rounds going in (a stripper-clip rifle topping up)
	capacity: number, -- rounds a full rifle holds (magazine and chamber)
	auto: boolean, -- semi-automatic: the action cycles itself
	target: { id: any, distance: number, visible: boolean }?,
	hurtAt: number?, -- when its health last fell
}

export type Brain = {
	state: State,
	targetId: any?,
	seenAt: number, -- when the target came into sight (the reaction counts from here)
	lastSeen: number,
	retreatUntil: number,
	nextShot: number,
	boltAt: number,
	reloading: boolean, -- asked for a reload and waiting for it to play out
}

export type Intent = {
	move: Move,
	aim: boolean, -- standing to the sights (the aim hold, its slower walk)
	fire: boolean,
	bolt: boolean,
	reload: boolean,
	stopLoad: boolean,
}

export type Difficulty = {
	reaction: number,
	aimError: number,
	aimFloor: number,
	settle: number,
	moving: number,
	spotRange: number,
	fov: number,
	lead: number,
	fireGap: { number },
}

-- Bots to run: `override` (a test's pin) when given, else what tops `players` up to the mode's fill; never under 0 nor
-- over `max`. A mode with no fill gets none.
function Bots.wanted(fill: { total: number }?, players: number, max: number, override: number?): number
	if override then
		return math.clamp(math.floor(override), 0, max)
	end
	if not fill then
		return 0
	end
	return math.clamp(fill.total - players, 0, max)
end

function Bots.new(): Brain
	return {
		state = "Advance",
		targetId = nil,
		seenAt = 0,
		lastSeen = -math.huge,
		retreatUntil = 0,
		nextShot = 0,
		boltAt = 0,
		reloading = false,
	}
end

-- Rounds in the rifle (the magazine and a live one chambered).
function Bots.rounds(s: Senses): number
	return s.magazine + (if s.chambered then 1 else 0)
end

-- A bolt rifle with a spent case (or an empty chamber over a fed magazine) wants its bolt worked.
function Bots.needsBolt(s: Senses): boolean
	return not s.auto and not s.chambered and s.magazine > 0
end

local function lerp(range: { number }, t: number): number
	return range[1] + (range[2] - range[1]) * t
end

-- One step of the brain. `cfg` is Config/Bots.Brain plus CloseRange; `roll` a fresh random 0..1 (gaps and delays).
-- Changes `b` and returns what to do this step.
function Bots.step(b: Brain, s: Senses, cfg: any, d: Difficulty, roll: number): Intent
	local now = s.now
	local t = s.target
	-- the target: a new one restarts the reaction; one out of sight is hunted for Forget seconds
	if t and t.visible then
		if b.targetId ~= t.id then
			b.targetId = t.id
			b.seenAt = now
		end
		b.lastSeen = now
	elseif b.targetId ~= nil and now - b.lastSeen > cfg.Forget then
		b.targetId = nil
	end
	local visible = t ~= nil and t.visible and t.id == b.targetId
	local hunting = b.targetId ~= nil
	local reacted = visible and now - b.seenAt >= d.reaction
	local rounds = Bots.rounds(s)

	-- hurt while under fire: fall back for a while (or until healed past RetreatUntil)
	if b.state ~= "Retreat" and s.health < cfg.RetreatBelow and s.hurtAt and now - s.hurtAt < 1 then
		b.state = "Retreat"
		b.retreatUntil = now + cfg.RetreatFor
	elseif b.state == "Retreat" and (now >= b.retreatUntil or s.health >= cfg.RetreatUntil) then
		b.state = "Advance"
	end

	local intent: Intent =
		{ move = "Objective", aim = false, fire = false, bolt = false, reload = false, stopLoad = false }

	-- a reload: when empty, or low with nothing in sight; it holds the state until it has played out
	if b.reloading and not s.busy and not s.loading then
		b.reloading = false
	end
	local low = rounds < s.capacity * cfg.ReloadBelow
	local openEmpty = not s.chambered and s.magazine == 0
	if not b.reloading and not s.busy and (openEmpty or (low and not hunting)) then
		intent.reload = true
		b.reloading = true
	end
	if s.loading and visible and rounds > 0 then
		intent.stopLoad = true -- (single rounds going in: stop them for the fight)
	end

	if b.state ~= "Retreat" then
		b.state = if b.reloading then "Reload" elseif hunting then "Engage" else "Advance"
	end

	if b.state == "Engage" then
		intent.aim = true
		intent.move = if not visible then "Hunt" elseif t and t.distance < cfg.CloseRange then "Strafe" else "Hold"
	elseif b.state == "Retreat" then
		intent.move = "Away"
		intent.aim = visible
	elseif b.state == "Reload" then
		intent.move = if hunting then "Hold" else "Objective"
	end

	-- the bolt after a shot, a moment later
	if not intent.reload and not s.busy and Bots.needsBolt(s) and now >= b.boltAt then
		intent.bolt = true
	end
	-- a shot once it has reacted, the chamber live and the action idle
	if
		reacted
		and intent.aim
		and not b.reloading
		and not s.busy
		and s.chambered
		and now >= b.nextShot
		and not intent.bolt
	then
		intent.fire = true
		b.nextShot = now + (if s.auto then lerp(d.fireGap, roll) else 0)
		b.boltAt = now + lerp(cfg.BoltDelay, roll)
	end
	return intent
end

-- Whether an enemy `dx, dz` (flat, from the bot) at `distance` is within `range` and the view cone `fov` (degrees across)
-- about the facing `fx, fz` (flat, unit). `alert`: hit lately, it looks all round.
function Bots.inSight(
	dx: number,
	dz: number,
	distance: number,
	fx: number,
	fz: number,
	range: number,
	fov: number,
	alert: boolean
): boolean
	if distance > range then
		return false
	end
	if alert then
		return true
	end
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return true
	end
	local cos = (dx * fx + dz * fz) / len
	return cos >= math.cos(math.rad(fov / 2))
end

-- The target from the candidates (each id, distance, visible): the current one while it is still in sight, else the
-- nearest in sight, else nil.
function Bots.pick(candidates: { { id: any, distance: number, visible: boolean } }, current: any?)
	local best = nil
	for _, c in candidates do
		if c.visible then
			if c.id == current then
				return c
			end
			if not best or c.distance < best.distance then
				best = c
			end
		end
	end
	return best
end

-- Degrees of aim error `since` seconds onto a target crossing at `cross` studs/s: the new-target error settling
-- exponentially to the floor, plus the moving target's share (Config `moving` per 10 studs/s).
function Bots.aimError(d: Difficulty, since: number, cross: number): number
	local settled = d.aimFloor + (d.aimError - d.aimFloor) * math.exp(-math.max(0, since) / d.settle)
	return settled + d.moving * math.abs(cross) / 10
end

-- An offset within a cone of `err` degrees, from two random 0..1 numbers: (right, up) degrees, uniform over the disc.
function Bots.scatter(err: number, u1: number, u2: number): (number, number)
	local r = err * math.sqrt(u1)
	local a = 2 * math.pi * u2
	return r * math.cos(a), r * math.sin(a)
end

-- Where to aim at a target at `p` moving at `v` (per axis): a human-like lag of `lag` seconds, of which the share
-- `lead` is made up by leading it (1: dead on, 0: where it was `lag` ago).
function Bots.lead(p: number, v: number, lag: number, lead: number): number
	return p + v * lag * (lead - 1)
end

-- Whether a bot meant to be moving has stalled: under `distance` studs made over `window` seconds.
function Bots.stuck(moved: number, elapsed: number, window: number, distance: number): boolean
	return elapsed >= window and moved < distance
end

return Bots
