--!strict
-- Dev teleport menu: a pin button next to the settings gear, opening a list of destinations
-- (Rules/DevTeleports). Only shown when the server marked this player with the DevTools attribute.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.DevTools)
local Map1 = require(Shared.Config.Maps.Map1)
local Palette = require(Shared.Config.Palette)
local Rules = require(Shared.Rules.DevTeleports)
local Net = require(Shared.Net)

local DevTeleportMenu = {}

local UI = Palette.UI
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function style(obj: GuiObject, fill: { number }, radius: number)
	obj.BackgroundColor3 = rgb(fill)
	obj.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = obj
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = UI.stroke
	stroke.Color = rgb(UI.outline)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = obj
end

local function text(obj: TextLabel | TextButton, s: string, size: number)
	obj.Text = s
	obj.Font = Enum.Font.GothamBold
	obj.TextSize = size
	obj.TextColor3 = rgb(UI.text)
end

local function build(player: Player)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DevTeleportMenu"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local pin = Instance.new("TextButton")
	pin.Name = "Pin"
	pin.AnchorPoint = Vector2.new(1, 0)
	pin.Position = UDim2.new(1, -68, 0, 12) -- left of the settings gear
	pin.Size = UDim2.fromOffset(48, 48)
	style(pin, UI.panel, 10)
	text(pin, "📍", 24)
	pin.Parent = gui

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 70)
	panel.Size = UDim2.new(0, 260, 0.7, 0)
	panel.CanvasSize = UDim2.new()
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.ScrollBarThickness = 6
	panel.Visible = false
	style(panel, UI.panel, 12)
	panel.Parent = gui

	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, 10)
	end
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 24)
	title.TextXAlignment = Enum.TextXAlignment.Left
	text(title, "Teleport (dev)", 18)
	title.LayoutOrder = 0
	title.Parent = panel

	for i, dest in Rules.list(Map1, Cfg) do
		local b = Instance.new("TextButton")
		b.Name = dest.id
		b.Size = UDim2.new(1, -8, 0, 44) -- thumb-sized rows
		b.LayoutOrder = i
		style(b, UI.button, 8)
		text(b, dest.name, 15)
		b.Activated:Connect(function()
			Net.event("DevTeleport"):FireServer(dest.id)
			panel.Visible = false
		end)
		b.Parent = panel
	end

	pin.Activated:Connect(function()
		panel.Visible = not panel.Visible
		-- close the settings panel if it is open, so the two never overlap
		local settings = player.PlayerGui:FindFirstChild("SettingsMenu")
		local sp = settings and settings:FindFirstChild("Panel") :: GuiObject?
		if sp and panel.Visible then
			sp.Visible = false
		end
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

function DevTeleportMenu.start()
	local player = Players.LocalPlayer
	local gui: ScreenGui? = nil
	local function refresh()
		local allowed = player:GetAttribute(Cfg.Attribute) == true
		if allowed and not gui then
			gui = build(player)
		elseif not allowed and gui then
			gui:Destroy()
			gui = nil
		end
	end
	player:GetAttributeChangedSignal(Cfg.Attribute):Connect(refresh)
	refresh()
end

return DevTeleportMenu
