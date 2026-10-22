--!strict
-- The artillery's effects on every client (Config/Artillery.Fx; src/client/Artillery calls them; docs/VFX.md
-- "Artillery"). User 2026-10-21: "can you give a very visual projectile that comes out of them", "way way WAY more
-- effect when the cannon is fired. give it recoil air effects", "make the howitzer have a cinematic magic charge up",
-- "make the explosions have a staticky effect (charge up, projectile, explosion) kind of like the beam":
-- - shot(gun, origin, dir): on top of the muzzle blast (Vfx.Muzzle) a pressure wave racing out along the bore, a
--   flat ring blown across the ground, a clear air bubble swelling from the muzzle, and a shake for whoever is near
--   (src/client/CameraShake);
-- - shell(gun, origin, velocity, flight): the shell flying its path: the field gun's a hot slug trailing smoke, the
--   howitzer's a blue orb trailing light with static crackling round it;
-- - charge(gun, model, muzzle, crystal): the howitzer's charge-up before the shot: a magic circle opening at the
--   muzzle, energy gathering in it, lightning running from the crystal to the muzzle, static on the crystal, a rising
--   hum; returns a stop called at the shot;
-- - blast(gun, position): the howitzer's static after its explosion: bolts leaping out across the ground and a
--   crackling aura (the shake for whoever is near comes with the explosion, src/client/CameraShake).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local Rules = require(Shared.Rules.Artillery)
local CameraShake = require(script.Parent.CameraShake)
local SoundFx = require(script.Parent.SoundFx)
local Vfx = require(script.Parent.Vfx)

local ArtilleryFx = {}

local F = Cfg.Fx
local SMOKE = "rbxasset://textures/particles/smoke_main.dds" -- Roblox's own smoke texture
local rng = Random.new()

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
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
	CameraShake.kick(origin, F.Shake.shot * k, F.Shake.reach * k)
	-- smoke curling up out of the barrel after the shot, thinning out (user 2026-10-21: "make smoke come out of the
	-- cannons (both)")
	local M = F.Smoke
	local smoke =
		Vfx.Pool.emitter(CFrame.lookAt(origin, origin + d) * CFrame.Angles(-math.pi / 2, 0, 0), Vector3.one * 0.3 * k)
	smoke.Shape = Enum.ParticleEmitterShape.Box
	smoke.Texture = SMOKE
	smoke.EmissionDirection = Enum.NormalId.Top
	smoke.Speed = NumberRange.new(M.speed[1] * k, M.speed[2] * k)
	smoke.Lifetime = NumberRange.new(M.life[1], M.life[2])
	smoke.SpreadAngle = Vector2.new(M.spread, M.spread)
	smoke.Drag = M.drag
	smoke.Acceleration = Vector3.new(M.wind[1], M.rise, M.wind[3])
	smoke.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, M.size[1] * k),
		NumberSequenceKeypoint.new(1, M.size[2] * k),
	})
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, M.thick),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Color = ColorSequence.new(Vfx.Util.color(M.color))
	smoke.LightEmission = 0
	smoke.LightInfluence = 1
	smoke.Brightness = 1
	smoke.Orientation = Enum.ParticleOrientation.FacingCamera
	smoke.Squash = NumberSequence.new(0)
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-20, 20)
	smoke.Rate = M.rate
	smoke.Enabled = true
	local t0 = os.clock()
	Vfx.Driver.add(function(now: number): boolean
		local t = now - t0
		if t >= M.time then
			smoke.Enabled = false
			if t >= M.time + M.life[2] then
				Vfx.Pool.freeEmitter(smoke)
				return false
			end
			return true
		end
		smoke.Rate = M.rate * (1 - t / M.time) ^ 1.5
		return true
	end)
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
	local light = Vfx.Pool.light(origin, rgb(P.color), P.light, P.star and P.star.brightness or 2)
	-- a bright four-point star (user 2026-10-21: "make it a bright 4 point star ... look at some clips from animes"):
	-- the anime sparkle: four long spikes in a cross, wide at the core and tapering to needle points (beams square to the
	-- camera), four faint short ones between them, a soft halo round the white-hot core; it twinkles
	local centre: Attachment? = nil
	local tips: { Attachment } = {}
	local spikes: { Beam } = {}
	local halo: Part? = nil
	if P.star then
		local S = P.star
		centre = Vfx.Pool.att(origin)
		for k = 1, 8 do
			local long = k % 2 == 1
			tips[k] = Vfx.Pool.att(origin)
			spikes[k] = Vfx.Pool.beam(
				centre :: Attachment,
				tips[k],
				rgb(S.color),
				if long then S.width else S.diagWidth,
				0,
				if long then 0 else S.diagFade,
				S.beamBrightness
			)
		end
		halo = Vfx.Pool.part(Enum.PartType.Ball, rgb(S.color), Vector3.one * S.halo, CFrame.new(origin), S.haloFade)
	end
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
			for _, b in spikes do
				Vfx.Pool.freeBeam(b)
			end
			for _, a in tips do
				Vfx.Pool.freeAtt(a)
			end
			if centre then
				Vfx.Pool.freeAtt(centre)
			end
			if halo then
				Vfx.Pool.freePart(halo)
			end
			if light then
				Vfx.Pool.freeLight(light)
			end
			return false
		end
		local p = at(t)
		local ahead = at(t + 0.02)
		core.CFrame = CFrame.lookAt(p, ahead)
		if P.star and centre then
			local S = P.star
			local cam = workspace.CurrentCamera.CFrame
			local twinkle = 1 + S.twinkle * math.sin(t * 19) * math.sin(t * 6.3)
			local turn = math.rad(S.spin * t)
			centre.Position = p
			for k, a in tips do
				local long = k % 2 == 1
				local ang = turn + (k - 1) * math.pi / 4
				local len = (if long then S.long else S.diag) * (if long then twinkle else 2 - twinkle)
				a.Position = p + (cam.RightVector * math.cos(ang) + cam.UpVector * math.sin(ang)) * len
			end
			if halo then
				halo.CFrame = CFrame.new(p)
				halo.Size = Vector3.one * S.halo * twinkle
			end
		end
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
	-- the layered circles (user 2026-10-21: "a similar multi layer circle animation" to the staff's, "the circles are
	-- way way WAY bigger"): stacked out from the muzzle along the bore, each opening in its turn through the charge,
	-- larger the further out, curves orbiting each
	local circles: { any } = {}
	local orbits: { any } = {}
	local opened: { boolean } = {}
	local orb = Vfx.Charge.start(muzzle.Position, time, C.color)
	if crystal then
		Vfx.Aura.play(crystal, time, C.color)
	end
	local hum = SoundFx.loop(C.hum, muzzle.Position)
	SoundFx.play(C.open :: any, muzzle.Position)
	local stopped = false
	local t0 = os.clock()
	local nextBolt, nextArc = 0, 0
	local function frame(layer: any): CFrame
		return muzzle * CFrame.new(0, 0, -layer.ahead)
	end
	Vfx.Driver.add(function(now: number): boolean
		if stopped then
			return false
		end
		local t = now - t0
		local k = math.clamp(t / time, 0, 1)
		for i, layer in C.layers do
			if not opened[i] and t >= layer.at * time then
				opened[i] = true
				circles[i] =
					Vfx.Circle.open(frame(layer), layer.diameter, C.color, layer.appear, layer.assemble == true)
				orbits[i] = Vfx.Orbits.new(layer.orbits, layer.diameter, C.color)
				orbits[i].move(frame(layer))
			end
		end
		hum.set(C.humVolume * (0.3 + 0.7 * k), C.humPitch[1] + (C.humPitch[2] - C.humPitch[1]) * k)
		-- lightning from the crystal along the barrel to the muzzle, quicker as it builds
		if crystal and now >= nextBolt then
			nextBolt = now + C.boltEvery[1] + (C.boltEvery[2] - C.boltEvery[1]) * k
			Vfx.Lightning.bolt(crystal.Position, muzzle.Position, C.boltLife, C.color)
		end
		-- and between the circles' rims, more as it builds
		local last = #circles
		if last >= 2 and now >= nextArc then
			nextArc = now + C.rimEvery[1] + (C.rimEvery[2] - C.rimEvery[1]) * k
			local a = math.random() * 2 * math.pi
			local l0, l1 = C.layers[1], C.layers[last]
			local p0 = frame(l0) * CFrame.new(math.cos(a) * l0.diameter / 2, math.sin(a) * l0.diameter / 2, 0)
			local p1 = frame(l1) * CFrame.new(math.cos(a) * l1.diameter / 2, math.sin(a) * l1.diameter / 2, 0)
			Vfx.Lightning.bolt(p0.Position, p1.Position, C.boltLife, C.color)
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
		-- they crumble outermost first
		for i = #circles, 1, -1 do
			local c, o = circles[i], orbits[i]
			task.delay((#circles - i) * C.closeEach, function()
				c.close()
				o.stop(0.2)
			end)
		end
	end
end

-- the howitzer's static after its blast: bolts leaping out over the ground, a crackling aura (its shake: Vfx/Blast)
function ArtilleryFx.blast(gun: any, position: Vector3)
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
