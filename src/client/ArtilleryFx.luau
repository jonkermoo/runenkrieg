--!strict
-- The artillery's effects on every client (Config/Artillery.Fx; src/client/Artillery calls them; docs/VFX.md
-- "Artillery"). User 2026-10-21: "can you give a very visual projectile that comes out of them", "way way WAY more
-- effect when the cannon is fired. give it recoil air effects", "make the howitzer have a cinematic magic charge up",
-- "make the explosions have a staticky effect (charge up, projectile, explosion) kind of like the beam":
-- - shot(gun, origin, dir): the muzzle blast in its beats (Vfx.Muzzle: fireball, flash, glint, smoke jet and ring,
--   embers, dust), a pressure wave racing out along the bore, a flat ring blown across the ground, a clear air bubble
--   swelling from the muzzle, a shake for whoever is near (src/client/CameraShake), smoke curling out of the barrel
--   and a bank of it hanging in front, and the sound layers after the report (user 2026-10-26: "improve the cannon
--   firing animations. give it more effect, make it super 'visual' and appealing"); far off only the muzzle's flash;
-- - punch(gun, manning): the gunner's view widening for a moment on the shot;
-- - shell(gun, origin, velocity, flight): the shell flying its path: the field gun's a hot slug trailing smoke that
--   corkscrews off it at first and shedding sparks, the howitzer's a blue orb trailing light with static crackling
--   round it;
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

-- a smoke emitter at `cf` (its top face out), Roblox's smoke lit by the scene; `M` as Fx.Smoke (x the scale `k`)
local function smoke(cf: CFrame, box: Vector3, M: any, k: number): ParticleEmitter
	local e = Vfx.Pool.emitter(cf, box)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.Texture = SMOKE
	e.EmissionDirection = Enum.NormalId.Top
	e.Speed = NumberRange.new(M.speed[1] * k, M.speed[2] * k)
	e.Lifetime = NumberRange.new(M.life[1], M.life[2])
	e.SpreadAngle = Vector2.new(M.spread or 180, M.spread or 180)
	e.Drag = M.drag or 0.6
	e.Acceleration = Vector3.new(M.wind[1], M.rise, M.wind[3])
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, M.size[1] * k),
		NumberSequenceKeypoint.new(1, M.size[2] * k),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.15, M.thick),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Color = ColorSequence.new(Vfx.Util.color(M.color))
	e.LightEmission = 0
	e.LightInfluence = 1
	e.Brightness = 1
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.Squash = NumberSequence.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-20, 20)
	return e
end

-- glowing motes (Roblox's sparkle) of `size` studs out of the box at `cf`, living `life` s, drifting up to `speed`
local function motes(
	cf: CFrame,
	box: Vector3,
	color: Color3,
	size: number,
	life: { number },
	speed: number
): ParticleEmitter
	local e = Vfx.Pool.emitter(cf, box)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	e.Texture = Vfx.Util.SPARKLE
	e.EmissionDirection = Enum.NormalId.Top
	e.Speed = NumberRange.new(0, speed)
	e.Lifetime = NumberRange.new(life[1], life[2])
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 1
	e.Acceleration = Vector3.zero
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, size),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new(0)
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = 3
	e.Orientation = Enum.ParticleOrientation.FacingCamera
	e.Squash = NumberSequence.new(0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(0, 0)
	return e
end

-- an emitter running at `rate` from `from` s for `time` s (thinning out by `thin`, a power; 0 keeps it steady), then
-- freed once its last puffs are gone
local function run(e: ParticleEmitter, rate: number, from: number, time: number, life: number, thin: number)
	local t0 = os.clock()
	e.Rate = 0
	e.Enabled = false
	Vfx.Driver.add(function(now: number): boolean
		local t = now - t0 - from
		if t < 0 then
			return true
		elseif t >= time then
			e.Enabled = false
			if t >= time + life then
				Vfx.Pool.freeEmitter(e)
				return false
			end
			return true
		end
		e.Enabled = true
		e.Rate = rate * (1 - t / time) ^ thin
		return true
	end)
end

-- the gunner's view widening for a moment on the shot (Fx.Punch), while `manning()` holds
function ArtilleryFx.punch(gun: any, manning: () -> boolean)
	local P = F.Punch
	local camera = workspace.CurrentCamera
	local base = gun.camera.fov
	local size = P.fov * math.sqrt(gun.muzzleScale)
	local t0 = os.clock()
	Vfx.Driver.add(function(now: number): boolean
		if not manning() then
			return false
		end
		local a = (now - t0) / P.time
		if a >= 1 then
			camera.FieldOfView = base
			return false
		end
		camera.FieldOfView = base + size * (1 - a) ^ 2
		return true
	end)
end

function ArtilleryFx.shot(gun: any, origin: Vector3, dir: Vector3)
	local k = gun.muzzleScale
	local d = if dir.Magnitude > 1e-6 then dir.Unit else Vector3.zAxis
	local look = if gun.vfx.magic then "Magic" else "Field"
	local near = (workspace.CurrentCamera.CFrame.Position - origin).Magnitude <= F.far
	-- the muzzle's own beats: fireball, flash, glint, jet, smoke ring, embers, dust (Vfx/Muzzle)
	Vfx.Muzzle.play(origin, d, k, look, near)
	CameraShake.kick(origin, F.Shake.shot * k, F.Shake.reach * k)
	-- smoke curling up out of the barrel after the shot, thinning out (user 2026-10-21: "make smoke come out of the
	-- cannons (both)")
	local M = F.Smoke
	local wisp =
		smoke(CFrame.lookAt(origin, origin + d) * CFrame.Angles(-math.pi / 2, 0, 0), Vector3.one * 0.3 * k, M, k)
	run(wisp, M.rate, 0, M.time, M.life[2], 1.5)
	if not near then
		return
	end
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
	-- the smoke bank hanging low in front, and on the magic gun its motes twinkling in it
	local B = F.Bank
	local flat = Vector3.new(d.X, 0, d.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
	local foot = if ground then ground.Position else origin
	local at = CFrame.new(foot + flat * B.ahead * k + Vector3.new(0, k, 0))
	local box = Vector3.new(B.width * k, 1, B.width * k)
	run(smoke(at, box, B, k), B.rate, B.at, B.time, B.life[2], 0)
	if gun.vfx.magic then
		local G = B.sparkle
		run(motes(at, box, Vfx.Util.color(G.color), G.size * k, G.life, 2), G.rate, B.at, B.time * 2, G.life[2], 0)
	end
	-- the sound layers after the report: the recoil's clank, the dirt pattering down, the barrel running home
	for _, layer in F.Sound[look] do
		SoundFx.play(layer.sound :: any, origin, nil, { delay = layer.at })
	end
	SoundFx.play(F.Sound.runout[look] :: any, origin, nil, { delay = gun.recoilTimes[1] + gun.recoilTimes[2] })
end

-- the shells' trails (a Trail across two attachments), kept for the next shell instead of built for each one
type TrailKit = { trail: Trail, a0: Attachment, a1: Attachment }
local trails: { TrailKit } = {}

local function trailOn(core: Part): TrailKit
	local kit = table.remove(trails)
	if not kit then
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.FaceCamera = true
		kit = { trail = trail, a0 = a0, a1 = a1 }
	end
	local k = kit :: TrailKit
	k.a0.Parent, k.a1.Parent, k.trail.Parent = core, core, core
	k.trail:Clear()
	k.trail.Enabled = true
	return k
end

local function trailOff(kit: TrailKit)
	kit.trail.Enabled = false
	kit.trail:Clear()
	kit.trail.Parent, kit.a0.Parent, kit.a1.Parent = nil, nil, nil
	table.insert(trails, kit)
end

-- the shell flying its path for `flight` seconds (the server's own path, the same maths)
function ArtilleryFx.shell(gun: any, origin: Vector3, velocity: Vector3, flight: number)
	local P = gun.shell
	local core =
		Vfx.Pool.part(Enum.PartType.Ball, rgb(P.color), Vector3.one * P.size, CFrame.new(origin), 0, Enum.Material.Neon)
	-- its trail: two attachments across it, a Trail fading behind
	local kit = trailOn(core)
	local trail = kit.trail
	kit.a0.Position = Vector3.new(0, P.size * 0.4, 0)
	kit.a1.Position = Vector3.new(0, -P.size * 0.4, 0)
	trail.Lifetime = P.trail
	trail.LightEmission = if P.magic then 1 else 0.6
	trail.Color = ColorSequence.new(rgb(P.color), rgb(P.tail))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	-- the field shell's smoke corkscrewing off it at first, and the sparks it sheds
	local C = F.Corkscrew
	local screw: ParticleEmitter? = nil
	local sparks: ParticleEmitter? = nil
	if not P.magic then
		local e = smoke(CFrame.new(origin), Vector3.one * 0.2, {
			speed = { 0, 0.5 },
			life = C.life,
			wind = { 0, 0, 0 },
			rise = 0.5,
			size = C.size,
			thick = C.thick,
			color = C.color,
		}, 1)
		e.Rate = C.rate
		e.Enabled = true
		screw = e
		local m = motes(CFrame.new(origin), Vector3.one * 0.2, rgb(P.color), P.size * 0.3, { 0.2, 0.4 }, 6)
		m.Rate = C.sparks
		m.Enabled = true
		sparks = m
	end
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
			trailOff(kit)
			Vfx.Pool.freePart(core)
			for _, e in { screw, sparks } do
				local em = e :: ParticleEmitter
				em.Enabled = false
				task.delay(C.life[2], function()
					Vfx.Pool.freeEmitter(em)
				end)
			end
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
		if screw then
			if t >= C.time then
				screw.Enabled = false
			else
				local turn = t * C.turns * 2 * math.pi
				local around = core.CFrame:VectorToWorldSpace(Vector3.new(math.cos(turn), math.sin(turn), 0))
				local box = screw.Parent :: Part
				box.CFrame = CFrame.new(p + around * C.radius)
			end
		end
		if sparks then
			(sparks.Parent :: Part).CFrame = CFrame.new(p)
		end
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
