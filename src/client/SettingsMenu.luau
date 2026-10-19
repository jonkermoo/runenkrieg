--!strict
-- Settings menu: a gear button (top right) or the Settings key (Key_Settings) opens a centred panel with tabs
-- (Config/Settings.Tabs): segmented rows for choices, sliders for numbers, a press-a-key button per keybind, and the
-- graphics preset row (Config/Settings.Presets; "Custom" when the four don't match one). While open the Player's
-- "MenuOpen" attribute frees the mouse (src/client/WeaponCamera); a click outside the panel closes it.
-- Layout, sizes and fonts come from the spec src/shared/ui/SettingsMenu.json (local layout check and preview scripts
-- read the same file); a row is built from the spec's template for its option's kind, so a new option
-- only needs its Config/Settings entry and a place in a tab. Look: gray slate, thin lines, square-turned knobs
-- (Config/Palette UI.Settings; docs/ART_STYLE.md). No CanvasGroup: every element sets its own transparency.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Settings)
local Palette = require(Shared.Config.Palette)
local R = require(Shared.Rules.Settings)
local Spec = require(Shared.ui.SettingsMenu) :: any
local Settings = require(script.Parent.Settings)

local SettingsMenu = {}

local C = Palette.UI.Settings :: any
local T = Spec.theme
local M = Cfg.Menu
local O = Cfg.Options :: any

local function rgb(name: string): Color3
	local c = C[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local FONTS: { [string]: Font } = {}
for name, f in T.fonts do
	FONTS[name] = Font.new(`rbxasset://fonts/families/{f.family}.json`, (Enum.FontWeight :: any)[f.weight])
end

local function find(n: any, id: string): any
	if n.id == id then
		return n
	end
	for _, c in n.children or {} do
		local f = find(c, id)
		if f then
			return f
		end
	end
	return nil
end

local function node(id: string): any
	return assert(find(Spec.root, id), id)
end

local function role(n: any, r: string): any
	for _, c in n.children or {} do
		if c.role == r then
			return c
		end
	end
	return nil
end

local function udim(a: { number }): UDim2
	return UDim2.new(a[1], a[2], a[3], a[4])
end

-- a spec node's place (its offsets are reference pixels: the UIScale does the rest)
local function place(obj: GuiObject, n: any)
	obj.Position = udim(n.pos or { 0, 0, 0, 0 })
	obj.Size = udim(n.size or { 1, 0, 1, 0 })
	if n.anchor then
		obj.AnchorPoint = Vector2.new(n.anchor[1], n.anchor[2])
	end
end

-- a flat box: fill, rounded corners and a line (`thickness`: the panel's own `stroke`, else `thin`)
local function box(obj: GuiObject, fill: string, line: string?, thickness: number?): UIStroke?
	obj.BackgroundColor3 = rgb(fill)
	obj.BackgroundTransparency = 0
	obj.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, T.corner)
	corner.Parent = obj
	if not line then
		return nil
	end
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or C.thin
	stroke.Color = rgb(line)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = obj
	return stroke
end

local ALIGN = { left = Enum.TextXAlignment.Left, right = Enum.TextXAlignment.Right }
local function text(obj: TextLabel | TextButton, s: string, n: any)
	obj.Text = s
	obj.FontFace = FONTS[n.font or "body"]
	obj.TextSize = n.textSize
	obj.TextColor3 = rgb(n.textColor or "text")
	obj.TextXAlignment = ALIGN[n.align] or Enum.TextXAlignment.Center
end

local function label(parent: Instance, s: string, n: any): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = n.id
	l.BackgroundTransparency = 1
	place(l, n)
	text(l, s, n)
	l.Parent = parent
	return l
end

local function clearButton(parent: Instance, name: string): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.Parent = parent
	return b
end

-- a square turned 45 degrees inside a node's box (the close and gear buttons, the slider knob)
local function diamond(parent: GuiObject, fill: string, line: string?): Frame
	local d = Instance.new("Frame")
	d.Name = "Diamond"
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.fromScale(0.5, 0.5)
	d.Size = UDim2.fromScale(1 / math.sqrt(2), 1 / math.sqrt(2))
	d.SizeConstraint = Enum.SizeConstraint.RelativeYY
	d.Rotation = 45
	d.BackgroundColor3 = rgb(fill)
	d.BorderSizePixel = 0
	if line then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = C.thin
		stroke.Color = rgb(line)
		stroke.Parent = d
	end
	d.Parent = parent
	return d
end

-- the button colours: idle, or picked (also a keybind waiting for its key)
local function paint(b: TextButton, stroke: UIStroke?, picked: boolean)
	b.BackgroundColor3 = rgb(if picked then "selFill" else "field")
	b.TextColor3 = rgb(if picked then "selText" else "text")
	if stroke then
		stroke.Color = rgb(if picked then "selLine" else "line")
	end
end

-- a key or mouse button as shown
local MOUSE = { MouseButton1 = "Left mouse", MouseButton2 = "Right mouse", MouseButton3 = "Middle mouse" }
local function keyName(name: string): string
	return MOUSE[name] or name
end

-- a row from its kind's template (spec "<Kind>Row"): the row frame, its name label, its control's node
local function row(parent: Instance, order: number, kind: string, name: string): (Frame, TextLabel, any, any)
	local tpl = node(kind .. "Row")
	local r = Instance.new("Frame")
	r.Name = kind .. "Row"
	r.BackgroundTransparency = 1
	r.Size = udim(tpl.size)
	r.LayoutOrder = order
	r.Parent = parent
	local n = label(r, name, role(tpl, "name"))
	n.Name = "Name"
	return r, n, tpl, role(tpl, "control")
end

local function frame(parent: Instance, n: any): Frame
	local f = Instance.new("Frame")
	f.Name = "Control"
	f.BackgroundTransparency = 1
	place(f, n)
	f.Parent = parent
	return f
end

-- one button per value, `gap` apart; returns `refresh(current)` that lights the current one
local function segmented(c: Frame, gap: number, values: { string }, textNode: any, pick: (string) -> ()): (string) -> ()
	local buttons: { [string]: TextButton } = {}
	local strokes: { [string]: UIStroke? } = {}
	local n = #values
	for i, v in values do
		local b = Instance.new("TextButton")
		b.Name = v
		b.AutoButtonColor = false
		b.Position = UDim2.new((i - 1) / n, (i - 1) * gap / n, 0, 0)
		b.Size = UDim2.new(1 / n, -gap * (n - 1) / n, 1, 0)
		local stroke = box(b, "field", "line")
		text(b, v, textNode)
		b.Parent = c
		b.Activated:Connect(function()
			pick(v)
		end)
		buttons[v], strokes[v] = b, stroke
	end
	return function(current: string)
		for v, b in buttons do
			paint(b, strokes[v], v == current)
		end
	end
end

-- the first value button in a template's control (its text size and font)
local function segNode(control: any): any
	return control.children[1]
end

local function choiceRow(parent: Instance, order: number, key: string)
	local opt = O[key]
	local r, _, _, cn = row(parent, order, "Choice", opt.label)
	local refresh = segmented(frame(r, cn), cn.gap, opt.values, segNode(cn), function(v)
		Settings.set(key, v)
	end)
	refresh(Settings.get(key))
	Settings.changed(key, refresh)
end

local function presetRow(parent: Instance, order: number)
	local r, name, _, cn = row(parent, order, "Preset", Cfg.PresetLabel)
	local refresh = segmented(frame(r, cn), cn.gap, Cfg.PresetOrder, segNode(cn), function(p)
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
	local r, _, tpl, cn = row(parent, order, "Slider", opt.label)
	local value = label(r, "", role(tpl, "value"))
	local c = frame(r, cn)
	local line = Instance.new("Frame")
	line.Name = "Track"
	place(line, role(cn, "track"))
	box(line, "line")
	line.Parent = c
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	box(fill, "accent")
	fill.Parent = line
	local kn = role(cn, "knob")
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.BackgroundTransparency = 1
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = udim(kn.size)
	knob.ZIndex = 2
	diamond(knob, "accent").ZIndex = 2
	knob.Parent = line
	-- the whole control takes the press (a button: it sinks the click, so the gun doesn't fire)
	local hit = clearButton(c, "Hit")
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 3

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
		local share = (x - line.AbsolutePosition.X) / math.max(line.AbsoluteSize.X, 1)
		Settings.set(key, R.fromShare(opt, share))
	end
	hit.InputBegan:Connect(function(input)
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
	local r, _, _, cn = row(parent, order, "Key", opt.label)
	local b = Instance.new("TextButton")
	b.Name = "Key"
	b.AutoButtonColor = false
	place(b, cn)
	local stroke = box(b, "field", "line")
	text(b, "", cn)
	b.Parent = r
	local function refresh()
		b.Text = if capturing == key then "Press a key (Esc cancels)" else keyName(Settings.get(key))
		paint(b, stroke, capturing == key)
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

-- a diamond button from a spec node: a clear hit box the node's size with the turned square inside
local function diamondButton(parent: Instance, n: any): TextButton
	local b = clearButton(parent, n.id)
	place(b, n)
	diamond(b, n.color, n.line)
	return b
end

function SettingsMenu.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "SettingsMenu"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = M.DisplayOrder

	local gn = node("Gear")
	local gear = diamondButton(gui, gn)
	local gi = node("GearIcon")
	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Image = Spec.icons[gi.icon]
	icon.ImageColor3 = rgb(gi.color)
	place(icon, gi)
	icon.Parent = gear

	-- behind the panel: a click outside it closes the menu (and never reaches the game); it dims the game a little
	local backdrop = clearButton(gui, "Backdrop")
	backdrop.BackgroundColor3 = rgb("backdrop")
	backdrop.BackgroundTransparency = C.backdropTransparency
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Visible = false

	local pn = node("Panel")
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.Active = true
	place(panel, pn)
	panel.Visible = false
	box(panel, pn.color, pn.line, C.stroke)
	panel.Parent = gui
	local scales = {}
	for _, obj in { panel, gear } do
		local s = Instance.new("UIScale")
		s.Parent = obj
		table.insert(scales, s)
	end
	local function rescale()
		-- one scale for the reference height, the panel never taller than the screen
		local h = gui.AbsoluteSize.Y
		local s =
			math.min(math.clamp(h / T.scale.referenceHeight, T.scale.min, T.scale.max), (h - T.fitMargin) / pn.size[4])
		for _, u in scales do
			u.Scale = s
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)

	label(panel, "Settings", node("Title"))
	local close = diamondButton(panel, node("Close"))
	local cn = node("Close")
	local x = Instance.new("TextLabel")
	x.Name = "X"
	x.BackgroundTransparency = 1
	x.Size = UDim2.fromScale(1, 1)
	x.ZIndex = 2
	text(x, cn.text, cn)
	x.Parent = close
	local rule = Instance.new("Frame")
	rule.Name = "Rule"
	place(rule, node("Rule"))
	rule.BackgroundColor3 = rgb(node("Rule").color)
	rule.BorderSizePixel = 0
	rule.Parent = panel

	-- the tab bar (clear buttons, the open one bright and underlined), and one scrolling page per tab
	local tn = node("Tabs")
	local bar = Instance.new("Frame")
	bar.Name = "Tabs"
	bar.BackgroundTransparency = 1
	place(bar, tn)
	bar.Parent = panel
	local tabNode = node("Tab1")
	local un = node("Underline")
	local tabs: { [string]: TextButton } = {}
	local underlines: { [string]: Frame } = {}
	local openTab: (string) -> ()
	local n = #Cfg.Tabs
	for i, tab in Cfg.Tabs do
		local b = clearButton(bar, tab.name)
		b.Position = UDim2.new((i - 1) / n, (i - 1) * tn.gap / n, 0, 0)
		b.Size = UDim2.new(1 / n, -tn.gap * (n - 1) / n, 1, 0)
		text(b, tab.name, tabNode)
		local u = Instance.new("Frame")
		u.Name = "Underline"
		place(u, un)
		u.BackgroundColor3 = rgb(un.color)
		u.BorderSizePixel = 0
		u.Parent = b
		b.Activated:Connect(function()
			openTab(tab.name)
		end)
		tabs[tab.name], underlines[tab.name] = b, u
	end

	local refreshKeys: { () -> () } = {}
	local function capture(key: string?)
		capturing = key
		for _, f in refreshKeys do
			f()
		end
	end

	local pg = node("Page")
	local pages: { [string]: ScrollingFrame } = {}
	for i, tab in Cfg.Tabs do
		local page = Instance.new("ScrollingFrame")
		page.Name = tab.name
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		place(page, pg)
		page.CanvasSize = UDim2.new()
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.ScrollingDirection = Enum.ScrollingDirection.Y
		page.ScrollBarThickness = T.scrollBar
		page.ScrollBarImageColor3 = rgb("lineStrong")
		page.Visible = i == 1
		page.Parent = panel
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, pg.gap)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = page
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
		for t, page in pages do
			page.Visible = t == name
		end
		for t, b in tabs do
			b.TextColor3 = rgb(if t == name then "title" else "textDim")
			underlines[t].Visible = t == name
		end
		capture(nil)
	end
	openTab(Cfg.Tabs[1].name)

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
