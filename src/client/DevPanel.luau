--!strict
-- The look shared by the dev menus (DevTeleportMenu, DevWeaponMenu): a square icon button along the top-right next
-- to the settings gear, opening a scrolling panel of thumb-sized rows. Opening one panel closes the others.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared").Config.Palette)

local DevPanel = {}

local UI = Palette.UI
local PANELS = { "SettingsMenu", "DevTeleportMenu", "DevWeaponMenu" } -- ScreenGuis whose "Panel" is closed on open

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

function DevPanel.style(obj: GuiObject, fill: { number }, radius: number)
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

function DevPanel.text(obj: TextLabel | TextButton, s: string, size: number)
	obj.Text = s
	obj.Font = Enum.Font.GothamBold
	obj.TextSize = size
	obj.TextColor3 = rgb(UI.text)
end

export type Panel = { gui: ScreenGui, panel: ScrollingFrame, title: TextLabel }

-- `slot`: position along the top bar counting left from the settings gear (1 = right next to it).
function DevPanel.new(player: Player, name: string, icon: string, slot: number, title: string): Panel
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local pin = Instance.new("TextButton")
	pin.Name = "Pin"
	pin.AnchorPoint = Vector2.new(1, 0)
	pin.Position = UDim2.new(1, -12 - 56 * slot, 0, 12)
	pin.Size = UDim2.fromOffset(48, 48)
	DevPanel.style(pin, UI.panel, 10)
	DevPanel.text(pin, icon, 24)
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
	DevPanel.style(panel, UI.panel, 12)
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

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 24)
	label.TextXAlignment = Enum.TextXAlignment.Left
	DevPanel.text(label, title, 18)
	label.LayoutOrder = 0
	label.Parent = panel

	pin.Activated:Connect(function()
		panel.Visible = not panel.Visible
		if panel.Visible then
			-- close the other panels, so they never overlap
			for _, other in PANELS do
				local g = other ~= name and player.PlayerGui:FindFirstChild(other)
				local p = g and g:FindFirstChild("Panel") :: GuiObject?
				if p then
					p.Visible = false
				end
			end
		end
	end)
	gui.Parent = player:WaitForChild("PlayerGui")
	return { gui = gui, panel = panel, title = label }
end

-- A row button in a panel.
function DevPanel.button(panel: ScrollingFrame, id: string, label: string, order: number, fill: { number }?): TextButton
	local b = Instance.new("TextButton")
	b.Name = id
	b.Size = UDim2.new(1, -8, 0, 44) -- thumb-sized rows
	b.LayoutOrder = order
	DevPanel.style(b, fill or UI.button, 8)
	DevPanel.text(b, label, 15)
	b.Parent = panel
	return b
end

return DevPanel
