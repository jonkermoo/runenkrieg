--!strict
-- The player's Effects setting (src/client/Settings): the screen look per level (Config/Look) on this client only.
-- Adds "Look_Grade" (ColorCorrection, blended day to night by the sun's height: Rules/Grade), "Look_Bloom" and
-- "Look_SunRays" to Lighting and sets the sky light scales. Off puts back the place's own Lighting (its Bloom keeps
-- the magic glowing). The Beautiful setting's cinematic layer (src/client/Cinematic) adds its own effects on top.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Look)
local Grade = require(Shared.Rules.Grade)
local Settings = require(script.Parent.Settings)

local Look = {}

local function make(class: string, name: string): any
	local fx: any = Instance.new(class)
	fx.Name = name
	fx.Enabled = false
	fx.Parent = Lighting
	return fx
end

function Look.start()
	-- the place's own values, put back at Off
	local base = {
		diffuse = Lighting.EnvironmentDiffuseScale,
		specular = Lighting.EnvironmentSpecularScale,
		quality = Lighting.PrioritizeLightingQuality,
	}
	local placeBlooms: { [BloomEffect]: boolean } = {}
	for _, fx in Lighting:GetChildren() do
		if fx:IsA("BloomEffect") then
			placeBlooms[fx] = fx.Enabled
		end
	end

	local grade = make("ColorCorrectionEffect", "Look_Grade") :: ColorCorrectionEffect
	local bloom = make("BloomEffect", "Look_Bloom") :: BloomEffect
	local rays = make("SunRaysEffect", "Look_SunRays") :: SunRaysEffect

	local level: any = nil

	-- the grade and the rays follow the sun
	local function follow()
		if not level then
			return
		end
		local day = Grade.dayShare(Lighting:GetSunDirection().Y, Cfg.NightAt, Cfg.DayAt)
		local t = Grade.mix(level.grade.night, level.grade.day, day)
		grade.Saturation = t.saturation
		grade.Contrast = t.contrast
		grade.Brightness = t.brightness
		grade.TintColor = Color3.fromRGB(t.tint[1], t.tint[2], t.tint[3])
		if level.sunRays then
			rays.Intensity = level.sunRays.intensity * day
		end
	end

	local function apply(v: string)
		level = (Cfg.Levels :: any)[v]
		local on = level ~= nil
		for fx, enabled in placeBlooms do
			fx.Enabled = enabled and not on
		end
		grade.Enabled = on
		bloom.Enabled = on
		rays.Enabled = on and level.sunRays ~= nil
		Lighting.EnvironmentDiffuseScale = if on then level.diffuse else base.diffuse
		Lighting.EnvironmentSpecularScale = if on then level.specular else base.specular
		Lighting.PrioritizeLightingQuality = if on then level.quality else base.quality
		if on then
			bloom.Intensity = level.bloom.intensity
			bloom.Size = level.bloom.size
			bloom.Threshold = level.bloom.threshold
			if level.sunRays then
				rays.Spread = level.sunRays.spread
			end
			follow()
		end
	end

	apply(Settings.get("Effects"))
	Settings.changed("Effects", apply)
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(follow)
	Lighting:GetPropertyChangedSignal("GeographicLatitude"):Connect(follow)
end

return Look
