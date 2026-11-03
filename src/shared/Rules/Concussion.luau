--!strict
-- Concussion maths (Config/Concussion): how hard a hit or a near blast concusses, what that strength means for each
-- effect of its kind, and how each fades. Pure: strengths are 0..1, times in seconds.

local Concussion = {}

export type Shape = {
	duration: number,
	hold: number,
	blur: number,
	saturation: number,
	brightness: number,
	vignette: number,
	tilt: number,
	sway: number,
	snap: number,
	flash: number,
	ring: number,
	ringFor: number,
	pitch: number,
	muffle: number,
	muffleFor: number,
	muffleBack: number,
	duck: number,
	getUp: number,
	reaction: number,
	aim: number,
}

export type Kind = "Blast" | "Helmet"
export type State = { at: number, strength: number, kind: Kind }

-- shares and multipliers: 1 is "no effect" (the rest: 0)
local NEUTRAL = { duck = true, reaction = true, aim = true, pitch = true }

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

-- A helmet knocked off by a hit that left `left` of `maxHealth`: harder the nearer it came to killing.
function Concussion.helmet(left: number, maxHealth: number, h: { least: number, most: number }): number
	if maxHealth <= 0 then
		return h.least
	end
	return lerp(h.least, h.most, 1 - math.clamp(left / maxHealth, 0, 1))
end

-- A blast that threw a soldier, `fling` how hard (0..1: its damage over the most a blast does).
function Concussion.blast(fling: number, b: { least: number }): number
	return lerp(b.least, 1, math.clamp(fling, 0, 1))
end

-- A blast near the soldier with `kpa` of overpressure at the head: 0 under `from`, `most` from `full`, on a log scale.
function Concussion.near(kpa: number, n: { from: number, full: number, most: number }): number
	if kpa <= n.from or n.full <= n.from then
		return if kpa > n.from then n.most else 0
	end
	return n.most * math.clamp(math.log(kpa / n.from) / math.log(n.full / n.from), 0, 1)
end

-- The effects at the start of a concussion of `strength` of `kind` (cfg.Kinds[kind]): Light at `Light.at`, Heavy at 1,
-- in between in a straight line; weaker than `Light.at`, the Light values shrunk in step (multipliers towards 1).
function Concussion.shape(strength: number, kind: Kind, cfg: any): Shape
	local K = cfg.Kinds[kind]
	local L, H = K.Light, K.Heavy
	local s = math.clamp(strength, 0, 1)
	local out = {} :: any
	if s >= L.at then
		local t = if L.at >= 1 then 1 else (s - L.at) / (1 - L.at)
		for k, v in H do
			out[k] = lerp(L[k], v, t)
		end
	else
		local t = if L.at > 0 then s / L.at else 0
		for k in H do
			out[k] = lerp(if NEUTRAL[k] then 1 else 0, L[k], t)
		end
	end
	return out :: Shape
end

-- How much of a concussion is left `elapsed` seconds in (1 at the start, 0 at `duration` and after), faded by `power`.
function Concussion.fade(elapsed: number, duration: number, power: number): number
	if duration <= 0 or elapsed >= duration then
		return 0
	end
	return (1 - math.clamp(elapsed / duration, 0, 1)) ^ power
end

-- The same, held at 1 for the first `hold` seconds and fading over the rest of `duration`.
function Concussion.held(elapsed: number, hold: number, duration: number, power: number): number
	if duration <= 0 then
		return 0
	elseif elapsed < hold then
		return 1
	end
	return Concussion.fade(elapsed - hold, duration - hold, power)
end

-- How deep the muffle is `elapsed` seconds in (0..1 of the shape's): in over `attack`, held to `muffleFor`, then clear
-- again over `muffleBack`, eased (most of the hearing comes back late, as the ears settle).
function Concussion.muffle(elapsed: number, s: Shape, attack: number): number
	if s.muffle <= 0 or elapsed < 0 then
		return 0
	end
	local into = if attack > 0 then math.clamp(elapsed / attack, 0, 1) else 1
	if elapsed < s.muffleFor then
		return s.muffle * into
	end
	if s.muffleBack <= 0 then
		return 0
	end
	local back = math.clamp((elapsed - s.muffleFor) / s.muffleBack, 0, 1)
	return s.muffle * into * (1 - back * back)
end

-- A kick of 1 at `elapsed` 0 dying away squared to nothing at `time`.
function Concussion.kick(elapsed: number, time: number): number
	if time <= 0 or elapsed >= time or elapsed < 0 then
		return 0
	end
	local f = 1 - elapsed / time
	return f * f
end

-- What is left of `state` at `now` as a strength (its strength x its picture's fade), 0 when none.
function Concussion.left(state: State?, now: number, cfg: any): number
	if not state then
		return 0
	end
	local shape = Concussion.shape(state.strength, state.kind, cfg)
	return state.strength * Concussion.held(now - state.at, shape.hold, shape.duration, cfg.Fade)
end

-- A new concussion of `strength` and `kind` at `now` over `state`: the new one when it is at least as strong as what is
-- left of the old one, else the old one kept (nil: keep). A second blast restarts it; it never adds up.
function Concussion.add(state: State?, strength: number, kind: Kind, now: number, cfg: any): State?
	if strength <= 0 or strength < Concussion.left(state, now, cfg) then
		return nil
	end
	return { at = now, strength = strength, kind = kind }
end

-- Seconds a concussion in `state` adds to a get-up wait at `now`: the shape's `getUp`, faded.
function Concussion.getUp(state: State?, now: number, cfg: any): number
	if not state then
		return 0
	end
	local shape = Concussion.shape(state.strength, state.kind, cfg)
	return shape.getUp * Concussion.held(now - state.at, shape.hold, shape.duration, cfg.Fade)
end

-- A bot's difficulty `d` while concussed (`state` at `now`): reaction and aim error multiplied, fading back to normal.
-- Returns `d` itself when not concussed (no copy).
function Concussion.daze(d: any, state: State?, now: number, cfg: any): any
	if not state then
		return d
	end
	local shape = Concussion.shape(state.strength, state.kind, cfg)
	local f = Concussion.held(now - state.at, shape.hold, shape.duration, cfg.Fade)
	if f <= 0 then
		return d
	end
	local out = table.clone(d)
	local aim = lerp(1, shape.aim, f)
	out.reaction = d.reaction * lerp(1, shape.reaction, f)
	out.aimError = d.aimError * aim
	out.aimFloor = d.aimFloor * aim
	return out
end

return Concussion
