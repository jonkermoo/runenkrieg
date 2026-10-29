--!strict
-- The look tilt's maths (src/client/LookTilt, src/server/LookTilt): the torso's share of the camera pitch, the gun's
-- turn about the shoulders for the rest, the third-person turn onto the crosshair (Config/Camera.Aim3P), and what
-- other players are sent (quantized, throttled, and clamped by the server). Angles in degrees.

local LookTilt = {}

export type Send = {
	Rate: number,
	Step: number,
	FollowStep: number,
	AimStep: number,
	MaxPitch: number,
	Smoothing: number,
}
export type Max = { yaw: number, pitch: number }

-- value rounded to the nearest multiple of step
function LookTilt.quantize(value: number, step: number): number
	return math.floor(value / step + 0.5) * step
end

-- the torso's tilt for a camera pitch: a share of it, capped
function LookTilt.torso(pitch: number, share: number, max: number): number
	return math.clamp(pitch * share, -max, max)
end

-- the arms and gun turn about the shoulder line by the rest of the pitch the hold follows (follow = the hold's
-- share, Config/Camera.Follow; 0 with no weapon), on top of the torso's tilt
function LookTilt.weaponTurn(pitch: number, follow: number, torso: number): number
	return follow * pitch - torso
end

-- share of the way to move toward a target this frame, at `rate` per second
function LookTilt.ease(rate: number, dt: number): number
	return 1 - math.exp(-rate * dt)
end

-- ---- third person: the weapon onto the crosshair (Config/Camera.Aim3P) ----

-- yaw and pitch (degrees) of a direction: yaw + to the left of -Z like CFrame.fromOrientation's, pitch + up
function LookTilt.angles(x: number, y: number, z: number): (number, number)
	local length = math.sqrt(x * x + y * y + z * z)
	if length < 1e-9 then
		return 0, 0
	end
	return math.deg(math.atan2(-x, -z)), math.deg(math.asin(math.clamp(y / length, -1, 1)))
end

-- an angle (degrees) wrapped into -180..180
function LookTilt.wrap(angle: number): number
	return (angle + 180) % 360 - 180
end

-- the yaw and pitch (degrees, capped) that turn a weapon pointing at (yaw, pitch) onto the line at (wantYaw, wantPitch)
function LookTilt.aimTurn(yaw: number, pitch: number, wantYaw: number, wantPitch: number, max: Max): (number, number)
	return math.clamp(LookTilt.wrap(wantYaw - yaw), -max.yaw, max.yaw),
		math.clamp(wantPitch - pitch, -max.pitch, max.pitch)
end

-- an average angle (degrees) moved a share `k` toward `angle`, the short way round
function LookTilt.settle(average: number, angle: number, k: number): number
	return average + LookTilt.wrap(angle - average) * k
end

-- how fast the average pointing follows (per second) when it is `gap` degrees off: `slow` within `c.from` (the
-- animation's breath and stride sway around it), rising to `c.rate` at `c.full` (a new hold, e.g. crouching)
function LookTilt.settleRate(gap: number, slow: number, c: { rate: number, from: number, full: number }): number
	local s = math.clamp((math.abs(gap) - c.from) / math.max(c.full - c.from, 1e-6), 0, 1)
	return slow + (c.rate - slow) * s
end

-- how far along the crosshair's line (studs from the camera) the weapon points: at what it hits, else `fallback`;
-- never nearer than `min` past `from` (where the line passes the weapon)
function LookTilt.aimDistance(hit: number?, from: number, fallback: number, min: number): number
	return math.max(hit or fallback, from + min)
end

-- client: what to send now (quantized pitch, follow and the turn onto the crosshair), or nil when nothing changed or
-- the last send was too recent
function LookTilt.toSend(
	pitch: number,
	follow: number,
	aimYaw: number,
	aimPitch: number,
	last: { pitch: number, follow: number, aimYaw: number, aimPitch: number, at: number },
	now: number,
	send: Send,
	max: Max
): (number?, number?, number?, number?)
	if now - last.at < 1 / send.Rate then
		return nil, nil, nil, nil
	end
	local p = LookTilt.quantize(math.clamp(pitch, -send.MaxPitch, send.MaxPitch), send.Step)
	local f = LookTilt.quantize(math.clamp(follow, 0, 1), send.FollowStep)
	local ay = LookTilt.quantize(math.clamp(aimYaw, -max.yaw, max.yaw), send.AimStep)
	local ap = LookTilt.quantize(math.clamp(aimPitch, -max.pitch, max.pitch), send.AimStep)
	if p == last.pitch and f == last.follow and ay == last.aimYaw and ap == last.aimPitch then
		return nil, nil, nil, nil
	end
	return p, f, ay, ap
end

-- The head's turn toward the look (degrees, + to the left like Roblox's yaw): `look` is the camera's yaw from the
-- torso's facing, `glance` the animation's own neck turn, `current` the head's turn now. Capped so the head with the
-- glance stays within max; looking round behind (past `behind`), the head stays on the side it is already on rather than
-- whipping across.
function LookTilt.headYaw(look: number, glance: number, current: number, max: number, behind: number): number
	look = (look + 180) % 360 - 180
	if math.abs(look) > behind and look * current < 0 then
		look = if current > 0 then max else -max
	end
	return math.clamp(look, -max - glance, max - glance)
end

export type HeadSend = { Rate: number, Step: number, Range: number, Smoothing: number }

-- client: the head's turn to send now (quantized), or nil when unchanged or the last send was too recent
function LookTilt.yawToSend(
	yaw: number,
	last: { yaw: number, at: number },
	now: number,
	send: HeadSend,
	max: number
): number?
	if now - last.at < 1 / send.Rate then
		return nil
	end
	local y = LookTilt.quantize(math.clamp(yaw, -max, max), send.Step)
	return if y == last.yaw then nil else y
end

-- server: a client's head turn made safe (a finite number, clamped to +-max and quantized), or nil to drop it
function LookTilt.sanitizeYaw(yaw: unknown, step: number, max: number): number?
	if type(yaw) ~= "number" or yaw ~= yaw then
		return nil
	end
	return LookTilt.quantize(math.clamp(yaw, -max, max), step)
end

-- server: whether a soldier `distance` studs away is near enough to see another's head turn
function LookTilt.inRange(distance: number, range: number): boolean
	return distance <= range
end

-- server: a client's raw payload made safe (numbers, finite, clamped, quantized), or nil to drop it; a turn onto the
-- crosshair that isn't a finite number counts as none
function LookTilt.sanitize(
	pitch: unknown,
	follow: unknown,
	aimYaw: unknown,
	aimPitch: unknown,
	send: Send,
	max: Max
): (number?, number?, number, number)
	local function aim(v: unknown, cap: number): number
		if type(v) ~= "number" or v ~= v then
			return 0
		end
		return LookTilt.quantize(math.clamp(v, -cap, cap), send.AimStep)
	end
	local ay, ap = aim(aimYaw, max.yaw), aim(aimPitch, max.pitch)
	if type(pitch) ~= "number" or type(follow) ~= "number" then
		return nil, nil, ay, ap
	end
	if pitch ~= pitch or follow ~= follow then -- NaN
		return nil, nil, ay, ap
	end
	local p = LookTilt.quantize(math.clamp(pitch, -send.MaxPitch, send.MaxPitch), send.Step)
	local f = LookTilt.quantize(math.clamp(follow, 0, 1), send.FollowStep)
	return p, f, ay, ap
end

return LookTilt
