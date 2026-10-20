--!strict
-- The look tilt's maths (src/client/LookTilt, src/server/LookTilt): the torso's share of the camera pitch, the gun's
-- turn about the shoulders for the rest, and the pitch sent to other players (quantized, throttled, and clamped by
-- the server). Angles in degrees.

local LookTilt = {}

export type Send = { Rate: number, Step: number, FollowStep: number, MaxPitch: number, Smoothing: number }

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

-- client: what to send now (quantized pitch and follow), or nil when nothing changed or the last send was too recent
function LookTilt.toSend(
	pitch: number,
	follow: number,
	last: { pitch: number, follow: number, at: number },
	now: number,
	send: Send
): (number?, number?)
	if now - last.at < 1 / send.Rate then
		return nil, nil
	end
	local p = LookTilt.quantize(math.clamp(pitch, -send.MaxPitch, send.MaxPitch), send.Step)
	local f = LookTilt.quantize(math.clamp(follow, 0, 1), send.FollowStep)
	if p == last.pitch and f == last.follow then
		return nil, nil
	end
	return p, f
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

-- server: a client's raw payload made safe (numbers, finite, clamped, quantized), or nil to drop it
function LookTilt.sanitize(pitch: unknown, follow: unknown, send: Send): (number?, number?)
	if type(pitch) ~= "number" or type(follow) ~= "number" then
		return nil, nil
	end
	if pitch ~= pitch or follow ~= follow then -- NaN
		return nil, nil
	end
	local p = LookTilt.quantize(math.clamp(pitch, -send.MaxPitch, send.MaxPitch), send.Step)
	local f = LookTilt.quantize(math.clamp(follow, 0, 1), send.FollowStep)
	return p, f
end

return LookTilt
