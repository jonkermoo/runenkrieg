--!strict
-- The bot soldiers' rules as plain numbers (Config/Bots; src/server/Bots drives them). In FFA a bot plays like a player
-- (user 2026-10-30: "enemies are treated as players ... always be moving and try to find cover if spotted or shot at
-- ... some what realistic to how a real player would behave"):
-- - wanted: how many bots a mode runs for the players on (fill the empty places, never over the server's budget);
-- - the brain, a small state machine stepped several times a second from what the bot senses:
--   Advance (to the objective, sprinting) -> Engage (an enemy in sight: react, aim, shoot, work the bolt, never
--   standing still: it sidesteps, and a short-range gun closes in) -> Cover (shot at, hit or spotted: run to cover the
--   threat can't see, wait there, reload) -> Peek (step back out where it saw the enemy, shoot, and back into cover when
--   the peek is up or it is hit) -> Reload (empty, or low with nothing in sight) -> Retreat (badly hurt under fire: fall
--   back to cover, or away, shooting back);
-- - sight (range and view cone; the line-of-sight ray is the server's), being looked at, near misses, target choice,
--   the aim's error and lead;
-- - the class each life (its match points, Config/Classes), and which cover point to run to.
-- In Normal its squad (Rules/BotSquads) gives it a role (user 2026-11-01: "it seems too focused on killing and dodging
-- and forgets their goal"): pressing on (Move, Assault) it keeps going for its goal and shoots on the move, fighting
-- where it stands only an enemy within PressWithin and taking cover only when hit; Support holds its spot and fires at
-- where enemies were last seen (covering fire, at SuppressGap); Hold stays on its spot in the zone.
-- Suppression (Rules/Suppression, as a player's; user 2026-11-01: bots rattled by fire too): its level widens its aim
-- (shakenAim) and from SuppressedCover up it counts as under fire: it takes cover even while pressing on, and won't peek.

local Bots = {}

export type State = "Advance" | "Engage" | "Cover" | "Peek" | "Reload" | "Retreat"
export type Move = "Objective" | "Strafe" | "Push" | "Hunt" | "Cover" | "Peek" | "Away" | "Hold"
export type CoverState = "none" | "going" | "at"

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
	threatAt: number?, -- when it was last shot at (a near miss or a hit)
	spotted: boolean?, -- an enemy in sight is looking its way
	cover: CoverState?, -- the driver's cover point from the threat: none found, on the way, there
	push: number?, -- a short-range gun (the shotgun): closes in to this distance
	-- Normal (Rules/BotSquads): its role in its squad; whether there is a known enemy spot to fire at (Support)
	role: string?,
	suppress: boolean?,
	suppressed: number?, -- its suppression level, 0..1 (Rules/Suppression)
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
	coverUntil: number, -- in cover until then (then a peek)
	peekUntil: number,
	peekFrom: number, -- when the peek began (a hit after it ends the peek)
	coverReady: number, -- no new dash to cover before then
}

export type Intent = {
	move: Move,
	aim: boolean, -- to the sights (the aim hold, its slower walk)
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

-- Bots each side runs in Normal: each side topped up to `perSide` with its own players first; a test's pin (`override`,
-- a total) split evenly, West taking the odd one. Over `max` the side with more soldiers (players and bots; on a tie the
-- one with more bots, then West) gives up a bot at a time, so the sides stay as even as the bots can make them.
function Bots.wantedSides(perSide: number, west: number, east: number, max: number, override: number?): (number, number)
	local w, e
	if override then
		local total = math.max(0, math.floor(override))
		w, e = math.ceil(total / 2), math.floor(total / 2)
	else
		w, e = math.max(0, perSide - west), math.max(0, perSide - east)
	end
	max = math.max(0, math.floor(max))
	if override then
		west, east = 0, 0
	end
	while w + e > max do
		local sw, se = west + w, east + e
		if e == 0 or (w > 0 and (sw > se or (sw == se and w >= e))) then
			w -= 1
		else
			e -= 1
		end
	end
	return w, e
end

export type Governor = { cap: number, bad: number, good: number }

-- A fresh governor letting `max` bots run.
function Bots.governor(max: number): Governor
	return { cap = max, bad = 0, good = 0 }
end

-- The governor over `dt` seconds of a frame cost of `ms` (the bots' one-second average) and a physics rate of `fps`,
-- with `count` bots on now and the mode's `max` (Config/Bots.Budget.governor): over budget for `trimAfter` seconds,
-- the cap goes one under the bots on (then one more every `trimEvery`); within it for `restoreAfter`, one back (then
-- every `restoreEvery`), never over `max` nor under `floor`.
function Bots.govern(g: Governor, ms: number, fps: number, dt: number, count: number, max: number, cfg: any)
	if ms > cfg.ms or fps < cfg.minFps then
		g.bad += dt
		g.good = 0
		if g.bad >= cfg.trimAfter then
			g.cap = math.max(cfg.floor, math.min(g.cap, count) - 1)
			g.bad = cfg.trimAfter - cfg.trimEvery
		end
	else
		g.good += dt
		g.bad = 0
		if g.good >= cfg.restoreAfter and g.cap < max then
			g.cap += 1
			g.good = cfg.restoreAfter - cfg.restoreEvery
		end
	end
	g.cap = math.min(g.cap, max)
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
		coverUntil = 0,
		peekUntil = 0,
		peekFrom = 0,
		coverReady = 0,
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

-- the fight's state (not retreating): cover when shot at or spotted, peeks out of it, else engage in the open
local function fight(b: Brain, s: Senses, cfg: any, roll: number, hunting: boolean, visible: boolean)
	local now = s.now
	local threatened = s.threatAt ~= nil and now - s.threatAt < cfg.ThreatMemory
	local cover = s.cover or "none"
	local hasCover = cover ~= "none"
	local openEmpty = not s.chambered and s.magazine == 0
	local was = b.state
	-- pressing on (its squad moving or assaulting): cover only once it has been hit lately
	local pressing = s.role == "Move" or s.role == "Assault"
	local hurt = s.hurtAt ~= nil and now - s.hurtAt < cfg.ThreatMemory
	-- pinned down: as good as hit
	local shaken = (s.suppressed or 0) >= cfg.SuppressedCover
	if pressing and not hurt and not shaken and was ~= "Cover" and was ~= "Peek" then
		threatened = false
	end
	threatened = threatened or shaken
	if not hunting and not threatened then
		if was == "Cover" and hasCover and now < b.coverUntil then
			return -- (sits out its time in cover, reloading)
		end
		b.state = if b.reloading then "Reload" else "Advance"
	elseif was == "Cover" then
		if not hasCover then
			b.state = "Engage"
		elseif
			cover == "at"
			and now >= b.coverUntil
			and not b.reloading
			and hunting
			and not shaken
			and not (s.threatAt ~= nil and now - s.threatAt < cfg.PeekQuiet)
		then
			b.state = "Peek"
			b.peekFrom = now
			b.peekUntil = now + lerp(cfg.PeekFor, roll)
		end
	elseif was == "Peek" then
		local hit = s.hurtAt ~= nil and s.hurtAt > b.peekFrom
		if now >= b.peekUntil or hit or openEmpty or not hunting then
			b.state = if hasCover then "Cover" else "Engage"
			b.coverUntil = now + lerp(cfg.CoverFor, roll)
		end
	elseif
		(threatened or (s.spotted == true and not pressing))
		and hasCover
		and now >= b.coverReady
		and not (s.push ~= nil and visible)
	then
		b.state = "Cover"
		b.coverUntil = now + lerp(cfg.CoverFor, roll)
		b.coverReady = now + cfg.CoverEvery
	elseif b.reloading then
		b.state = if hasCover then "Cover" else "Engage" -- (reloading on the move, no shots)
	else
		b.state = "Engage"
	end
end

-- One step of the brain. `cfg` is Config/Bots.Brain; `roll` a fresh random 0..1 (gaps and delays). Changes `b` and
-- returns what to do this step.
function Bots.step(b: Brain, s: Senses, cfg: any, d: Difficulty, roll: number): Intent
	local now = s.now
	local t = s.target
	-- the target: a new one, or one back in sight after a while, restarts the reaction; one out of sight is hunted for
	-- Forget seconds
	if t and t.visible then
		if b.targetId ~= t.id or now - b.lastSeen > cfg.Reacquire then
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
	local hasCover = (s.cover or "none") ~= "none"

	-- badly hurt while under fire: fall back for a while (or until healed past RetreatUntil)
	if b.state ~= "Retreat" and s.health < cfg.RetreatBelow and s.hurtAt and now - s.hurtAt < 1 then
		b.state = "Retreat"
		b.retreatUntil = now + cfg.RetreatFor
	elseif b.state == "Retreat" and (now >= b.retreatUntil or s.health >= cfg.RetreatUntil) then
		b.state = "Advance"
	end

	local intent: Intent =
		{ move = "Objective", aim = false, fire = false, bolt = false, reload = false, stopLoad = false }

	-- a reload: when empty, or low with nothing in sight (or safe in cover); it holds the state until it has played out
	if b.reloading and not s.busy and not s.loading then
		b.reloading = false
	end
	local low = rounds < s.capacity * cfg.ReloadBelow
	local openEmpty = not s.chambered and s.magazine == 0
	local safe = not hunting or (b.state == "Cover" and s.cover == "at")
	if not b.reloading and not s.busy and (openEmpty or (low and safe)) then
		intent.reload = true
		b.reloading = true
	end
	if s.loading and visible and rounds > 0 and b.state ~= "Cover" then
		intent.stopLoad = true -- (single rounds going in: stop them for the fight)
	end

	if b.state ~= "Retreat" then
		fight(b, s, cfg, roll, hunting, visible)
	end

	local st = b.state
	local role = s.role
	local pressing = role == "Move" or role == "Assault"
	local holding = role == "Support" or role == "Hold"
	-- covering fire: a Support with an enemy spot known and nothing in sight fires at the spot
	local suppressing = role == "Support" and s.suppress == true and not visible and (st == "Advance" or st == "Engage")
	if st == "Engage" then
		intent.aim = true
		if not visible then
			intent.move = if pressing then "Objective" elseif holding then "Hold" elseif hunting then "Hunt" else "Strafe"
		elseif pressing and t and t.distance > cfg.PressWithin then
			intent.move = "Objective" -- (on toward its goal, shooting on the move)
		elseif s.push and t and t.distance > s.push then
			intent.move = "Push"
		elseif holding then
			intent.move = "Hold"
		else
			intent.move = "Strafe" -- (never a standing target)
		end
	elseif st == "Advance" or st == "Reload" then
		intent.move = if holding then "Hold" else "Objective"
		intent.aim = suppressing
	elseif st == "Cover" then
		intent.move = "Cover"
	elseif st == "Peek" then
		intent.move = "Peek"
		intent.aim = true
	elseif st == "Retreat" then
		intent.move = if hasCover then "Cover" else "Away"
		intent.aim = visible
	end

	-- the bolt after a shot, a moment later
	if not intent.reload and not s.busy and Bots.needsBolt(s) and now >= b.boltAt then
		intent.bolt = true
	end
	-- a shot once it has reacted, the chamber live and the action idle
	if
		(reacted or suppressing)
		and intent.aim
		and not b.reloading
		and not s.busy
		and s.chambered
		and now >= b.nextShot
		and not intent.bolt
	then
		intent.fire = true
		local gap = if suppressing then lerp(cfg.SuppressGap, roll) elseif s.auto then lerp(d.fireGap, roll) else 0
		b.nextShot = now + gap
		b.boltAt = now + lerp(cfg.BoltDelay, roll)
	end
	return intent
end

-- The class a bot takes this life with `points` (Config/Classes): with chance `buy` (roll1) the dearest it can pay for
-- among `options` (each key and cost; the first is the free default), else one of those it can pay for at random
-- (roll2), so some lives it saves up. Returns the key and its cost.
function Bots.chooseClass(
	points: number,
	options: { { key: string, cost: number } },
	buy: number,
	roll1: number,
	roll2: number
): (string, number)
	local can = {}
	for _, o in options do
		if o.cost <= points then
			table.insert(can, o)
		end
	end
	if #can == 0 then
		return options[1].key, 0
	end
	local pick = can[1]
	if roll1 < buy then
		for _, o in can do
			if o.cost > pick.cost then
				pick = o
			end
		end
	else
		pick = can[math.clamp(math.floor(roll2 * #can) + 1, 1, #can)]
	end
	return pick.key, pick.cost
end

-- The cover to run to from the candidate points (each its distance from the bot, whether the threat can't see it, how
-- far it is from the threat, and whether a teammate already stands close to it): the nearest hidden one within
-- `maxDistance` that isn't nearer the threat than `minThreat` nor crowded (user 2026-11-01: under fire they disperse);
-- nil if none.
function Bots.pickCover(
	points: { { distance: number, hidden: boolean, threat: number, crowded: boolean? } },
	minThreat: number,
	maxDistance: number
): number?
	local best: number? = nil
	for i, p in points do
		if p.hidden and not p.crowded and p.threat >= minThreat and p.distance <= maxDistance then
			if best == nil or p.distance < points[best].distance then
				best = i
			end
		end
	end
	return best
end

-- Where a bot shot at (or near a teammate who was) thinks the shot came from (user 2026-11-01: "be aware of where your
-- shot came from (not where you are, but where it came from)"): from the listener at (lx, lz) toward the muzzle at
-- (ox, oz), the bearing off by up to `angle` degrees and the distance by up to `range` of it, either way (`r1`, `r2`
-- random 0..1). Flat x, z.
function Bots.heard(
	lx: number,
	lz: number,
	ox: number,
	oz: number,
	angle: number,
	range: number,
	r1: number,
	r2: number
): (number, number)
	local dx, dz = ox - lx, oz - lz
	local d = math.sqrt(dx * dx + dz * dz)
	if d < 1e-3 then
		return ox, oz
	end
	local a = math.atan2(dz, dx) + math.rad((r1 * 2 - 1) * angle)
	local guess = d * (1 + (r2 * 2 - 1) * range)
	return lx + math.cos(a) * guess, lz + math.sin(a) * guess
end

-- How often a bot thinks and looks (per second) by how far the nearest player is (Config/Bots.Budget.lod): full rate
-- near a player or in a fight (`fighting`: shot at lately, or a target), less at `mid`, least past `far` (the long walks
-- nobody watches).
function Bots.lod(distance: number, fighting: boolean, cfg: any): (number, number)
	local r = if fighting or distance < cfg.mid then cfg.near elseif distance < cfg.far then cfg.middle else cfg.distant
	return r.think, r.sense
end

-- Whether an enemy `dx, dz` away (flat, from the bot to it) and facing `fx, fz` (flat, unit) is looking at the bot,
-- within `cone` degrees either side.
function Bots.lookingAt(dx: number, dz: number, fx: number, fz: number, cone: number): boolean
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-6 then
		return true
	end
	return (-dx * fx - dz * fz) / len >= math.cos(math.rad(cone))
end

-- Whether a shot from `o` along the unit line `l` for `len` studs passed within `radius` of the point `p`: a near miss
-- (heard and felt).
function Bots.nearMiss(
	ox: number,
	oy: number,
	oz: number,
	lx: number,
	ly: number,
	lz: number,
	len: number,
	px: number,
	py: number,
	pz: number,
	radius: number
): boolean
	local vx, vy, vz = px - ox, py - oy, pz - oz
	local along = vx * lx + vy * ly + vz * lz
	if along < 0 or along > len + radius then
		return false
	end
	local cx, cy, cz = vx - lx * along, vy - ly * along, vz - lz * along
	return cx * cx + cy * cy + cz * cz <= radius * radius
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

-- The aim error `err` (degrees) of a bot suppressed to `level` (0..1): `extra` more degrees at full.
function Bots.shakenAim(err: number, level: number, extra: number): number
	return err + math.clamp(level, 0, 1) * extra
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

-- Whether a bot meant to be moving has stalled: under `distance` studs made over `window` seconds. A sample older
-- than `stale` seconds says nothing (it wasn't walking meanwhile: held in the wave line, down, standing up).
function Bots.stuck(moved: number, elapsed: number, window: number, distance: number, stale: number): boolean
	return elapsed >= window and elapsed < stale and moved < distance
end

-- (x, z) moved inside `bounds` by `margin` studs (the map's walls stop soldiers, but paths don't see them)
function Bots.inside(
	x: number,
	z: number,
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number },
	margin: number
): (number, number)
	return math.clamp(x, bounds.minX + margin, bounds.maxX - margin),
		math.clamp(z, bounds.minZ + margin, bounds.maxZ - margin)
end

return Bots
