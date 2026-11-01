--!strict
-- Concussion maths (Config/Concussion): how hard a hit concusses, what that strength means for each effect, and how it
-- fades. Pure: strengths are 0..1, times in seconds.

local Concussion = {}

export type Shape = {
	duration: number,
	blur: number,
	saturation: number,
	brightness: number,
	ring: number,
	duck: number,
	duckFor: number,
	getUp: number,
	reaction: number,
	aim: number,
}

export type State = { at: number, strength: number }

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

-- The effects at the start of a concussion of `strength`: Light at `Light.at`, Heavy at 1, in between in a straight
-- line; weaker than `Light.at`, the Light values shrunk in step (multipliers towards 1).
function Concussion.shape(strength: number, cfg: any): Shape
	local L, H = cfg.Light, cfg.Heavy
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
			local base = if k == "duck" or k == "reaction" or k == "aim" then 1 else 0
			out[k] = lerp(base, L[k], t)
		end
		out.duration = L.duration * t
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

-- What is left of `state` at `now` as a strength (its strength x its fade), 0 when none.
function Concussion.left(state: State?, now: number, cfg: any): number
	if not state then
		return 0
	end
	local shape = Concussion.shape(state.strength, cfg)
	return state.strength * Concussion.fade(now - state.at, shape.duration, cfg.Fade)
end

-- A new concussion of `strength` at `now` over `state`: the new one when it is at least as strong as what is left of the
-- old one, else the old one kept (nil: keep).
function Concussion.add(state: State?, strength: number, now: number, cfg: any): State?
	if strength <= 0 or strength < Concussion.left(state, now, cfg) then
		return nil
	end
	return { at = now, strength = strength }
end

-- The other sounds' volume share `elapsed` seconds in: `duck` for `duckFor` seconds, then back to 1 over `recover`.
function Concussion.duck(elapsed: number, duck: number, duckFor: number, recover: number): number
	if elapsed < duckFor then
		return duck
	end
	if recover <= 0 then
		return 1
	end
	return lerp(duck, 1, math.clamp((elapsed - duckFor) / recover, 0, 1))
end

-- Seconds a concussion in `state` adds to a get-up wait at `now`: the shape's `getUp`, faded.
function Concussion.getUp(state: State?, now: number, cfg: any): number
	if not state then
		return 0
	end
	local shape = Concussion.shape(state.strength, cfg)
	return shape.getUp * Concussion.fade(now - state.at, shape.duration, cfg.Fade)
end

-- A bot's difficulty `d` while concussed (`state` at `now`): reaction and aim error multiplied, fading back to normal.
-- Returns `d` itself when not concussed (no copy).
function Concussion.daze(d: any, state: State?, now: number, cfg: any): any
	if not state then
		return d
	end
	local shape = Concussion.shape(state.strength, cfg)
	local f = Concussion.fade(now - state.at, shape.duration, cfg.Fade)
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
