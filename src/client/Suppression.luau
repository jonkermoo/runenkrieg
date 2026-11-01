--!strict
-- Suppression on the own soldier (Config/Suppression, Rules/Suppression): enemy bullets passing or landing close
-- (src/client/ShotAudio calls Suppression.shot for every shot heard) and explosions nearby (src/client/Vfx/Blast calls
-- Suppression.blast) build a level that holds, then falls away. While it is up the first-person gun and arms wander
-- (src/client/Sway reads Suppression.wobble) and the camera shakes (here, after the camera is placed, in every view;
-- harder in first person). Every hit also jerks the gun and the first-person view, a startle that shudders out.
-- Your own shots never come here; teammates' are skipped (Rules/Teams). Client only, nothing sent.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Suppression)
local Zone = require(Shared.Config.ZoneMatch)
local Rules = require(Shared.Rules.Suppression)
local ShotRules = require(Shared.Rules.ShotAudio)
local Teams = require(Shared.Rules.Teams)

local Suppression = {}

local level, hitAt, at = 0, -math.huge, os.clock()
local size = 0 -- the eased shake size
local shaking = false
local t = 0
local jolts: { { at: number, pitch: number, yaw: number, roll: number } } = {}

-- the level now (worked forward from the last time it was read)
local function current(): number
	local now = os.clock()
	level = Rules.decay(level, at - hitAt, now - at, Cfg.Hold, Cfg.Fall)
	at = now
	return level
end

local function head(): Vector3?
	local character = Players.LocalPlayer.Character
	local h = character and character:FindFirstChild("Head") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not h or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return h.Position
end

-- smooth noise, about -1..1
local function wander(seed: number, rate: number): number
	return math.noise(t * rate, seed) * 2
end

-- the shake's offsets (degrees) for `amp` per axis: the slow wander plus the tremor
local function shake(amp: { pitch: number, yaw: number, roll: number }, k: number): (number, number, number)
	local function axis(seed: number): number
		return (wander(seed, Cfg.rate) + wander(seed + 31.7, Cfg.tremorRate) * Cfg.tremor) * k
	end
	return axis(2.3) * amp.pitch, axis(6.1) * amp.yaw, axis(11.9) * amp.roll
end

-- the startle jolts' turn now (shares of Jolt's degrees: pitch, yaw, roll)
local function jolt(): (number, number, number)
	local J = Cfg.Jolt
	local now = os.clock()
	local p, y, r = 0, 0, 0
	for i = #jolts, 1, -1 do
		local j = jolts[i]
		local k = Rules.jolt(now - j.at, J.time, J.freq)
		if now - j.at >= J.time then
			table.remove(jolts, i)
		else
			p += j.pitch * k
			y += j.yaw * k
			r += j.roll * k
		end
	end
	return p, y, r
end

local function firstPerson(): boolean
	local character = Players.LocalPlayer.Character
	local h = character and character:FindFirstChild("Head") :: BasePart?
	return h ~= nil and (workspace.CurrentCamera.CFrame.Position - h.Position).Magnitude < Cfg.FirstWithin
end

local function step(dt: number)
	t += dt
	local want = Rules.size(current(), Cfg.grow)
	size += (want - size) * (1 - math.exp(-Cfg.ease * math.min(dt, 0.1)))
	if want <= 0 and size < 1e-3 and #jolts == 0 then
		size = 0
		shaking = false
		RunService:UnbindFromRenderStep("Suppression")
		return
	end
	local first = firstPerson()
	local p, y, r = shake(if first then Cfg.cameraFirst else Cfg.camera, size)
	local jp, jy, jr = jolt() -- (read every frame, so finished jolts clear in any view)
	if first then
		local J = Cfg.Jolt.camera
		p, y, r = p + jp * J, y + jy * J, r + jr * J
	end
	local cam = workspace.CurrentCamera
	cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(p), math.rad(y), math.rad(r))
end

local function add(hit: number)
	if hit <= 0 then
		return
	end
	level = Rules.add(current(), hit, Cfg.Cap)
	hitAt = os.clock()
	-- the startle: mostly up, a random side and roll, by the hit's size
	local k = math.min(hit, Cfg.Cap)
	local up = Cfg.Jolt.up
	table.insert(jolts, {
		at = hitAt,
		pitch = k * (up + (1 - up) * (math.random() * 2 - 1)),
		yaw = k * (math.random() * 2 - 1),
		roll = k * (math.random() * 2 - 1),
	})
	if shaking then
		return
	end
	shaking = true
	RunService:BindToRenderStep("Suppression", Enum.RenderPriority.Camera.Value + 6, step)
end

-- The first-person gun's wander this frame (degrees: pitch, yaw, roll), for src/client/Sway.
function Suppression.wobble(aiming: boolean): (number, number, number)
	if not shaking then
		return 0, 0, 0
	end
	local p, y, r = shake(Cfg.viewmodel, size * (if aiming then Cfg.aim else 1))
	local jp, jy, jr = jolt()
	local J = Cfg.Jolt.viewmodel
	return p + jp * J, y + jy * J, r + jr * J
end

local function point(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

-- `shooter` (someone else) fired from `origin`; `hits`: where each bullet or pellet ended.
function Suppression.shot(shooter: Model, origin: Vector3, hits: { Vector3 })
	local me = Players.LocalPlayer.Character
	if not me or shooter == me then
		return
	end
	if
		Teams.same(
			shooter:GetAttribute("Kit"),
			me:GetAttribute("Kit"),
			workspace:GetAttribute(Zone.FreeForAllAttribute) == true
		)
	then
		return
	end
	local h = head()
	if not h then
		return
	end
	local P, I = Cfg.Pass, Cfg.Impact
	local best = 0
	for _, hit in hits do
		local p = ShotRules.pass(point(origin), point(hit), point(h), P.radius, P.clear)
		local s = Rules.impact((hit - h).Magnitude, I)
		best = math.max(best, s, if p then Rules.pass(p.off, P) else 0)
	end
	add(best)
end

-- An explosion of `kg` of TNT at `pos`.
function Suppression.blast(pos: Vector3, kg: number)
	local h = head()
	if h then
		add(Rules.blast(kg, (pos - h).Magnitude, Cfg.Blast))
	end
end

return Suppression
