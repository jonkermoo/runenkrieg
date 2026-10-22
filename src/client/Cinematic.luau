--!strict
-- The cinematic layer of the "Beautiful" graphics level (Config/Cinematic, Rules/Cinematic): a film grade that follows
-- the sun from day to night, depth of field focused on what the screen centre looks at, sun rays and a vignette.
-- Client only. Its own instances ("Cinematic_*" in Lighting, the "Cinematic" ScreenGui); it never edits the per-level
-- effects (src/client/Look), the Atmosphere, the Sky or the time of day.
-- On while the "Effects" setting is Beautiful (before that option exists: while the graphics preset is Beautiful).
-- Dev: the local Player's "CinematicLook" attribute picks another of Config/Cinematic.Looks.
-- Cinematic.apply(name, guiParent) / Cinematic.clear(guiParent) also work in edit mode, for stills.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Cinematic)
local R = require(Shared.Rules.Cinematic)

local Cinematic = {}

local GUI = "Cinematic"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function effect<T>(class: string, name: string): T
	local inst = Lighting:FindFirstChild(name)
	if not (inst and inst:IsA(class)) then
		if inst then
			inst:Destroy()
		end
		inst = Instance.new(class)
		inst.Name = name
		inst.Parent = Lighting
	end
	return inst :: any
end

local function setGrade(cc: ColorCorrectionEffect, g: R.Grade)
	cc.TintColor = rgb(g.tint)
	cc.Brightness = g.brightness
	cc.Contrast = g.contrast
	cc.Saturation = g.saturation
end

-- Four edge gradients, dark at the edge and clear inward.
local function vignette(look: any, parent: Instance)
	local old = parent:FindFirstChild(GUI)
	if old then
		old:Destroy()
	end
	local v = look.vignette
	local gui = Instance.new("ScreenGui")
	gui.Name = GUI
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = Cfg.VignetteOrder
	local edges = {
		{ UDim2.fromScale(1, v.size), UDim2.fromScale(0, 0), Vector2.zero, 90, Enum.SizeConstraint.RelativeXY },
		{ UDim2.fromScale(1, v.size), UDim2.fromScale(0, 1), Vector2.new(0, 1), 270, Enum.SizeConstraint.RelativeXY },
		{ UDim2.fromScale(v.size, 1), UDim2.fromScale(0, 0), Vector2.zero, 0, Enum.SizeConstraint.RelativeYY },
		{ UDim2.fromScale(v.size, 1), UDim2.fromScale(1, 0), Vector2.new(1, 0), 180, Enum.SizeConstraint.RelativeYY },
	}
	for _, e in edges do
		local f = Instance.new("Frame")
		f.Size, f.Position, f.AnchorPoint = e[1], e[2], e[3]
		f.SizeConstraint = e[5]
		f.BackgroundColor3 = rgb(v.color)
		f.BackgroundTransparency = 0
		f.BorderSizePixel = 0
		f.Active = false
		local g = Instance.new("UIGradient")
		g.Rotation = e[4]
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, v.transparency),
			NumberSequenceKeypoint.new(0.45, v.transparency + (1 - v.transparency) * 0.75),
			NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		f.Parent = gui
	end
	gui.Parent = parent
end

-- Builds a look as it stands by day with the focus at `focus` studs (the live loop then moves it).
function Cinematic.apply(name: string, guiParent: Instance, focus: number?)
	local look = (Cfg.Looks :: any)[name]
	assert(look, `no cinematic look {name}`)
	setGrade(effect("ColorCorrectionEffect", "Cinematic_Grade"), look.day)
	local dof = effect("DepthOfFieldEffect", "Cinematic_DoF") :: DepthOfFieldEffect
	local f = focus or Cfg.Focus.maxDistance / 2
	dof.FarIntensity = look.dof.far
	dof.NearIntensity = 0
	dof.FocusDistance = f
	dof.InFocusRadius = R.radius(f, look.dof.radius, look.dof.minRadius, Cfg.Focus.maxRadius)
	local rays = effect("SunRaysEffect", "Cinematic_SunRays") :: SunRaysEffect
	rays.Intensity = look.sunRays.intensity
	rays.Spread = look.sunRays.spread
	vignette(look, guiParent)
end

function Cinematic.clear(guiParent: Instance)
	for _, n in { "Cinematic_Grade", "Cinematic_DoF", "Cinematic_SunRays" } do
		local inst = Lighting:FindFirstChild(n)
		if inst then
			inst:Destroy()
		end
	end
	local gui = guiParent:FindFirstChild(GUI)
	if gui then
		gui:Destroy()
	end
end

function Cinematic.start()
	local Settings = require(script.Parent.Settings) :: any
	local SetCfg = require(Shared.Config.Settings) :: any
	local SetRules = require(Shared.Rules.Settings)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- the "Effects" option once it exists, else the graphics preset
	local function wanted(): boolean
		if SetCfg.Options.Effects then
			return Settings.get("Effects") == "Beautiful"
		end
		return SetRules.preset(SetCfg.Presets, SetCfg.PresetOrder, Settings.get) == "Beautiful"
	end
	local function lookName(): string
		local dev = player:GetAttribute("CinematicLook")
		return if typeof(dev) == "string" and (Cfg.Looks :: any)[dev] then dev else Cfg.Look
	end

	local on, name = false, ""
	local focus = Cfg.Focus.maxDistance / 2
	local function refresh()
		local want = wanted()
		if want and (not on or name ~= lookName()) then
			name = lookName()
			Cinematic.apply(name, playerGui, focus)
		elseif not want and on then
			Cinematic.clear(playerGui)
		end
		on = want
	end
	refresh()
	for key in SetCfg.Options do
		Settings.changed(key, refresh)
	end
	player:GetAttributeChangedSignal("CinematicLook"):Connect(refresh)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if not on or acc < 1 / Cfg.Focus.updateHz then
			return
		end
		local step = acc
		acc = 0
		local look = (Cfg.Looks :: any)[name]
		local cam = workspace.CurrentCamera
		local grade = Lighting:FindFirstChild("Cinematic_Grade") :: ColorCorrectionEffect?
		local dof = Lighting:FindFirstChild("Cinematic_DoF") :: DepthOfFieldEffect?
		if not (look and cam and grade and dof) then
			return
		end

		local t = R.daylight(Lighting:GetSunDirection().Y, Cfg.DayAbove, Cfg.NightBelow)
		setGrade(grade, R.grade(look.day, look.night, t))

		local character = player.Character
		params.FilterDescendantsInstances = if character then { character, cam } else { cam }
		local maxD = Cfg.Focus.maxDistance
		local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * maxD, params)
		focus = R.focus(focus, if hit then hit.Distance else maxD, Cfg.Focus.focusRate, step)
		local aiming = character ~= nil and character:GetAttribute("Aiming") == true
		dof.FocusDistance = focus
		dof.InFocusRadius = R.radius(focus, look.dof.radius, look.dof.minRadius, Cfg.Focus.maxRadius)
		dof.FarIntensity = look.dof.far * (if aiming then Cfg.AimFarShare else 1)
	end)
end

return Cinematic
