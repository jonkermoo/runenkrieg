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

-- The match's two teams from `teams` (at least two): a random pair (`r1`, `r2` in [0, 1)) and which takes the West.
function Frontline.pair(teams: { string }, r1: number, r2: number): { West: string, East: string }
	local n = #teams
	local a = math.clamp(math.floor(r1 * n) + 1, 1, n)
	local b = math.clamp(math.floor(r2 * (n - 1)) + 1, 1, n - 1)
	if b >= a then
		b += 1
	end
	return { West = teams[a], East = teams[b] }
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
