--!strict
-- The cinematic layer of the "Beautiful" graphics level (Config/Cinematic, Rules/Cinematic): depth of field focused on
-- what the screen centre looks at, and a vignette. Client only, on while the "Effects" setting is Beautiful, on top of
-- the per-level look (src/client/Look owns the grade, bloom and sun rays). Its own instances only: "Cinematic_DoF" in
-- Lighting and the "Cinematic" ScreenGui; it never edits the Look_* effects, the Atmosphere, the Sky or the time of day.
-- Cinematic.apply(guiParent) / Cinematic.clear(guiParent) also work in edit mode, for stills.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Cinematic)
local R = require(Shared.Rules.Cinematic)

local Cinematic = {}

local GUI = "Cinematic"
local DOF = "Cinematic_DoF"

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- Four edge gradients, dark at the edge and clear inward.
local function vignette(parent: Instance)
	local old = parent:FindFirstChild(GUI)
	if old then
		old:Destroy()
	end
	local v = Cfg.Vignette
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

-- Builds the layer with the focus at `focus` studs (the live loop then moves it).
function Cinematic.apply(guiParent: Instance, focus: number?)
	local dof = Lighting:FindFirstChild(DOF) :: DepthOfFieldEffect?
	if not dof then
		dof = Instance.new("DepthOfFieldEffect")
		dof.Name = DOF
		dof.Parent = Lighting
	end
	assert(dof, "no depth of field")
	local f = focus or Cfg.Focus.maxDistance / 2
	dof.FarIntensity = Cfg.Dof.far
	dof.NearIntensity = 0
	dof.FocusDistance = f
	dof.InFocusRadius = R.radius(f, Cfg.Dof.radius, Cfg.Dof.minRadius, Cfg.Focus.maxRadius)
	vignette(guiParent)
end

function Cinematic.clear(guiParent: Instance)
	local dof = Lighting:FindFirstChild(DOF)
	if dof then
		dof:Destroy()
	end
	local gui = guiParent:FindFirstChild(GUI)
	if gui then
		gui:Destroy()
	end
end

function Cinematic.start()
	local Settings = require(script.Parent.Settings)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local on = false
	local focus = Cfg.Focus.maxDistance / 2
	local function apply(v: string)
		local want = v == "Beautiful"
		if want and not on then
			Cinematic.apply(playerGui, focus)
		elseif not want and on then
			Cinematic.clear(playerGui)
		end
		on = want
	end
	apply(Settings.get("Effects"))
	Settings.changed("Effects", apply)

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
		local cam = workspace.CurrentCamera
		local dof = Lighting:FindFirstChild(DOF) :: DepthOfFieldEffect?
		if not (cam and dof) then
			return
		end
		local character = player.Character
		params.FilterDescendantsInstances = if character then { character, cam } else { cam }
		local maxD = Cfg.Focus.maxDistance
		local hit = workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * maxD, params)
		focus = R.focus(focus, if hit then hit.Distance else maxD, Cfg.Focus.focusRate, step)
		local aiming = character ~= nil and character:GetAttribute("Aiming") == true
		dof.FocusDistance = focus
		dof.InFocusRadius = R.radius(focus, Cfg.Dof.radius, Cfg.Dof.minRadius, Cfg.Focus.maxRadius)
		dof.FarIntensity = Cfg.Dof.far * (if aiming then Cfg.AimFarShare else 1)
	end)
end

return Cinematic
