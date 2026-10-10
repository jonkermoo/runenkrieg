--!strict
-- Settings menu: a gear button (top right) toggling a panel with one segmented row per option.
-- Flat palette colors with one uniform outline thickness (docs/ART_STYLE.md).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Settings)
local Palette = require(Shared.Config.Palette)
local Settings = require(script.Parent.Settings)

local SettingsMenu = {}

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

function SettingsMenu.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local gear = Instance.new("TextButton")
	gear.Name = "Gear"
	gear.AnchorPoint = Vector2.new(1, 0)
	gear.Position = UDim2.new(1, -12, 0, 12)
	gear.Size = UDim2.fromOffset(48, 48) -- thumb-sized
	style(gear, UI.panel, 10)
	text(gear, "⚙", 26)
	gear.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -12, 0, 70)
	panel.Size = UDim2.fromOffset(340, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.Visible = false
	style(panel, UI.panel, 12)
	panel.Parent = gui

	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, 14)
	end
	pad.Parent = panel
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Left
	text(title, "Settings", 20)
	title.LayoutOrder = 0
	title.Parent = panel

	for order, key in Cfg.Order do
		local opt = Cfg.Options[key]
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 72)
		row.LayoutOrder = order
		row.Parent = panel

		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Size = UDim2.new(1, 0, 0, 22)
		name.TextXAlignment = Enum.TextXAlignment.Left
		text(name, opt.label, 16)
		name.Parent = row

		local seg = Instance.new("Frame")
		seg.BackgroundTransparency = 1
		seg.Position = UDim2.fromOffset(0, 28)
		seg.Size = UDim2.new(1, 0, 0, 44)
		seg.Parent = row
		local h = Instance.new("UIListLayout")
		h.FillDirection = Enum.FillDirection.Horizontal
		h.Padding = UDim.new(0, 6)
		h.Parent = seg

		local buttons: { [string]: TextButton } = {}
		local n = #opt.values
		local function refresh(current: string)
			for v, b in buttons do
				b.BackgroundColor3 = rgb(if v == current then UI.accent else UI.button)
			end
		end
		for _, v in opt.values do
			local b = Instance.new("TextButton")
			b.Size = UDim2.new(1 / n, -6 * (n - 1) / n, 1, 0)
			style(b, UI.button, 8)
			text(b, v, 15)
			b.AutoButtonColor = false
			b.Activated:Connect(function()
				Settings.set(key, v)
			end)
			b.Parent = seg
			buttons[v] = b
		end
		refresh(Settings.get(key))
		Settings.changed(key, refresh)
	end

	gear.Activated:Connect(function()
		panel.Visible = not panel.Visible
		local tp = Players.LocalPlayer.PlayerGui:FindFirstChild("DevTeleportMenu")
		local tpPanel = tp and tp:FindFirstChild("Panel") :: GuiObject?
		if tpPanel and panel.Visible then
			tpPanel.Visible = false
		end
	end)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return SettingsMenu
