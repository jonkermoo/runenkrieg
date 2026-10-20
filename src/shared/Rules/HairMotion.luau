--!strict
-- Hair sway rules (Config/HairMotion): which part of the hair a bone holds, where each bone wants to swing, and the
-- spring that takes it there. Pure: src/client/HairMotion feeds it the soldier's motion.

local HairMotion = {}

export type Bone = { kind: "back" | "side", index: number, side: number }
-- the soldier's motion in its head's frame: forward / sideways (to its right) / up in studs/s, turn = yaw rate
-- (rad/s, + turning left), speed = flat speed
export type Motion = { forward: number, sideways: number, up: number, turn: number, speed: number }

-- What a bone of the hair rig holds (tools/hair/rig_hair.py): "Back<n>" a link of the back chain, "SideL" / "SideR"
-- the locks beside the face (side 1 = the soldier's right); nil for Root and anything else (never moved).
function HairMotion.bone(name: string): Bone?
	local n = string.match(name, "^Back(%d+)$")
	if n then
		return { kind = "back", index = tonumber(n) :: number, side = 0 }
	elseif name == "SideR" then
		return { kind = "side", index = 1, side = 1 }
	elseif name == "SideL" then
		return { kind = "side", index = 1, side = -1 }
	end
	return nil
end

local function clamp(x: number, most: number): number
	return math.clamp(x, -most, most)
end

-- Where `bone` (of a back chain `n` long) wants to be at time `t`: degrees its tip swings toward the back (`back`)
-- and toward the soldier's right (`right`). `seed` puts each soldier on its own rhythm; `scale` is 1 bareheaded,
-- Config.HelmetOn under a helmet; dead: 0 everywhere (the hair settles and holds still).
function HairMotion.target(
	bone: Bone,
	n: number,
	t: number,
	m: Motion,
	seed: number,
	scale: number,
	dead: boolean,
	cfg: any
): (number, number)
	if dead then
		return 0, 0
	end
	local B = cfg.Back
	local c = if bone.kind == "back" then B else cfg.Side
	local share = if bone.kind == "back" then 1 / math.max(1, n) else 1
	local phase = if bone.kind == "back" then (bone.index - 1) * B.phasePerBone else bone.side * 1.3
	local sway = math.sin((t * c.swayHz + seed) * 2 * math.pi - phase) * c.swayDeg
	local stride = math.clamp(m.speed / B.bobSpeed, 0, 1)
	local bob = math.sin((t * B.bobHz + seed) * 2 * math.pi) * c.bobDeg * stride
	local lift = math.clamp(m.forward * c.liftPerSpeed, 0, c.liftMax)
	local fall = math.clamp(-m.up * c.fallPerSpeed, 0, c.fallMax)
	local lag = clamp(-m.sideways * c.lagPerSpeed, c.lagMax)
	local turn = clamp(-m.turn * c.turnLag, c.turnMax)
	local back, right
	if bone.kind == "back" then
		back = lift + bob + fall
		right = sway + lag + turn
	else
		-- locks beside the face: trail back, and lift out to their own side when falling
		back = lift + bob
		right = sway + lag + turn + bone.side * fall
	end
	return back * share * scale, right * share * scale
end

-- One spring step: the angle `x` moving at `v` toward `target` over `dt` (sub-stepped, so a long frame never blows
-- up). Returns the new angle and speed, the angle held within ±`most`.
function HairMotion.spring(x: number, v: number, target: number, dt: number, most: number, cfg: any): (number, number)
	local k, d = cfg.stiffness, cfg.damping
	local steps = math.max(1, math.ceil(dt / (1 / 60)))
	local h = math.min(dt, 0.25) / steps
	for _ = 1, steps do
		v += ((target - x) * k - v * d) * h
		x += v * h
	end
	if x > most then
		x, v = most, math.min(v, 0)
	elseif x < -most then
		x, v = -most, math.max(v, 0)
	end
	return x, v
end

return HairMotion
