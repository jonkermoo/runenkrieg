--!strict
-- The artillery's maths (Config/Artillery; src/server/Artillery, src/client/Artillery): laying a gun toward the
-- gunner's aim (the mount's traverse, then the whole gun swinging), the muzzle and the shell's launch in gun space,
-- the scatter, the recoil (cut short where the breech would hit the ground), the reload and the crystal's state.
-- Gun space: right +X, up +Y, back +Z, origin on the ground under the traverse axis. Angles in degrees. Pure numbers.

local Artillery = {}

export type Lay = { yaw: number, traverse: number, elevation: number }

-- `a` wrapped to -180..180
function Artillery.wrap(a: number): number
	return (a + 180) % 360 - 180
end

-- `from` moved toward `to` by at most `step`
local function toward(from: number, to: number, step: number): number
	if math.abs(to - from) <= step then
		return to
	end
	return from + (if to > from then step else -step)
end

-- The gun's lay after `dt` seconds working toward the wanted world yaw and elevation: the mount traverses toward the
-- aim within +-`gun.traverse` at `traverseRate`; while the aim lies past that and the mount is at its stop, the whole
-- gun swings at `swing`. Elevation goes toward the wanted one, clamped, at `elevationRate`.
function Artillery.lay(state: Lay, wantYaw: number, wantElevation: number, gun: any, dt: number): Lay
	local rel = Artillery.wrap(wantYaw - state.yaw)
	local limit = gun.traverse
	local target = math.clamp(rel, -limit, limit)
	local traverse = toward(state.traverse, target, gun.traverseRate * dt)
	local yaw = state.yaw
	local past = math.abs(rel) - limit
	if past > 0 and math.abs(traverse - target) < 1e-6 then
		local sign = if rel > 0 then 1 else -1
		local turn = math.min(gun.swing * dt, past)
		yaw = Artillery.wrap(yaw + sign * turn)
		-- the mount stays on its stop: the aim relative to the turned gun is still past it
	end
	local elevation =
		toward(state.elevation, math.clamp(wantElevation, gun.elevation[1], gun.elevation[2]), gun.elevationRate * dt)
	return { yaw = yaw, traverse = traverse, elevation = elevation }
end

-- (x, y, z) turned `deg` about the X axis through `p` (+ lifts what lies toward -Z)
local function aboutX(x: number, y: number, z: number, p: { number }, deg: number): (number, number, number)
	local a = math.rad(deg)
	local c, s = math.cos(a), math.sin(a)
	local dy, dz = y - p[2], z - p[3]
	return x, p[2] + dy * c - dz * s, p[3] + dy * s + dz * c
end

-- (x, y, z) turned `deg` about the Y axis through the origin (+ turns -Z toward -X, as CFrame.Angles(0, a, 0))
local function aboutY(x: number, y: number, z: number, deg: number): (number, number, number)
	local a = math.rad(deg)
	local c, s = math.cos(a), math.sin(a)
	return x * c + z * s, y, -x * s + z * c
end

-- The muzzle point and the direction the shell leaves in (gun space) for a traverse and elevation: the bore's, raised
-- by the gun's unseen `aimTilt` degrees (Config/Artillery).
function Artillery.muzzle(
	gun: any,
	traverse: number,
	elevation: number
): (number, number, number, number, number, number)
	local m, t = gun.muzzle, gun.trunnion
	local x, y, z = aboutX(m[1], m[2], m[3], t, elevation)
	x, y, z = aboutY(x, y, z, traverse)
	local dx, dy, dz = aboutX(0, 0, -1, { 0, 0, 0 }, elevation + (gun.aimTilt or 0))
	dx, dy, dz = aboutY(dx, dy, dz, traverse)
	return x, y, z, dx, dy, dz
end

-- A world direction (x, z) as a yaw (CFrame.Angles(0, yaw, 0) looks along it).
function Artillery.yawOf(x: number, z: number): number
	return math.deg(math.atan2(-x, -z))
end

-- The stray of one shot from three random numbers in 0..1 each pair (r1 + r2 is a triangle: most shots near the aim,
-- none past the most): degrees of yaw, degrees of elevation, the speed's share.
function Artillery.scatter(
	s: { yaw: number, elevation: number, speed: number },
	r: { number }
): (number, number, number)
	local function tri(a: number, b: number): number
		return a + b - 1
	end
	return s.yaw * tri(r[1], r[2]), s.elevation * tri(r[3], r[4]), 1 + s.speed * tri(r[5], r[6])
end

-- How far the barrel is back `t` seconds after a shot: straight back over `times[1]`, running out again over
-- `times[2]` (eased), `full` studs at most.
function Artillery.recoilAt(t: number, full: number, times: { number }): number
	if t < 0 then
		return 0
	elseif t < times[1] then
		return full * t / times[1]
	end
	local k = math.clamp((t - times[1]) / times[2], 0, 1)
	return full * (1 - k) * (1 - k)
end

-- The share of the whole gun's jolt `t` s after the shot (Config/Artillery.Fx.Jolt `J`): up to 1 over `rise` s, then
-- a wobble dying away (overshooting a little past rest), 0 before the shot and after `time` s.
function Artillery.joltAt(t: number, J: any): number
	if t < 0 or t >= J.time then
		return 0
	elseif t < J.rise then
		return t / J.rise
	end
	local s = t - J.rise
	return math.exp(-s * J.damp) * math.cos(s * J.wobble)
end

-- The longest recoil at `elevation` keeping the breech's lowest point over `clear.floor` (Config recoilClear), at
-- most `full`; nil `clear`: always full.
function Artillery.recoilLength(full: number, elevation: number, trunnionY: number, clear: any?): number
	if not clear then
		return full
	end
	local a = math.rad(elevation)
	local s = math.sin(a)
	local room = trunnionY - clear.below * math.cos(a) - clear.floor
	if s <= 1e-6 then
		return if room >= 0 then full else 0
	end
	return math.clamp(room / s - clear.along, 0, full)
end

-- The share of the reload done (0..1) at `now`, the gun ready at `readyAt` after `reload` seconds.
function Artillery.loaded(now: number, readyAt: number, reload: number): number
	if reload <= 0 then
		return 1
	end
	return math.clamp(1 - (readyAt - now) / reload, 0, 1)
end

-- How far open the breech is (0 shut .. 1 open) at `now`: shut for the shot, open from `times[1]` after it, shut
-- again `times[2]` before ready; swinging over `swing` seconds.
function Artillery.breechAt(now: number, firedAt: number, readyAt: number, times: { number }, swing: number): number
	local opens, closes = firedAt + times[1], readyAt - times[2]
	if now <= opens or closes <= opens then
		return 0
	end
	local o = math.clamp((now - opens) / swing, 0, 1)
	local c = math.clamp((now - closes) / swing, 0, 1)
	return math.min(o, 1 - c)
end

-- The crystal's state at `now` (Config/Artillery.Crystal; user 2026-10-20: "an empty colored crystal and the color
-- slowly returns ... like its coming back to life"):
--   "Fired"    right after the shot: a white-hot flare draining away (`flare` s);
--   "Charging" drained, then life creeping back: the glow rises slowly (share ^ `curve`), sputtering at first (below
--              `sputter` of the reload), with heartbeats quickening from `beat[1]` to `beat[2]` a second and fading
--              into a steady light near the end;
--   "Awake"    the moment it's full: a bright bloom for `awake` s;
--   "Ready"    a slow breath.
-- Returns the state, the glow (0 dark .. 1 full, above 1: white-hot) and the share charged (0..1, the runes lit).
function Artillery.crystal(
	now: number,
	firedAt: number,
	readyAt: number,
	reload: number,
	c: any
): (string, number, number)
	if now < readyAt then
		local since = now - firedAt
		if since >= 0 and since < c.flare then
			local k = since / c.flare
			return "Fired", (1 - k) * c.flareGlow, 0
		end
		local s = Artillery.loaded(now, readyAt, reload)
		local e = math.max(since - c.flare, 0)
		local glow = s ^ c.curve
		-- the heartbeat: sharp beats, quickening as it fills, strongest midway, gone into the steady glow at the end
		local rate = c.beat[1] + (c.beat[2] - c.beat[1]) * s / 2 -- (the mean rate so far, for the phase)
		local beat = math.max(math.sin(2 * math.pi * rate * e), 0) ^ 6
		glow += c.beatGlow * beat * math.sin(math.pi * math.min(s * 1.15, 1))
		-- sputtering back to life at first
		if s < c.sputter then
			local flick = 0.5 + 0.5 * math.sin(e * 23) * math.sin(e * 7.3)
			glow *= 1 - (1 - s / c.sputter) * flick
		end
		return "Charging", math.clamp(glow, 0, 1), s
	end
	local after = now - readyAt
	if after < c.awake then
		return "Awake", 1 + c.awakeGlow * (1 - after / c.awake), 1
	end
	return "Ready", 1 - c.breath * (0.5 + 0.5 * math.sin(now * c.pulse)), 1
end

-- How lit rune `i` of `n` is (0..1) with the crystal `share` charged: each wakes in turn over `fade` of the charge.
function Artillery.runeLit(i: number, n: number, share: number, fade: number): number
	local from = (i - 1) / n
	return math.clamp((share - from) / math.max(fade, 1e-6), 0, 1)
end

-- Where a shell launched from (ox, oy, oz) at (vx, vy, vz) under `gravity` is at `t` (no drag).
function Artillery.at(
	t: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	gravity: number
): (number, number, number)
	return ox + vx * t, oy + vy * t - gravity * t * t / 2, oz + vz * t
end

-- When a shell launched `height` above a level ground at vertical speed `vy` comes down to it (nil: never).
function Artillery.fall(height: number, vy: number, gravity: number): number?
	local d = vy * vy + 2 * gravity * height
	if gravity <= 0 or d < 0 then
		return nil
	end
	local t = (vy + math.sqrt(d)) / gravity
	return if t > 0 then t else nil
end

-- How far it lands on ground level with the muzzle at `elevation` degrees (flat ground, from the ground).
function Artillery.range(speed: number, elevation: number, gravity: number): number
	return speed * speed * math.sin(math.rad(2 * elevation)) / gravity
end

-- The server's check of an aim sent by the gunner: real numbers in range.
function Artillery.aimOk(yaw: any, elevation: any): boolean
	return type(yaw) == "number"
		and type(elevation) == "number"
		and yaw == yaw
		and elevation == elevation
		and math.abs(yaw) <= 1e6
		and math.abs(elevation) <= 90
end

-- What a blast is to the guns (Config/Artillery.Hits `h`): its named `key`'s entry, or by its `kg` charge.
function Artillery.hitSource(key: string?, kg: number, h: any): any
	if key and h[key] then
		return h[key]
	end
	for _, c in h.byCharge do
		if kg <= c.kg then
			return h[c.source]
		end
	end
	return h.howitzer
end

-- The HP a gun loses to `src` (a Config/Artillery.Hits entry) going off `d` studs from its box: all of `src.direct`
-- within `direct` studs (a direct hit), past that `src.near` fading to nothing at `src.reach`.
function Artillery.gunHit(d: number, src: any, direct: number): number
	if d <= direct then
		return src.direct
	end
	if d >= src.reach or src.reach <= direct then
		return 0
	end
	return src.near * (1 - (d - direct) / (src.reach - direct))
end

-- The ground's height at (`x`, `z`) in gun space under a gun standing on the terrain (Config/Artillery `level`): `flat`
-- (its foot) within the box `lo`..`hi` (x, z), easing back to `natural` (the ground there as it was) over `blend` studs
-- out from it; nil past that (left alone).
function Artillery.levelAt(
	x: number,
	z: number,
	lo: { number },
	hi: { number },
	blend: number,
	flat: number,
	natural: number
): number?
	local dx = math.max(lo[1] - x, x - hi[1], 0)
	local dz = math.max(lo[2] - z, z - hi[2], 0)
	local d = math.sqrt(dx * dx + dz * dz)
	if d <= 0 then
		return flat
	end
	if d >= blend then
		return nil
	end
	local t = d / blend
	local ease = t * t * (3 - 2 * t) -- smoothstep: no edge at either end
	return flat + (natural - flat) * ease
end

-- Whether (`x`, `z`) in gun space is on a gun's ground, the box `lo`..`hi` (x, z): craters never carve it.
function Artillery.onGround(x: number, z: number, lo: { number }, hi: { number }): boolean
	return x >= lo[1] and x <= hi[1] and z >= lo[2] and z <= hi[2]
end

-- A gun's HP after a repair swing giving back `amount` (Config/Artillery.Repair), and what that makes it: "whole",
-- "usable" (it was `broken` and is back to `usable`% of `max`) or nil.
function Artillery.repaired(hp: number, max: number, amount: number, usable: number, broken: boolean): (number, string?)
	local after = math.min(hp + amount, max)
	if after >= max - 1e-6 then
		return max, "whole"
	end
	if broken and after / max * 100 >= usable - 1e-6 then
		return after, "usable"
	end
	return after, nil
end

-- A gun's damage stage (Config/Artillery.Wreck `at`: % of full HP, falling): 0 unhurt, else the last stage it is down to.
function Artillery.wreckStage(hp: number, max: number, at: { number }): number
	local share = if max > 0 then hp / max * 100 else 0
	local stage = 0
	for i, p in at do
		if share <= p then
			stage = i
		end
	end
	return stage
end

-- The eye of a machine gun's gunner (gun space, Config/Artillery.Guns `mg.eye`) for a traverse and elevation: it turns
-- and lifts with the gun, as the muzzle does
function Artillery.eye(gun: any, traverse: number, elevation: number): (number, number, number)
	local e, t = gun.mg.eye, gun.trunnion
	local x, y, z = aboutX(e[1], e[2], e[3], t, elevation)
	return aboutY(x, y, z, traverse)
end

-- The eye of a machine gun's gunner at the hip (gun space, Config/Artillery.Guns `mg.over`) for a traverse: over the
-- shield, turning with the mount as the shield does (the gun's lift leaves it)
function Artillery.over(gun: any, traverse: number): (number, number, number)
	local e = gun.mg.over
	return aboutY(e[1], e[2], e[3], traverse)
end

-- A machine gun laid by the mouse (`dx`, `dy` pixels; Config/Artillery.Guns `mg.look` degrees a pixel): the wanted
-- yaw and elevation after it, straight off, the yaw within its traverse of the gun's own `base` yaw (no swinging past
-- its stops) and the elevation within its limits
function Artillery.mgLay(
	wantYaw: number,
	wantElevation: number,
	base: number,
	dx: number,
	dy: number,
	gun: any
): (number, number)
	local rel = math.clamp(Artillery.wrap(wantYaw - base) - dx * gun.mg.look, -gun.traverse, gun.traverse)
	return Artillery.wrap(base + rel), math.clamp(wantElevation - dy * gun.mg.look, gun.elevation[1], gun.elevation[2])
end

-- Seconds between a machine gun's shots at `rate` rounds a minute
function Artillery.mgInterval(rate: number): number
	return 60 / math.max(rate, 1)
end

-- A machine gun's heat (0 cold .. 1, Config/Artillery.Guns `mg.spread`): each shot adds `per`, it settles back at
-- `recover` a second; and the most a shot strays at that heat (degrees), from `min` to `max`
function Artillery.mgHeat(heat: number, shots: number, dt: number, spread: any): number
	return math.clamp(heat - spread.recover * dt + spread.per * shots, 0, 1)
end

function Artillery.mgSpread(heat: number, spread: any): number
	return spread.min + (spread.max - spread.min) * math.clamp(heat, 0, 1)
end

-- Whether a machine gun can fire now: rounds in its box and not in a box reload (`readyAt`, server time)
function Artillery.mgReady(rounds: number, readyAt: number?, now: number): boolean
	return rounds > 0 and (readyAt == nil or now >= readyAt)
end

-- A shot's stray off the bore (degrees: yaw, elevation) from two random numbers in 0..1, within `spread` degrees of it
-- (evenly over a disc, so the middle isn't crowded)
function Artillery.mgStray(spread: number, r1: number, r2: number): (number, number)
	local d = spread * math.sqrt(r1)
	local a = 2 * math.pi * r2
	return d * math.cos(a), d * math.sin(a)
end

return Artillery
