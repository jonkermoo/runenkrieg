--!strict
-- The frontline match (Config/Frontline; src/server/Frontline): which sector each side may attack, how the soldiers in
-- a zone move its control, captures, the winner and where each side spawns. Pure: numbers and tables only.
-- Sides are "West" and "East" (the ends of the map's sector chain, Config/Maps/*.sectors, listed west to east); a
-- sector's owner is a side or "Neutral". Control runs from 1 (West's end) to -1 (East's end).

local Frontline = {}

export type Side = string -- "West" | "East"
export type State = { owner: { string }, control: { number } }
export type Event = { kind: string, index: number, side: Side } -- kind "Neutral" (side: who neutralised it) / "Captured"

local SIGN = { West = 1, East = -1 }

-- The other side.
function Frontline.enemy(side: Side): Side
	return if side == "West" then "East" else "West"
end

-- Where a sector held by `owner` rests: its side's end, or 0 when neutral.
function Frontline.rest(owner: string): number
	return SIGN[owner] or 0
end

-- A match's start from the map's sectors (each with startOwner).
function Frontline.new(sectors: { any }): State
	local s: State = { owner = {}, control = {} }
	for i, sector in sectors do
		s.owner[i] = sector.startOwner
		s.control[i] = Frontline.rest(sector.startOwner)
	end
	return s
end

-- How many sectors `side` holds in an unbroken run from its own end.
local function run(state: State, side: Side): number
	local n, k = #state.owner, 0
	for step = 1, n do
		local i = if side == "West" then step else n + 1 - step
		if state.owner[i] ~= side then
			break
		end
		k += 1
	end
	return k
end

-- The sector `side` may attack: the one just past its front (nil once it holds them all).
function Frontline.target(state: State, side: Side): number?
	local n, k = #state.owner, run(state, side)
	if k >= n then
		return nil
	end
	return if side == "West" then k + 1 else n - k
end

-- The sector `side` spawns at (user 2026-10-27: "always front most, except at the start where every player starts at
-- HQ until the first point is captured"): its HQ until the match's first capture, then its frontmost sector in the run
-- from its HQ (its HQ when it holds none of it).
function Frontline.spawn(state: State, side: Side, anyCaptured: boolean): number
	local n = #state.owner
	local home = if side == "West" then 1 else n
	local k = run(state, side)
	if not anyCaptured or k == 0 then
		return home
	end
	return if side == "West" then k else n + 1 - k
end

-- The sector `side` spawns at this wave (user 2026-10-27): Frontline.spawn, but one sector back toward its own end
-- while the enemy leads in that sector's zone (more of them in it than of `side`). `counts` as in Frontline.step.
function Frontline.spawnSector(
	state: State,
	side: Side,
	anyCaptured: boolean,
	counts: { { West: number, East: number } }
): number
	local i = Frontline.spawn(state, side, anyCaptured)
	local home = if side == "West" then 1 else #state.owner
	local c: any = counts[i] or {}
	if i ~= home and (c[Frontline.enemy(side)] or 0) > (c[side] or 0) then
		i += if side == "West" then -1 else 1
	end
	return i
end

-- When the next wave goes: waves go every `every` seconds from `start`; the first at or after `now`.
function Frontline.nextWave(start: number, every: number, now: number): number
	if now <= start or every <= 0 then
		return start
	end
	return start + math.ceil((now - start) / every - 1e-9) * every
end

-- Slot `k` (from 1) of a wave line (Config/Frontline.Line): `perRow` side by side `gap` apart, filled from the middle
-- out (0, right, left, ...), each row `rowGap` behind the last. Returns studs right of and behind the line's centre.
function Frontline.slot(k: number, line: any): (number, number)
	local row = (k - 1) // line.perRow
	local col = (k - 1) % line.perRow
	local right = if col % 2 == 1 then (col + 1) / 2 else -col / 2
	return right * line.gap, row * line.rowGap
end

-- The points under a standing soldier (offsets from its middle, studs) where the ground is sampled: its middle, its
-- legs' sides and its four corners `foot` out. Its feet go on the highest, so no part of a foot is ever in the ground
-- (user 2026-11-01: "my body was in the ground"; 2026-11-02: "plays spawn under the ground").
function Frontline.footprint(foot: number): { { number } }
	local out = {}
	for _, x in { -foot, 0, foot } do
		for _, z in { -foot, 0, foot } do
			table.insert(out, { x, z })
		end
	end
	return out
end

-- How far a held soldier must be lifted so its feet stand `lift` over the highest ground sampled under it now (0 when
-- they already do): the ground can rise under a soldier waiting in its wave line (dug spoil, a crater's rim).
function Frontline.liftNeeded(feet: number, highest: number, lift: number): number
	return math.max(0, highest + lift - feet)
end

-- Where `side`'s wave line stands while sector `i` (a fought-over one, not its HQ) is its furthest forward: its front
-- row's middle `line.back` of the way from sector i's point back to the point behind it, so closer to the sector
-- behind (user 2026-11-02: "it should be closer to the previous sector than the furthest sector they have"), facing
-- the sector ahead. Returns the middle (x, z) and the facing (unit x, z).
function Frontline.lineCentre(sectors: { any }, i: number, side: Side, line: any): (number, number, number, number)
	local s = sectors[i]
	local back = sectors[if side == "West" then i - 1 else i + 1]
	local aim = sectors[if side == "West" then i + 1 else i - 1] or s
	local cx, cz = s.x + (back.x - s.x) * line.back, s.z + (back.z - s.z) * line.back
	local fx, fz = aim.x - cx, aim.z - cz
	local fl = math.sqrt(fx * fx + fz * fz)
	if fl < 1 then
		return cx, cz, if side == "West" then 1 else -1, 0
	end
	return cx, cz, fx / fl, fz / fl
end

-- The ground each wave line at a fought-over sector stands on (Frontline.lineCentre, as src/server/Frontline's lineOf;
-- every slot up to `line.tries`), as quads of { x, z } corners
-- grown by `pad`: kept clear of trees so a whole line stands (user 2026-11-02, the lines moved back into the groves).
function Frontline.lineQuads(sectors: { any }, line: any, pad: number): { { { number } } }
	local out = {}
	local n = #sectors
	local rows = math.ceil(line.tries / line.perRow)
	local half = (line.perRow - 1) / 2 * line.gap + pad
	for i = 2, n - 1 do
		for _, side: Side in { "West", "East" } :: { Side } do
			local cx, cz, fx, fz = Frontline.lineCentre(sectors, i, side, line)
			local rx, rz = -fz, fx
			local front, rear = pad, (rows - 1) * line.rowGap + pad
			local q = {}
			for _, c in { { -half, front }, { half, front }, { half, -rear }, { -half, -rear } } do
				table.insert(q, { cx + rx * c[1] + fx * c[2], cz + rz * c[1] + fz * c[2] })
			end
			table.insert(out, q)
		end
	end
	return out
end

-- How many sectors `side` holds in an unbroken run from its own end (1: only its HQ).
function Frontline.held(state: State, side: Side): number
	return run(state, side)
end

-- Why `side` can't build gun `key` while it holds `held` sectors from its end (Config/Frontline.Artillery: a
-- `lastStand` gun only while it holds `unlockAt` or fewer); nil: it can, and keys not listed never wait.
function Frontline.gunLocked(cfg: any, key: string, held: number): string?
	if cfg.lastStand[key] and held > cfg.unlockAt then
		return cfg.why
	end
	return nil
end

-- The side the reinforcements boost goes to (Config/Frontline.Reinforcements): the smaller one, while the other has
-- at least `gap` more players and `share` more; nil when the sides are near enough.
function Frontline.reinforced(cfg: any, west: number, east: number): Side?
	local big, small, side = west, east, "East"
	if east > west then
		big, small, side = east, west, "West"
	end
	if big - small >= cfg.gap and big >= small * (1 + cfg.share) then
		return side
	end
	return nil
end

-- What one soldier in a zone counts for (Config/Frontline.BotWeight): a player 1, a bot `BotWeight`.
function Frontline.weight(cfg: any, bot: boolean): number
	return if bot then cfg.BotWeight else 1
end

-- How far control moves in `dt` seconds with soldiers `west` and `east` in the zone: by the lead (at most
-- MaxAdvantage) at one soldier's rate times `rate` (momentum), toward the side ahead; nil when nobody leads (empty,
-- or even: contested).
function Frontline.push(cfg: any, west: number, east: number, dt: number, rate: number?): number?
	local lead = west - east
	if lead == 0 then
		return nil
	end
	local by = math.min(math.abs(lead), cfg.MaxAdvantage) * 2 / cfg.CaptureSeconds * dt * (rate or 1)
	return if lead > 0 then by else -by
end

-- Moves sector `i`'s control from `from` to `to`, changing its owner where it crosses: the holder loses it at 0, a
-- side takes it at its end. Returns the event, if any.
local function move(state: State, i: number, to: number, by: Side?): Event?
	local owner = state.owner[i]
	to = math.clamp(to, -1, 1)
	state.control[i] = to
	if owner ~= "Neutral" and to * SIGN[owner] <= 0 then
		state.owner[i] = "Neutral"
		state.control[i] = 0
		return { kind = "Neutral", index = i, side = by or Frontline.enemy(owner) }
	end
	for side, sign in SIGN do
		if owner ~= side and to == sign then
			state.owner[i] = side
			return { kind = "Captured", index = i, side = side }
		end
	end
	return nil
end

-- One tick of `dt` seconds. `counts[i]` = { West = n, East = n }: the soldiers in sector i's zone. The sectors either
-- side may attack move by the lead in their zone (times `rate`, the momentum); contested (even, not empty) ones hold;
-- the rest drift back to their holder's end. Returns the captures and neutralisations, in sector order.
function Frontline.step(
	state: State,
	cfg: any,
	counts: { { West: number, East: number } },
	dt: number,
	rate: number?
): { Event }
	local live: { [number]: boolean } = {}
	for _, side in { "West", "East" } do
		local t = Frontline.target(state, side)
		if t then
			live[t] = true
		end
	end
	local events: { Event } = {}
	for i in state.owner do
		local c = counts[i] or { West = 0, East = 0 }
		local w, e = c.West or 0, c.East or 0
		local d = if live[i] then Frontline.push(cfg, w, e, dt, rate) else nil
		local event: Event? = nil
		if d then
			-- a side neutralises the other's sector at 0, then needs to keep pushing to take it
			event = move(state, i, state.control[i] + d, if d > 0 then "West" else "East")
		elseif not live[i] or (w == 0 and e == 0) then
			local rest, now = Frontline.rest(state.owner[i]), state.control[i]
			local by = dt / cfg.DrainSeconds
			state.control[i] = if now < rest then math.min(now + by, rest) else math.max(now - by, rest)
		end
		if event then
			table.insert(events, event)
		end
	end
	return events
end

-- Each sector's control per second now (+ toward West, - toward East): the lead's push in the sectors either side may
-- attack, 0 where nothing moves it (contested, empty or out of reach; the drift back isn't counted). For the admin
-- readout.
function Frontline.rates(state: State, cfg: any, counts: { { West: number, East: number } }, rate: number?): { number }
	local live: { [number]: boolean } = {}
	for _, side in { "West", "East" } do
		local t = Frontline.target(state, side)
		if t then
			live[t] = true
		end
	end
	local out = {}
	for i in state.owner do
		local c = counts[i] or { West = 0, East = 0 }
		out[i] = if live[i] then Frontline.push(cfg, c.West or 0, c.East or 0, 1, rate) or 0 else 0
	end
	return out
end

-- Seconds until control moving at `perSecond` (Frontline.rates) reaches the end it heads for (a capture there); nil
-- when it isn't moving.
function Frontline.eta(control: number, perSecond: number): number?
	if perSecond == 0 then
		return nil
	end
	local to = if perSecond > 0 then 1 else -1
	return math.abs(to - control) / math.abs(perSecond)
end

-- The capture speed's multiplier after `still` seconds without a capture (Config/Frontline.Momentum): 1 until
-- `after`, then `perMinute` more per minute, at most `max`.
function Frontline.momentum(cfg: any, still: number): number
	local m = cfg.Momentum
	return math.min(1 + math.max(still - m.after, 0) / 60 * m.perMinute, m.max)
end

-- Whether a match can start: each side has at least `least` players.
function Frontline.ready(west: number, east: number, least: number): boolean
	return west >= least and east >= least
end

-- Whether a kill by a soldier of `side` earns a Defend (Config/Classes.Earn): the killer or the victim (`spots`, each
-- { x, z }) within `reach` past the zone of a sector `side` holds while the enemy is attacking it.
function Frontline.defends(state: State, sectors: { any }, side: Side, spots: { { number } }, reach: number): boolean
	local i = Frontline.target(state, Frontline.enemy(side))
	if not i or state.owner[i] ~= side then
		return false
	end
	local s, r = sectors[i], sectors[i].radius + reach
	for _, p in spots do
		if (p[1] - s.x) ^ 2 + (p[2] - s.z) ^ 2 <= r * r then
			return true
		end
	end
	return false
end

-- The side that won: the one holding the other's HQ (the chain's ends).
function Frontline.winner(state: State): Side?
	local n = #state.owner
	if state.owner[1] == "East" then
		return "East"
	end
	if state.owner[n] == "West" then
		return "West"
	end
	return nil
end

-- Whether a spot `dx`, `dz` across and `dy` above the zone's ground point is in a zone of `radius`.
function Frontline.inZone(dx: number, dz: number, dy: number, radius: number, height: number): boolean
	return dx * dx + dz * dz <= radius * radius and math.abs(dy) <= height
end

-- The match's two teams from `teams` (at least two): `always` and one other at random (`r1` in [0, 1)), `r2` < 0.5
-- putting `always` in the West (user 2026-11-01: "it should always be green OR brown vs gray")
function Frontline.pair(teams: { string }, always: string, r1: number, r2: number): { West: string, East: string }
	local others = {}
	for _, t in teams do
		if t ~= always then
			table.insert(others, t)
		end
	end
	local foe = others[math.clamp(math.floor(r1 * #others) + 1, 1, #others)]
	return if r2 < 0.5 then { West = always, East = foe } else { West = foe, East = always }
end

-- The pair a map is fought by (user 2026-11-04, "fixed pair per map"): its own `pair` when that names two different
-- teams of `teams`, one of them `always`, else a random one (Frontline.pair).
function Frontline.mapPair(
	own: unknown,
	teams: { string },
	always: string,
	r1: number,
	r2: number
): { West: string, East: string }
	if type(own) == "table" then
		local w, e = (own :: any).West, (own :: any).East
		if w ~= e and table.find(teams, w) and table.find(teams, e) and (w == always or e == always) then
			return { West = w, East = e }
		end
	end
	return Frontline.pair(teams, always, r1, r2)
end

-- The pair as Workspace's MatchTeams text ("west,east"), and back (nil when it isn't one).
function Frontline.pairText(pair: { West: string, East: string }): string
	return `{pair.West},{pair.East}`
end

function Frontline.parsePair(text: unknown): { West: string, East: string }?
	if type(text) ~= "string" then
		return nil
	end
	local w, e = string.match(text, "^([^,]+),([^,]+)$")
	if not w or not e or w == e then
		return nil
	end
	return { West = w :: string, East = e :: string }
end

-- The side team `kit` plays on (nil: not in the match).
function Frontline.sideOf(pair: { West: string, East: string }?, kit: unknown): Side?
	if not pair then
		return nil
	end
	return if kit == pair.West then "West" elseif kit == pair.East then "East" else nil
end

return Frontline
