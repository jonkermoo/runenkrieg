--!strict
-- A thrown grenade's whole path, worked out on the server as it leaves the hand (src/server/Grenades; Config/Grenades
-- Motion and Types[name].motion, Rules/Grenade.hit / thunk / roll / rests). It flies the throw's arc tumbling end over
-- end along the throw, bounces a little off what it hits (swept as a ball of its own thickness each step, so it never
-- passes through thin ground or a wall), then lies on its side and rolls across its long axis to a stop, or on down a
-- slope too steep to rest on, or off an edge into the air again. Every client plays the same frames back
-- (src/client/Grenades), and the blast goes off where the path ends.
-- Scripted, not left to Roblox's physics: the physics' box spun 140-195 rad/s off contacts (Studio 2026-10-20) and,
-- damped down, stopped dead where it landed (user 2026-10-25).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Grenades)
local Rules = require(Shared.Rules.Grenade)

local GrenadeFlight = {}

-- its body: a ball `radius` thick, its long axis (`long`, in its own space) and where the model's pivot sits on it
export type Body = { radius: number, long: Vector3, toPivot: CFrame }
export type Motion = {
	spin: number,
	first: number,
	keep: number,
	bounce: number,
	settle: number,
	spinKeep: number,
	resist: number,
	slide: number,
}
-- `times` (seconds from the throw) and the model's pivot at each; `thunks`: each hit loud enough to hear (`share` of the
-- thunk's volume, Rules/Grenade.thunk) at `at`; `rest`: where the body ends up
export type Thunk = { t: number, share: number, at: Vector3 }
export type Path = { times: { number }, frames: { CFrame }, thunks: { Thunk }, rest: Vector3 }

-- the body as the model sits now: its box, the ball's radius half the box's middle size, the long axis its biggest
function GrenadeFlight.body(model: Model): (Body, CFrame)
	local box, size = model:GetBoundingBox()
	local sizes = { size.X, size.Y, size.Z }
	table.sort(sizes)
	local long = if size.X >= size.Y and size.X >= size.Z
		then Vector3.xAxis
		elseif size.Y >= size.Z then Vector3.yAxis
		else Vector3.zAxis
	return { radius = sizes[2] / 2, long = long, toPivot = box:ToObjectSpace(model:GetPivot()) }, box
end

-- the turn taking direction `a` onto `b` (both unit)
local function turnTo(a: Vector3, b: Vector3): CFrame
	local c = a:Cross(b)
	local angle = math.acos(math.clamp(a:Dot(b), -1, 1))
	if c.Magnitude < 1e-5 then
		return CFrame.identity
	end
	return CFrame.fromAxisAngle(c.Unit, angle)
end

local function inPlane(v: Vector3, n: Vector3): Vector3
	return v - n * v:Dot(n)
end

-- The path from the body at `start` thrown at `velocity`, for at most `duration` seconds.
function GrenadeFlight.path(
	body: Body,
	start: CFrame,
	velocity: Vector3,
	m: Motion,
	params: RaycastParams,
	gravity: number,
	duration: number
): Path
	local M, T = Cfg.Motion, Cfg.Thunk
	local r = body.radius
	local dt = M.step
	local pos, rot = start.Position, start.Rotation
	local v = velocity
	local spin = m.spin
	local first = true
	local rolling = false
	local n = Vector3.yAxis -- the ground it rolls on
	local blendFrom, blendAt = rot, -math.huge
	local times, frames, thunks = {}, {}, {} :: { Thunk }
	local t = 0
	local nextSample = 0

	local function shown(): CFrame
		local a = math.clamp((t - blendAt) / M.blend, 0, 1)
		local look = if a < 1 then blendFrom:Lerp(rot, a * a * (3 - 2 * a)) else rot
		return (look + pos) * body.toPivot
	end
	local function record()
		table.insert(times, t)
		table.insert(frames, shown())
	end
	local function thunk(into: number)
		local share = Rules.thunk(into, T.quiet, T.loud, T.soft)
		if share > 0 then
			table.insert(thunks, { t = t, share = share, at = pos })
		end
	end
	-- its long axis in the world, laid into the ground plane (it lies on its side)
	local function lay()
		local L = rot:VectorToWorldSpace(body.long)
		local flat = inPlane(L, n)
		if flat.Magnitude > 1e-4 then
			rot = turnTo(L, flat.Unit) * rot
		end
	end
	-- lies down on ground `ground` going at `along` (in its plane): long axis across the way it goes
	local function lieDown(ground: Vector3, along: Vector3)
		rolling, n, v = true, ground, along
		blendFrom, blendAt = rot, t
		local L = rot:VectorToWorldSpace(body.long)
		local across = if along.Magnitude > 1e-3 then n:Cross(along.Unit) else inPlane(L, n)
		if across.Magnitude < 1e-4 then
			across = inPlane(Vector3.xAxis, n)
		end
		across = across.Unit
		if across:Dot(L) < 0 then
			across = -across
		end
		rot = turnTo(L, across) * rot
	end

	local function fly()
		v -= Vector3.yAxis * gravity * dt
		local move = v * dt
		for _ = 1, 3 do
			if move.Magnitude < 1e-5 then
				break
			end
			local hit = workspace:Spherecast(pos, r, move, params)
			if not hit then
				pos += move
				break
			end
			local hn = hit.Normal
			local gone = math.max(hit.Distance - M.skin, 0)
			pos += move.Unit * gone
			local left = move.Magnitude - gone
			local into = -v:Dot(hn)
			local along = inPlane(v, hn)
			if into <= 0 then
				-- grazing: slide past it
				move = inPlane(move.Unit * left, hn)
				continue
			end
			local ground = hn.Y >= M.ground
			local out, keep = Rules.hit(
				into,
				along.Magnitude,
				if first then m.first else m.keep,
				m.bounce * (if ground then 1 else M.wall),
				m.settle
			)
			first = false
			thunk(into)
			record()
			spin *= m.spinKeep
			local tangent = if along.Magnitude > 1e-4 then along.Unit * keep else Vector3.zero
			if ground and out == 0 then
				lieDown(hn, tangent)
				return
			end
			v = tangent + hn * out
			move = v * (left / math.max(move.Magnitude, 1e-6)) * dt
		end
		-- end over end along the way it goes (an overarm throw: the top turns forward)
		local axis = v:Cross(Vector3.yAxis) * -1
		if axis.Magnitude > 1e-3 then
			rot = CFrame.fromAxisAngle(axis.Unit, spin * dt) * rot
		end
	end

	-- returns true once at rest
	local function roll(): boolean
		local downhill = inPlane(-Vector3.yAxis, n)
		local slope = downhill.Magnitude
		v += downhill * M.gravity * dt
		-- slides along its long axis (gripping), rolls across it
		local L = rot:VectorToWorldSpace(body.long)
		local axial = v:Dot(L)
		local across = v - L * axial
		axial = math.sign(axial) * Rules.roll(math.abs(axial), m.slide, dt)
		local speed = Rules.roll(across.Magnitude, m.resist, dt)
		across = if across.Magnitude > 1e-6 then across.Unit * speed else Vector3.zero
		v = across + L * axial
		if Rules.rests(v.Magnitude, slope, M.stop, M.grip) then
			v = Vector3.zero
			return true
		end
		-- swept for walls by its upper half (bumps lower than that it rides over: the ground under it is found below)
		local move = v * dt
		local hit = workspace:Spherecast(pos + n * (r / 2), r / 2, move, params)
		if hit and hit.Normal.Y < M.ground then
			local hn = hit.Normal
			pos += move.Unit * math.max(hit.Distance - M.skin, 0)
			-- a wall: knocked back off it
			local into = -v:Dot(hn)
			if into > 0 then
				thunk(into)
				record()
				v += hn * into * (1 + m.bounce * M.wall)
			end
			v = inPlane(v, n)
		else
			pos += move
		end
		-- stays on the ground under it, or off an edge into the air
		local under = workspace:Raycast(pos + n * r, -n * (2 * r + M.probe), params)
		if under and under.Normal.Y >= M.ground then
			n = under.Normal
			pos = under.Position + n * r
			local s = v.Magnitude
			v = inPlane(v, n)
			v = if v.Magnitude > 1e-6 then v.Unit * s else v
		else
			rolling = false
			spin = v.Magnitude / r
			return false
		end
		lay()
		-- turns about its long axis by how far it went across it
		L = rot:VectorToWorldSpace(body.long)
		local turn = v:Dot(L:Cross(n)) * dt / r
		rot = CFrame.fromAxisAngle(L, turn) * rot
		return false
	end

	record()
	nextSample = M.sample
	while t < duration do
		t += dt
		local still = false
		if rolling then
			still = roll()
		else
			fly()
		end
		if still then
			record()
			break
		end
		if t >= nextSample then
			record()
			nextSample = t + M.sample
		end
	end
	if times[#times] ~= t then
		record()
	end
	return { times = times, frames = frames, thunks = thunks, rest = pos }
end

return GrenadeFlight
