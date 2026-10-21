--!strict
-- The artillery's effects on every client (Config/Artillery.Fx; src/client/Artillery calls them; docs/VFX.md
-- "Artillery"). User 2026-10-21: "can you give a very visual projectile that comes out of them", "way way WAY more
-- effect when the cannon is fired. give it recoil air effects", "make the howitzer have a cinematic magic charge up",
-- "make the explosions have a staticky effect (charge up, projectile, explosion) kind of like the beam":
-- - shot(gun, origin, dir): on top of the muzzle blast (Vfx.Muzzle) a pressure wave racing out along the bore, a
--   flat ring blown across the ground, a clear air bubble swelling from the muzzle, and a shake for whoever is near;
-- - shell(gun, origin, velocity, flight): the shell flying its path: the field gun's a hot slug trailing smoke, the
--   howitzer's a blue orb trailing light with static crackling round it;
-- - charge(gun, model, muzzle, crystal): the howitzer's charge-up before the shot: a magic circle opening at the
--   muzzle, energy gathering in it, lightning running from the crystal to the muzzle, static on the crystal, a rising
--   hum; returns a stop called at the shot;
-- - blast(gun, position): the howitzer's static after its explosion: bolts leaping out across the ground and a
--   crackling aura; and a shake for whoever is near (both guns).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local Rules = require(Shared.Rules.Artillery)
local SoundFx = require(script.Parent.SoundFx)
local Vfx = require(script.Parent.Vfx)

local ArtilleryFx = {}

local F = Cfg.Fx
local rng = Random.new()

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- the camera shake: kicks added up, each decaying; applied after the camera has been placed
local kicks: { { at: number, size: number } } = {}
local shaking = false
local function shake(at: Vector3, size: number, reach: number)
	local d = (workspace.CurrentCamera.CFrame.Position - at).Magnitude
	if d >= reach then
		return
	end
	table.insert(kicks, { at = os.clock(), size = size * (1 - d / reach) ^ 2 })
	if shaking then
		return
	end
	shaking = true
	RunService:BindToRenderStep("ArtilleryShake", Enum.RenderPriority.Camera.Value + 5, function()
		local now = os.clock()
		local sx, sy = 0, 0
		for i = #kicks, 1, -1 do
			local k = kicks[i]
			local t = now - k.at
			if t > F.Shake.time then
				table.remove(kicks, i)
			else
				local a = k.size * (1 - t / F.Shake.time) ^ 2
				sx += a * math.sin(t * F.Shake.speed * 1.3)
				sy += a * math.cos(t * F.Shake.speed)
			end
		end
		if #kicks == 0 then
			shaking = false
			RunService:UnbindFromRenderStep("ArtilleryShake")
			return
		end
		local cam = workspace.CurrentCamera
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(sy), math.rad(sx), 0)
	end)
end

-- a quick swelling see-through ball (the air thrown out by the blast)
local function bubble(at: Vector3, size: number, time: number)
	local b = Vfx.Pool.part(
		Enum.PartType.Ball,
		rgb(F.Air.color),
		Vector3.one * 0.5,
		CFrame.new(at),
		F.Air.transparency[1],
		Enum.Material.SmoothPlastic
	)
	local t0 = os.clock()
	Vfx.Driver.add(function(now: number): boolean
		local k = (now - t0) / time
		if k >= 1 then
			Vfx.Pool.freePart(b)
			return false
		end
		local e = 1 - (1 - k) ^ 3
		b.Size = Vector3.one * (0.5 + size * e)
		b.Transparency = F.Air.transparency[1] + (F.Air.transparency[2] - F.Air.transparency[1]) * k
		return true
	end)
end

function ArtilleryFx.shot(gun: any, origin: Vector3, dir: Vector3)
	local k = gun.muzzleScale
	local d = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.zAxis
	local S = F.Shot
	-- the pressure wave racing out along the bore, twice, and a ring blown flat across the ground
	Vfx.Shockwave.play(origin + d * S.ahead * k, d, S.color, S.wave * k)
	task.delay(0.06, function()
		Vfx.Shockwave.play(origin + d * S.ahead * k * 2, d, S.color, S.wave * k * 1.4)
	end)
	local ground = workspace:Raycast(origin, Vector3.new(0, -S.groundReach * k, 0))
	if ground then
		Vfx.Shockwave.play(ground.Position + Vector3.new(0, 0.2, 0), Vector3.yAxis, S.color, S.ground * k)
	end
	bubble(origin + d * S.ahead * k, F.Air.size * k, F.Air.time)
	shake(origin, F.Shake.shot * k, F.Shake.reach * k)
end

-- the shell flying its path for `flight` seconds (the server's own path, the same maths)
function ArtilleryFx.shell(gun: any, origin: Vector3, velocity: Vector3, flight: number)
	local P = gun.shell
	local core =
		Vfx.Pool.part(Enum.PartType.Ball, rgb(P.color), Vector3.one * P.size, CFrame.new(origin), 0, Enum.Material.Neon)
	-- its trail: two attachments across it, a Trail fading behind
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, P.size * 0.4, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -P.size * 0.4, 0)
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime = P.trail
	trail.FaceCamera = true
	trail.LightEmission = if P.magic then 1 else 0.6
	trail.Color = ColorSequence.new(rgb(P.color), rgb(P.tail))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Parent = core
	local light = Vfx.Pool.light(origin, rgb(P.color), P.light, 2)
	local nextArc = 0
	local t0 = os.clock()
	local g = gun.gravity
	local function at(t: number): Vector3
		local x, y, z = Rules.at(t, origin.X, origin.Y, origin.Z, velocity.X, velocity.Y, velocity.Z, g)
		return Vector3.new(x, y, z)
	end
	Vfx.Driver.add(function(now: number): boolean
		local t = now - t0
		if t >= flight then
			trail:Destroy()
			a0:Destroy()
			a1:Destroy()
			Vfx.Pool.freePart(core)
			if light then
				Vfx.Pool.freeLight(light)
			end
			return false
		end
		local p = at(t)
		local ahead = at(t + 0.02)
		core.CFrame = CFrame.lookAt(p, ahead)
		if light then
			(light.Parent :: Attachment).WorldPosition = p
		end
		-- the magic shell crackles: short bolts jumping off it
		if P.magic and now >= nextArc then
			nextArc = now + F.Static.every
			local off = rng:NextUnitVector() * F.Static.reach * P.size
			Vfx.Lightning.bolt(p, p + off, F.Static.life, P.static)
		end
		return true
	end)
end

-- the howitzer's charge-up at `muzzle` (a CFrame looking out of it), from the crystal; returns a stop for the shot
function ArtilleryFx.charge(gun: any, muzzle: CFrame, crystal: BasePart?): () -> ()
	local C = F.Charge
	local time = gun.charge
	local circle = Vfx.Circle.open(muzzle * CFrame.new(0, 0, -C.ahead), C.circle, C.color, C.appear)
	local orb = Vfx.Charge.start(muzzle.Position, time, C.color)
	if crystal then
		Vfx.Aura.play(crystal, time, C.color)
	end
	local hum = SoundFx.loop(C.hum, muzzle.Position)
	SoundFx.play(C.open :: any, muzzle.Position)
	local stopped = false
	local t0 = os.clock()
	local nextBolt = 0
	Vfx.Driver.add(function(now: number): boolean
		if stopped then
			return false
		end
		local k = math.clamp((now - t0) / time, 0, 1)
		hum.set(C.humVolume * (0.3 + 0.7 * k), C.humPitch[1] + (C.humPitch[2] - C.humPitch[1]) * k)
		-- lightning from the crystal along the barrel to the muzzle, quicker as it builds
		if crystal and now >= nextBolt then
			nextBolt = now + C.boltEvery[1] + (C.boltEvery[2] - C.boltEvery[1]) * k
			Vfx.Lightning.bolt(crystal.Position, muzzle.Position, C.boltLife, C.color)
		end
		return true
	end)
	return function()
		if stopped then
			return
		end
		stopped = true
		hum.stop(0.15)
		orb.release()
		circle.close()
	end
end

-- the howitzer's static after its blast: bolts leaping out over the ground, a crackling aura (and, any gun, a shake)
function ArtilleryFx.blast(gun: any, position: Vector3)
	shake(position, F.Shake.blast * math.max(gun.kg, 1) ^ (1 / 3), F.Shake.blastReach * math.max(gun.kg, 1) ^ (1 / 3))
	if not gun.vfx.magic then
		return
	end
	local B = F.Blast
	Vfx.Aura.play(position, B.aura, B.color)
	for _ = 1, B.bolts do
		task.delay(rng:NextNumber(0, B.spread), function()
			local a = rng:NextNumber(0, 2 * math.pi)
			local r = gun.zone * rng:NextNumber(0.5, 1.2)
			local to = position + Vector3.new(math.cos(a) * r, rng:NextNumber(-1, 3), math.sin(a) * r)
			Vfx.Lightning.bolt(position + Vector3.new(0, 1, 0), to, B.life, B.color)
		end)
	end
end

return ArtilleryFx
