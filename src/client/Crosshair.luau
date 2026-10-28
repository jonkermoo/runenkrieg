--!strict
-- The third-person crosshair (Config/Camera.Crosshair; user 2026-10-20: "small hollow circle (not dot) that can be
-- disabled in settings"): a thin ring at the screen centre, where the camera looks, with a dark edge so it reads on
-- sky and ground. Only with a weapon out over the shoulder ("CameraMode" "Third" at the hip, or "ThirdAim": the staff
-- aimed over the shoulder, user 2026-10-21; src/client/WeaponCamera): never in first person, aiming down the sights,
-- sprinting or with the settings menu open. The player's "Crosshair" setting turns it off. Fades in and out.
-- Manning a machine gun over the shoulder (src/client/Artillery; user 2026-10-28: "keep the hipfire cross fire in third
-- person manning the turret") it sits where the gun points instead (Crosshair.point).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Camera)
local Palette = require(Shared.Config.Palette)
local W = require(Shared.Config.Weapons)
local Rules = require(Shared.Rules.Camera)
local Held = require(script.Parent.Held)
local Settings = require(script.Parent.Settings)

local Crosshair = {}

-- manning a machine gun, and the screen point it points at (nil: not over its shoulder, no crosshair)
local manning = false
local mgPoint: Vector2? = nil

function Crosshair.point(on: boolean, at: Vector2?)
	manning, mgPoint = on, at
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- a ring `size` pixels across, its line `thickness` thick
local function ring(parent: Instance, size: number, thickness: number, color: Color3, z: number): UIStroke
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundTransparency = 1
	f.ZIndex = z
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local line = Instance.new("UIStroke")
	line.Thickness = thickness
	line.Color = color
	line.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	line.Parent = f
	f.Parent = parent
	return line
end

function Crosshair.start()
	local player = Players.LocalPlayer
	local C = Cfg.Crosshair
	local gui = Instance.new("ScreenGui")
	gui.Name = "Crosshair"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true -- the centre of the whole screen, where the camera looks
	gui.Enabled = false
	-- the dark edge: a wider ring under the light one
	local edge = ring(gui, C.Size, C.Thickness + C.EdgeWidth, rgb(Palette.UI.outline), 1)
	local light = ring(gui, C.Size, C.Thickness, rgb(Palette.UI.crosshair), 2)
	local rings = { edge.Parent :: Frame, light.Parent :: Frame }
	gui.Parent = player:WaitForChild("PlayerGui")

	local shown = 0 -- 0..1, eased
	RunService.RenderStepped:Connect(function(dt)
		local character = player.Character
		local weapon = character and Held.weapon(character)
		local spec = weapon and (W :: any)[weapon.name]
		local mode = character and character:GetAttribute("CameraMode")
		local held = character ~= nil
			and spec ~= nil
			and not Rules.thirdPerson(Cfg.ThirdPersonClasses, spec.class)
			and (mode == "Third" or mode == "ThirdAim")
			and character:GetAttribute("Sprinting") ~= true
		local want = (if manning then mgPoint ~= nil else held)
			and player:GetAttribute("MenuOpen") ~= true
			and Settings.get("Crosshair") == "On"
		local at = if mgPoint then UDim2.fromOffset(mgPoint.X, mgPoint.Y) else UDim2.fromScale(0.5, 0.5)
		for _, f in rings do
			f.Position = at
		end
		shown += ((if want then 1 else 0) - shown) * (1 - math.exp(-C.Fade * dt))
		if not want and shown < C.Hidden then
			shown = 0
		end
		gui.Enabled = shown > 0
		local t = 1 - (1 - C.Transparency) * shown
		light.Transparency = t
		edge.Transparency = 1 - (1 - C.Transparency) * shown * C.EdgeShare
	end)
end

return Crosshair
