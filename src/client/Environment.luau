--!strict
-- Draws the time of day and the weather the server keeps (src/server/Environment's Workspace attributes,
-- Config/Environment, Rules/Environment) on this client: Lighting's clock, light and ambient, the map's Atmosphere
-- thickening for fog and rain and darkening at night, the clouds, darker (wet) terrain in the rain, and the rain itself:
-- one emitter over the camera (local, under the camera; the drops stop under a roof) and a looping rain sound.
-- Every client reads the same attributes and the server time, so all players see the same sky. Lighting writes here
-- are local; the post-processing (Bloom, ColorCorrection) and the graphics presets belong to other modules.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Environment)
local Rules = require(Shared.Rules.Environment)
local Audio = require(script.Parent.Audio)

local A = Cfg.Attributes
local R = Cfg.Rain

local Environment = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(math.clamp(c[1], 0, 255), math.clamp(c[2], 0, 255), math.clamp(c[3], 0, 255))
end

local function triple(c: Color3): { number }
	return { c.R * 255, c.G * 255, c.B * 255 }
end

local function num(name: string, default: number): number
	local v = workspace:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

-- the terrain's own colors (the map builder's), darkened together in the rain
local function terrainColors(): { [Enum.Material]: Color3 }
	local out = {}
	for _, m in Enum.Material:GetEnumItems() do
		local ok, c = pcall(function()
			return workspace.Terrain:GetMaterialColor(m)
		end)
		if ok and c then
			out[m] = c
		end
	end
	return out
end

local function rainPart(): (BasePart, ParticleEmitter)
	local p = Instance.new("Part")
	p.Name = "Rain"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(R.area, 1, R.area)
	local e = Instance.new("ParticleEmitter")
	e.Texture = R.texture
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Speed = NumberRange.new(R.speed)
	e.Lifetime = NumberRange.new(R.lifetime)
	e.Size = NumberSequence.new(R.size)
	e.Squash = NumberSequence.new(R.length)
	e.Transparency = NumberSequence.new(R.transparency)
	e.Color = ColorSequence.new(rgb(R.color))
	e.LightInfluence = R.light
	e.LightEmission = 0
	e.Rate = 0
	e.Parent = p
	p.Parent = workspace.CurrentCamera
	return p, e
end

local function rainSound(): (Sound, EqualizerSoundEffect)
	local s = Instance.new("Sound")
	s.Name = "Rain"
	s.SoundId = `rbxassetid://{R.sound.id}`
	s.Looped = true
	s.Volume = 0
	s.SoundGroup = Audio.effects()
	local eq = Instance.new("EqualizerSoundEffect")
	eq.LowGain, eq.MidGain, eq.HighGain = 0, 0, 0
	eq.Parent = s
	s.Parent = SoundService
	return s, eq
end

function Environment.start()
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	local atmosphere = atm :: Atmosphere
	local base: Rules.Haze = {
		density = atmosphere.Density,
		haze = atmosphere.Haze,
		color = triple(atmosphere.Color),
		decay = triple(atmosphere.Decay),
	}
	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if not clouds then
		clouds = Instance.new("Clouds")
		clouds.Parent = workspace.Terrain
	end
	local cloud = clouds :: Clouds
	cloud.Density = Cfg.Weather.clouds.density
	local colors = terrainColors()
	local wetNow = 1

	local part, emitter = rainPart()
	local sound, eq = rainSound()
	local rain, covered = 0, false
	local cast = RaycastParams.new()
	cast.FilterType = Enum.RaycastFilterType.Exclude

	local function look()
		local t = workspace:GetServerTimeNow()
		local clock = Rules.clockAt(t - num(A.dayStart, t), Cfg.Day)
		local kind = workspace:GetAttribute(A.weather)
		local w = Rules.strength(t, num(A.from, 0), num(A.to, 0), Cfg.Weather.fade)
		local l =
			Rules.look(Rules.daylight(clock, Cfg.Day), if typeof(kind) == "string" then kind else "Clear", w, base, Cfg)
		Lighting.ClockTime = clock
		Lighting.Brightness = l.brightness
		Lighting.Ambient = rgb(l.ambient)
		Lighting.OutdoorAmbient = rgb(l.outdoorAmbient)
		Lighting.ExposureCompensation = l.exposure
		atmosphere.Density = l.density
		atmosphere.Haze = l.haze
		atmosphere.Color = rgb(l.color)
		atmosphere.Decay = rgb(l.decay)
		cloud.Cover = l.cloudCover
		cloud.Color = rgb(l.cloudColor)
		if math.abs(l.wet - wetNow) > 0.005 then
			wetNow = l.wet
			for m, c in colors do
				workspace.Terrain:SetMaterialColor(m, Color3.new(c.R * wetNow, c.G * wetNow, c.B * wetNow))
			end
		end
		rain = l.rain
	end

	local last, lastRoof = 0, 0
	RunService:BindToRenderStep("EnvironmentRain", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now - last >= 1 / Cfg.UpdateHz then
			last = now
			look()
		end
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		if part.Parent ~= cam then
			part.Parent = cam
		end
		local eye = cam.CFrame.Position
		if rain > 0 and now - lastRoof >= 0.25 then
			lastRoof = now
			local char = Players.LocalPlayer.Character
			cast.FilterDescendantsInstances = if char then { char, cam } else { cam }
			covered = workspace:Raycast(eye, Vector3.new(0, R.roof, 0), cast) ~= nil
		end

		-- the area sits over where the camera is heading; tilted so the drops slant downwind
		local subject = cam.CameraSubject
		local vel = if subject
				and subject:IsA("Humanoid")
				and subject.RootPart
			then subject.RootPart.AssemblyLinearVelocity
			else Vector3.zero
		local wind = workspace.GlobalWind * R.wind
		local fall = (Vector3.new(0, -R.speed, 0) + wind).Unit
		local at = eye + Vector3.new(vel.X, 0, vel.Z) * R.lead - fall * R.height
		part.CFrame = CFrame.lookAt(at, at + fall:Cross(Vector3.xAxis).Unit, -fall) -- (its -Y, the Bottom face, falls)
		emitter.Rate = if covered then 0 else R.rate * rain

		local vol = R.sound.volume * rain * (if covered then R.sound.covered else 1)
		sound.Volume = vol
		eq.HighGain = if covered then R.sound.coveredHigh else 0
		if vol > 0 and not sound.IsPlaying then
			sound:Play()
		elseif vol <= 0 and sound.IsPlaying then
			sound:Stop()
		end
	end)
end

return Environment
