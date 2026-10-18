--!strict
-- Settings menu: a gear button (top right) or the Settings key (Key_Settings) opens a centred panel with tabs
-- (Config/Settings.Tabs): segmented rows for choices, sliders for numbers, a press-a-key button per keybind, and the
-- graphics preset row (Config/Settings.Presets; "Custom" when the four don't match one). While open the Player's
-- "MenuOpen" attribute frees the mouse (src/client/WeaponCamera); a click outside the panel closes it.
-- Flat palette colors with one uniform outline thickness (docs/ART_STYLE.md).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Settings)
local Palette = require(Shared.Config.Palette)
local R = require(Shared.Rules.Settings)
local Settings = require(script.Parent.Settings)

local SettingsMenu = {}

local UI = Palette.UI
local M = Cfg.Menu
local O = Cfg.Options :: any

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

local function label(parent: Instance, s: string, size: number, align: Enum.TextXAlignment): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.TextXAlignment = align
	text(l, s, size)
	l.Parent = parent
	return l
end

local function button(parent: Instance, s: string, size: number): TextButton
	local b = Instance.new("TextButton")
	style(b, UI.button, 8)
	text(b, s, size)
	b.AutoButtonColor = false
	b.Parent = parent
	return b
end

-- a key or mouse button as shown
local MOUSE = { MouseButton1 = "Left mouse", MouseButton2 = "Right mouse", MouseButton3 = "Middle mouse" }
local function keyName(name: string): string
	return MOUSE[name] or name
end

-- a row: its name on top, the control below
local function row(parent: Instance, order: number, name: string): Frame
	local r = Instance.new("Frame")
	r.BackgroundTransparency = 1
	r.Size = UDim2.new(1, 0, 0, M.RowHeight)
	r.LayoutOrder = order
	r.Parent = parent
	local n = label(r, name, M.LabelSize, Enum.TextXAlignment.Left)
	n.Name = "Name"
	n.Size = UDim2.new(1, 0, 0, M.LabelHeight)
	return r
end

local function control(r: Frame): Frame
	local c = Instance.new("Frame")
	c.Name = "Control"
	c.BackgroundTransparency = 1
	c.Position = UDim2.fromOffset(0, M.LabelHeight + M.Gap)
	c.Size = UDim2.new(1, 0, 0, M.ControlHeight)
	c.Parent = r
	return c
end

-- one button per value; `current()` says which is lit, `pick(v)` sets it
local function segmented(c: Frame, values: { string }, pick: (string) -> ()): (string) -> ()
	local h = Instance.new("UIListLayout")
	h.FillDirection = Enum.FillDirection.Horizontal
	h.Padding = UDim.new(0, M.Gap)
	h.SortOrder = Enum.SortOrder.LayoutOrder
	h.Parent = c
	local buttons: { [string]: TextButton } = {}
	local n = #values
	for i, v in values do
		local b = button(c, v, M.ValueSize)
		b.LayoutOrder = i
		b.Size = UDim2.new(1 / n, -M.Gap * (n - 1) / n, 1, 0)
		b.Activated:Connect(function()
			pick(v)
		end)
		buttons[v] = b
	end
	return function(current: string)
		for v, b in buttons do
			b.BackgroundColor3 = rgb(if v == current then UI.accent else UI.button)
		end
	end
end

local function choiceRow(parent: Instance, order: number, key: string)
	local opt = O[key]
	local refresh = segmented(control(row(parent, order, opt.label)), opt.values, function(v)
		Settings.set(key, v)
	end)
	refresh(Settings.get(key))
	Settings.changed(key, refresh)
end

local function presetRow(parent: Instance, order: number)
	local r = row(parent, order, Cfg.PresetLabel)
	local name = r:FindFirstChild("Name") :: TextLabel
	local refresh = segmented(control(r), Cfg.PresetOrder, function(p)
		for key, v in Cfg.Presets[p] do
			Settings.set(key, v)
		end
	end)
	local function update()
		local p = R.preset(Cfg.Presets, Cfg.PresetOrder, Settings.get)
		refresh(p)
		name.Text = if p == "Custom" then `{Cfg.PresetLabel}: Custom` else Cfg.PresetLabel
	end
	update()
	for key in Cfg.Presets[Cfg.PresetOrder[1]] do
		Settings.changed(key, update)
	end
end

local function sliderRow(parent: Instance, order: number, key: string)
	local opt = O[key]
	local r = row(parent, order, opt.label)
	local value = label(r, "", M.LabelSize, Enum.TextXAlignment.Right)
	value.Size = UDim2.new(1, 0, 0, M.LabelHeight)
	local c = control(r)
	local track = Instance.new("TextButton") -- (a button: it sinks the click, so the gun doesn't fire)
	track.Text = ""
	track.AutoButtonColor = false
	track.AnchorPoint = Vector2.new(0, 0.5)
	track.Position = UDim2.new(0, M.KnobSize / 2, 0.5, 0)
	track.Size = UDim2.new(1, -M.KnobSize, 0, M.TrackHeight)
	style(track, UI.slot, M.TrackHeight / 2)
	track.Parent = c
	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = rgb(UI.accent)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, M.TrackHeight / 2)
	fc.Parent = fill
	fill.Parent = track
	local knob = Instance.new("Frame")
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(M.KnobSize, M.KnobSize)
	style(knob, UI.text, M.KnobSize / 2)
	knob.Parent = track

	local function refresh(v: number)
		local share = R.share(opt, v)
		fill.Size = UDim2.fromScale(share, 1)
		knob.Position = UDim2.fromScale(share, 0.5)
		value.Text = R.format(opt, v)
	end
	refresh(Settings.get(key))
	Settings.changed(key, refresh)

	local dragging: InputObject? = nil
	local function at(x: number)
		local share = (x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1)
		Settings.set(key, R.fromShare(opt, share))
	end
	track.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = input
			at(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or (input.UserInputType == Enum.UserInputType.Touch and input == dragging)
			)
		then
			at(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if
			dragging
			and (
				input == dragging
				or input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			dragging = nil
		end
	end)
end

-- the keybind being captured (its option key), if any: the next key or mouse button press binds it; and when the
-- last one was bound (the click that binds the left mouse button also releases on its button)
local capturing: string? = nil
local boundAt = -math.huge

local function keyRow(parent: Instance, order: number, key: string, onCapture: (string?) -> ())
	local opt = O[key]
	local b = button(control(row(parent, order, opt.label)), "", M.ValueSize)
	b.Size = UDim2.fromScale(1, 1)
	local function refresh()
		b.Text = if capturing == key then "Press a key (Esc cancels)" else keyName(Settings.get(key))
		b.BackgroundColor3 = rgb(if capturing == key then UI.accent else UI.button)
	end
	refresh()
	Settings.changed(key, refresh)
	b.Activated:Connect(function()
		if os.clock() - boundAt > M.CaptureGuard then
			onCapture(if capturing == key then nil else key)
		end
	end)
	return refresh
end

function SettingsMenu.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = M.DisplayOrder

	local gear = Instance.new("TextButton")
	gear.Name = "Gear"
	gear.AnchorPoint = Vector2.new(1, 0)
	gear.Position = UDim2.new(1, -12, 0, 12)
	gear.Size = UDim2.fromOffset(48, 48) -- thumb-sized
	style(gear, UI.panel, 10)
	text(gear, "⚙", 26)
	gear.Parent = gui

	-- behind the panel: a click outside it closes the menu (and never reaches the game)
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BackgroundTransparency = 1
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Visible = false
	backdrop.Parent = gui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(M.Width, M.Height)
	panel.Visible = false
	style(panel, UI.panel, 12)
	panel.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function rescale()
		-- one scale for the reference height, never taller than the screen
		local h = gui.AbsoluteSize.Y
		scale.Scale = math.min(math.clamp(h / M.ReferenceHeight, M.MinScale, M.MaxScale), (h - M.Margin) / M.Height)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)

	local pad = Instance.new("UIPadding")
	for _, side in { "PaddingTop", "PaddingBottom", "PaddingLeft", "PaddingRight" } do
		(pad :: any)[side] = UDim.new(0, M.Padding)
	end
	pad.Parent = panel

	local title = label(panel, "Settings", M.TitleSize, Enum.TextXAlignment.Left)
	title.Size = UDim2.new(1, -M.ControlHeight, 0, M.ControlHeight)
	local close = button(panel, "X", M.ValueSize)
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(M.ControlHeight, M.ControlHeight)

	-- the tab bar, and one scrolling page per tab
	local bar = Instance.new("Frame")
	bar.Name = "Tabs"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromOffset(0, M.ControlHeight + M.Gap * 2)
	bar.Size = UDim2.new(1, 0, 0, M.ControlHeight)
	bar.Parent = panel
	local top = M.ControlHeight * 2 + M.Gap * 4
	local pages: { [string]: ScrollingFrame } = {}
	local names = {}
	for _, tab in Cfg.Tabs do
		table.insert(names, tab.name)
	end

	local refreshKeys: { () -> () } = {}
	local function capture(key: string?)
		capturing = key
		for _, f in refreshKeys do
			f()
		end
	end

	local openTab: (string) -> ()
	local showTab = segmented(bar, names, function(name)
		openTab(name)
	end)
	for i, tab in Cfg.Tabs do
		local page = Instance.new("ScrollingFrame")
		page.Name = tab.name
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.Position = UDim2.fromOffset(0, top)
		page.Size = UDim2.new(1, 0, 1, -top)
		page.CanvasSize = UDim2.new()
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.ScrollingDirection = Enum.ScrollingDirection.Y
		page.ScrollBarThickness = M.ScrollBar
		page.ScrollBarImageColor3 = rgb(UI.button)
		page.Visible = i == 1
		page.Parent = panel
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, M.RowGap)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = page
		local inner = Instance.new("UIPadding")
		inner.PaddingRight = UDim.new(0, M.ScrollBar + M.Gap)
		inner.Parent = page
		for order, key in tab.rows do
			if key == "Preset" then
				presetRow(page, order)
			elseif O[key].kind == "choice" then
				choiceRow(page, order, key)
			elseif O[key].kind == "slider" then
				sliderRow(page, order, key)
			else
				table.insert(refreshKeys, keyRow(page, order, key, capture))
			end
		end
		pages[tab.name] = page
	end
	function openTab(name: string)
		for n, page in pages do
			page.Visible = n == name
		end
		showTab(name)
		capture(nil)
	end
	openTab(names[1])

	local function setOpen(open: boolean)
		panel.Visible, backdrop.Visible = open, open
		player:SetAttribute("MenuOpen", open)
		capture(nil)
		if open then
			rescale()
			local tp = player.PlayerGui:FindFirstChild("DevTeleportMenu")
			local tpPanel = tp and tp:FindFirstChild("Panel") :: GuiObject?
			if tpPanel then
				tpPanel.Visible = false
			end
		end
	end
	gear.Activated:Connect(function()
		setOpen(not panel.Visible)
	end)
	close.Activated:Connect(function()
		setOpen(false)
	end)
	backdrop.Activated:Connect(function()
		setOpen(false)
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		local t = input.UserInputType
		if capturing then
			local name: string? = nil
			if t == Enum.UserInputType.Keyboard then
				if input.KeyCode == Enum.KeyCode.Escape then
					capture(nil)
					return
				end
				name = input.KeyCode.Name
			elseif MOUSE[t.Name] then
				name = t.Name
			end
			if name and name ~= "Unknown" then
				local action = capturing :: string
				boundAt = os.clock()
				capture(nil)
				for k, v in R.rebind(O, Settings.get, action, name :: string) do
					Settings.set(k, v)
				end
			end
			return
		end
		if not processed and Settings.pressed("Key_Settings", input) then
			setOpen(not panel.Visible)
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	rescale()
end

return SettingsMenu
