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
