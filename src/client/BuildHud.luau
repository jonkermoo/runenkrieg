--!strict
-- The shovel's panel at the bottom of the screen, built from its spec (src/shared/ui/BuildHud.json; colours
-- Config/Palette.UI.BuildHud; user 2026-10-27: the Bold look, "make it more distinct for each mode its in"). src/client/
-- Build decides what it says each frame and hands it a View; this only draws it:
-- - a tab over the top-left naming the mode (Build, Destroy, Placing, Trench plan) in the mode's colour, with its icon
-- - the see-through body with the status edge (go / no-go, else the mode's colour) and the mode's own face: Build a
--   rim along the top, Destroy a hazard band, Placing a blueprint grid with corner ticks, the trench plan a chalk line
-- - the title row (Placing: the pieces before and after either side, on their keys; Build and Destroy: what you point
--   at and its HP x / y), then a why-not line (red, when it can't go), a rule with a tick per trench square, and the key caps
-- - a badge by the cursor with the mode's icon
-- Icons are drawn from flat frames (no images). Offsets are reference pixels: one UIScale per panel does the rest.
--   BuildHud.new(player) -> { set(view: View?) }

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Palette = require(Shared.Config.Palette)
local Spec = require(Shared.ui.BuildHud) :: any

local BuildHud = {}

local HUD = Palette.UI.BuildHud :: any
local T = Spec.theme
local P = Spec.panel
local TX = Spec.text
local F = Spec.faces
local FONT =
	Font.new(`rbxasset://fonts/families/{T.fonts.body.family}.json`, (Enum.FontWeight :: any)[T.fonts.body.weight])

export type Key = { string } -- the key's name, what it does
export type View = {
	mode: string, -- "Build", "Destroy", "Place" or "Plan" (Spec.modes)
	edge: string?, -- "ok" or "bad"; nil: the mode's colour
	title: string,
	titleBad: boolean?,
	sub: string?,
	-- Placing: the pieces before and after, on their keys
	prev: { string }?, -- { key, name }
	next: { string }?,
	stat: { text: string, icon: string?, tone: string? }?, -- icon "ok" / "bad"; tone "bad" (the can't-go colour)
	ruler: { length: number, max: number, step: number }?,
	keys: { Key },
}
export type Hud = { set: (view: View?) -> () }

local function rgb(name: string): Color3
	local c = HUD[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function frame(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundTransparency = 1
	f.Parent = parent
	return f
end

local function auto(f: GuiObject)
	f.AutomaticSize = Enum.AutomaticSize.XY
	f.Size = UDim2.fromOffset(0, 0)
end

local function list(parent: Instance, horizontal: boolean, gap: number, align: Enum.VerticalAlignment?)
	local l = Instance.new("UIListLayout")
	l.FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical
	l.VerticalAlignment = align or Enum.VerticalAlignment.Center
	l.Padding = UDim.new(0, gap)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = parent
end

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function label(parent: Instance, size: number, color: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = rgb(color)
	l.TextXAlignment = Enum.TextXAlignment.Left
	auto(l)
	l.Parent = parent
	return l
end

-- a key cap (the key's name on a light cap)
local function cap(parent: Instance, text: string, order: number): TextLabel
	local c = label(parent, TX.cap, "keyText")
	c.Text = text
	c.LayoutOrder = order
	c.BackgroundColor3 = rgb("key")
	c.BackgroundTransparency = 0
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 5), UDim.new(0, 5)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 2), UDim.new(0, 2)
	pad.Parent = c
	corner(c, 2)
	return c
end

-- a bar in an icon's unit square: centre `x`, `y`, `w` x `h`, turned `rotation` degrees
local function bar(parent: Instance, x: number, y: number, w: number, h: number, rotation: number?)
	local f = frame(parent, "Bar")
	f.BackgroundTransparency = 0
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Rotation = rotation or 0
end

-- the flat icons: a shovel, a pick, a plus, a surveyor's peg, a tick, a cross
local ICONS: { [string]: (Frame) -> () } = {
	shovel = function(f)
		bar(f, 0.38, 0.62, 0.62, 0.15, -45)
		bar(f, 0.7, 0.3, 0.34, 0.34, 45)
	end,
	pick = function(f)
		bar(f, 0.5, 0.6, 0.15, 0.72)
		bar(f, 0.5, 0.22, 0.9, 0.17)
	end,
	plus = function(f)
		bar(f, 0.5, 0.5, 0.84, 0.18)
		bar(f, 0.5, 0.5, 0.18, 0.84)
	end,
	peg = function(f)
		bar(f, 0.31, 0.52, 0.15, 0.88)
		bar(f, 0.6, 0.26, 0.46, 0.3)
	end,
	ok = function(f)
		bar(f, 0.32, 0.64, 0.38, 0.17, 45)
		bar(f, 0.62, 0.5, 0.66, 0.17, -50)
	end,
	bad = function(f)
		bar(f, 0.5, 0.5, 0.9, 0.17, 45)
		bar(f, 0.5, 0.5, 0.9, 0.17, -45)
	end,
}

local function icon(parent: Instance, name: string, size: number): Frame
	local f = frame(parent, name)
	f.Size = UDim2.fromOffset(size, size)
	ICONS[name](f)
	return f
end

local function paint(f: Instance, color: Color3)
	for _, b in f:GetChildren() do
		if b:IsA("Frame") then
			b.BackgroundColor3 = color
		end
	end
end

local function scaled(gui: ScreenGui, obj: GuiObject): UIScale
	local s = Instance.new("UIScale")
	s.Parent = obj
	local function rescale()
		s.Scale = math.clamp(gui.AbsoluteSize.Y / T.scale.referenceHeight, T.scale.min, T.scale.max)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()
	return s
end

function BuildHud.new(player: Player): Hud
	local gui = Instance.new("ScreenGui")
	gui.Name = "BuildHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false

	local root = frame(gui, "Panel")
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -P.bottom)

	-- the tab: the mode's name and icon on its colour, squared off where it meets the body
	local tab = frame(root, "Tab")
	tab.AnchorPoint = Vector2.new(0, 1)
	tab.AutomaticSize = Enum.AutomaticSize.X
	tab.Size = UDim2.fromOffset(0, Spec.tab.height)
	tab.BackgroundTransparency = 0
	corner(tab, T.corner)
	local foot = frame(tab, "Foot")
	foot.BackgroundTransparency = 0
	foot.AnchorPoint = Vector2.new(0, 1)
	foot.Position = UDim2.fromScale(0, 1)
	foot.Size = UDim2.new(1, 0, 0, T.corner)
	local tabRow = frame(tab, "Row")
	tabRow.ZIndex = 2
	tabRow.Size = UDim2.fromScale(0, 1)
	tabRow.AutomaticSize = Enum.AutomaticSize.X
	list(tabRow, true, Spec.tab.gap)
	local tabPad = Instance.new("UIPadding")
	tabPad.PaddingLeft, tabPad.PaddingRight = UDim.new(0, Spec.tab.padLeft), UDim.new(0, Spec.tab.padRight)
	tabPad.Parent = tabRow
	local tabIcons: { [string]: Frame } = {}
	for name, m in Spec.modes do
		local i = icon(tabRow, m.icon, Spec.tab.icon)
		i.Name = name
		i.LayoutOrder = 1
		paint(i, rgb("keyText"))
		tabIcons[name] = i
	end
	local tabText = label(tabRow, TX.tab, "keyText")
	tabText.LayoutOrder = 2

	-- the body: as big as its rows (sized from them below, not by AutomaticSize, which grew it to the faces' stripes
	-- and grid lines: user 2026-10-27, "the build hud fills the screen")
	local body = frame(root, "Body")
	body.BackgroundTransparency = P.transparency
	body.ClipsDescendants = true
	corner(body, T.corner)
	local chalk = Instance.new("UIStroke")
	chalk.Thickness = T.outline
	chalk.Color = rgb("modePlan")
	chalk.Transparency = F.chalk
	chalk.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	chalk.Parent = body

	-- the faces, under everything else in the body
	local faces: { [string]: Frame } = {}
	local rim = frame(body, "Rim")
	rim.BackgroundTransparency = 0
	rim.BackgroundColor3 = rgb("modeBuild")
	rim.Size = UDim2.new(1, 0, 0, F.rim)
	faces.rim = rim
	local hazard = frame(body, "Hazard")
	hazard.BackgroundTransparency = 0
	hazard.BackgroundColor3 = rgb("hazardDark")
	hazard.Size = UDim2.new(1, 0, 0, F.hazard.height)
	hazard.ClipsDescendants = true
	for x = 0, F.extent[1], F.hazard.stripe * 2 do
		local s = frame(hazard, "Stripe")
		s.BackgroundTransparency = 0
		s.BackgroundColor3 = rgb("modeDestroy")
		s.Position = UDim2.fromOffset(x, 0)
		s.Size = UDim2.new(0, F.hazard.stripe, 1, 0)
	end
	faces.hazard = hazard
	local grid = frame(body, "Grid")
	grid.Size = UDim2.fromScale(1, 1)
	grid.ClipsDescendants = true
	local function line(x: number?, y: number?)
		local l = frame(grid, "Line")
		l.BackgroundTransparency = F.grid.transparency
		l.BackgroundColor3 = rgb("modePlace")
		l.Position = UDim2.fromOffset(x or 0, y or 0)
		l.Size = if x then UDim2.new(0, 1, 1, 0) else UDim2.new(1, 0, 0, 1)
	end
	for x = F.grid.step, F.extent[1], F.grid.step do
		line(x, nil)
	end
	for y = F.grid.step, F.extent[2], F.grid.step do
		line(nil, y)
	end
	-- the blueprint's corner ticks
	local cs, ci = F.corners.size, F.corners.inset
	for _, c in { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } } do
		local x = if c[1] == 0 then P.edge + ci else -ci
		local y = if c[2] == 0 then ci else -ci
		for _, long in { true, false } do
			local t = frame(grid, "Corner")
			t.BackgroundTransparency = F.corners.transparency
			t.BackgroundColor3 = rgb("modePlace")
			t.AnchorPoint = Vector2.new(c[1], c[2])
			t.Position = UDim2.new(c[1], x, c[2], y)
			t.Size = if long then UDim2.fromOffset(cs, T.outline) else UDim2.fromOffset(T.outline, cs)
		end
	end
	faces.grid = grid
	for _, f in faces do
		f.ZIndex = 1
	end

	local edge = frame(body, "Edge")
	edge.BackgroundTransparency = 0
	edge.Size = UDim2.new(0, P.edge, 1, 0)
	edge.ZIndex = 3

	local inner = frame(body, "Inner")
	auto(inner)
	inner.ZIndex = 2
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, P.edge + P.padLeft), UDim.new(0, P.padRight)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, P.padTop), UDim.new(0, P.padBottom)
	pad.Parent = inner
	list(inner, false, P.rowGap, Enum.VerticalAlignment.Top)

	-- row 1: [Q prev] TITLE sub [next E]
	local top = frame(inner, "Top")
	auto(top)
	top.LayoutOrder = 1
	list(top, true, 10, Enum.VerticalAlignment.Bottom)
	local function side(order: number, keyFirst: boolean): (Frame, TextLabel, TextLabel)
		local s = frame(top, if keyFirst then "Prev" else "Next")
		auto(s)
		s.LayoutOrder = order
		list(s, true, 5)
		local k = cap(s, "", if keyFirst then 1 else 2)
		local n = label(s, TX.side, "title")
		n.TextTransparency = TX.sideTransparency
		n.LayoutOrder = if keyFirst then 2 else 1
		return s, k, n
	end
	local prev, prevKey, prevName = side(1, true)
	local title = label(top, TX.title, "title")
	title.LayoutOrder = 2
	local sub = label(top, TX.sub, "sub")
	sub.LayoutOrder = 3
	local nextBox, nextKey, nextName = side(4, false)

	-- the trench plan's rule
	local R = Spec.ruler
	local ruler = frame(inner, "Ruler")
	ruler.LayoutOrder = 3
	ruler.Size = UDim2.fromOffset(R.width, R.height)
	local track = frame(ruler, "Track")
	track.BackgroundTransparency = R.trackTransparency
	track.BackgroundColor3 = rgb("track")
	track.Position = UDim2.fromOffset(0, (R.tick - R.track) / 2)
	track.Size = UDim2.new(1, 0, 0, R.track)
	corner(track, 2)
	local reach = frame(ruler, "Fill")
	reach.BackgroundTransparency = 0
	reach.BackgroundColor3 = rgb("modePlan")
	reach.Position = track.Position
	corner(reach, 2)
	local marks = frame(ruler, "Marks")
	marks.Size = UDim2.fromScale(1, 1)
	marks.ZIndex = 2
	local marksFor = ""

	-- the line under the title
	local S = Spec.stat
	local stat = frame(inner, "Stat")
	auto(stat)
	stat.LayoutOrder = 4
	list(stat, true, S.gap)
	local statIcons = { ok = icon(stat, "ok", S.icon), bad = icon(stat, "bad", S.icon) }
	paint(statIcons.ok, rgb("ok"))
	paint(statIcons.bad, rgb("bad"))
	local statText = label(stat, TX.stat, "sub")
	statText.LayoutOrder = 2

	local keyRow = frame(inner, "Keys")
	auto(keyRow)
	keyRow.LayoutOrder = 5
	list(keyRow, true, P.keyGap)

	-- the badge by the cursor (its own scale: it sits outside the panel)
	local G = Spec.badge
	local badge = frame(gui, "Badge")
	badge.BackgroundTransparency = 0.2
	badge.BackgroundColor3 = rgb("panel")
	badge.Size = UDim2.fromOffset(G.size, G.size)
	corner(badge, G.size)
	local badgeRing = Instance.new("UIStroke")
	badgeRing.Thickness = T.outline
	badgeRing.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	badgeRing.Parent = badge
	local badgeIcons: { [string]: Frame } = {}
	for name, m in Spec.modes do
		local i = icon(badge, m.icon, G.icon)
		i.Name = name
		i.AnchorPoint = Vector2.new(0.5, 0.5)
		i.Position = UDim2.fromScale(0.5, 0.5)
		badgeIcons[name] = i
	end

	gui.Parent = player:WaitForChild("PlayerGui")
	local scale = scaled(gui, root)
	scaled(gui, badge)
	local function fit()
		local s = inner.AbsoluteSize / math.max(scale.Scale, 0.01)
		body.Size = UDim2.fromOffset(math.max(P.minWidth, math.ceil(s.X)), math.ceil(s.Y))
		root.Size = body.Size
	end
	inner:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	scale:GetPropertyChangedSignal("Scale"):Connect(fit)
	fit()

	local shownKeys = ""
	local function setKeys(keys: { Key })
		local sign = ""
		for _, k in keys do
			sign ..= k[1] .. "\0" .. k[2] .. "\0"
		end
		if sign == shownKeys then
			return
		end
		shownKeys = sign
		for _, c in keyRow:GetChildren() do
			if c:IsA("Frame") then
				c:Destroy()
			end
		end
		for i, k in keys do
			local item = frame(keyRow, "Key")
			auto(item)
			item.LayoutOrder = i
			list(item, true, 6)
			cap(item, k[1], 1)
			if k[2] ~= "" then
				local hint = label(item, TX.hint, "hint")
				hint.Text = k[2]
				hint.LayoutOrder = 2
			end
		end
	end

	local function setRuler(r: { length: number, max: number, step: number })
		local sign = `{r.max}:{r.step}`
		if sign ~= marksFor then
			marksFor = sign
			marks:ClearAllChildren()
			for s = 0, r.max, r.step do
				local t = frame(marks, "Tick")
				t.BackgroundTransparency = 0.45
				t.BackgroundColor3 = rgb("modePlan")
				t.Position = UDim2.new(s / r.max, -1, 0, 0)
				t.Size = UDim2.fromOffset(T.outline, R.tick)
			end
			for _, n in R.numbers do
				if n <= r.max then
					local l = label(marks, R.numberSize, "sub")
					l.TextTransparency = 0.25
					l.Text = tostring(n)
					l.AnchorPoint = Vector2.new(0.5, 1)
					l.Position = UDim2.new(n / r.max, 0, 1, 2)
				end
			end
		end
		reach.Size = UDim2.new(math.clamp(r.length / r.max, 0, 1), 0, 0, R.track)
	end

	return {
		set = function(v: View?)
			gui.Enabled = v ~= nil
			if not v then
				return
			end
			local m = Spec.modes[v.mode] or Spec.modes.Build
			local mc = rgb(m.color)
			tab.BackgroundColor3, foot.BackgroundColor3 = mc, mc
			tabText.Text = m.tab
			for name, i in tabIcons do
				i.Visible = name == v.mode
			end
			body.BackgroundColor3 = rgb(m.field)
			for name, f in faces do
				f.Visible = name == m.face
			end
			chalk.Enabled = m.face == "chalk"
			-- (the hazard band pushes the rows down)
			pad.PaddingTop = UDim.new(0, if m.face == "hazard" then P.padTop + F.hazard.padTop else P.padTop)
			edge.BackgroundColor3 = if v.edge == "ok" then rgb("ok") elseif v.edge == "bad" then rgb("bad") else mc

			title.Text = string.upper(v.title)
			title.TextColor3 = rgb(if v.titleBad then "titleBad" else "title")
			sub.Text = v.sub or ""
			sub.Visible = v.sub ~= nil and v.sub ~= ""
			prev.Visible, nextBox.Visible = v.prev ~= nil, v.next ~= nil
			if v.prev then
				prevKey.Text, prevName.Text = v.prev[1], v.prev[2]
			end
			if v.next then
				nextKey.Text, nextName.Text = v.next[1], v.next[2]
			end

			ruler.Visible = v.ruler ~= nil
			if v.ruler then
				setRuler(v.ruler)
			end

			local st = v.stat
			stat.Visible = st ~= nil
			if st then
				statIcons.ok.Visible = st.icon == "ok"
				statIcons.bad.Visible = st.icon == "bad"
				statText.Text = st.text
				statText.TextColor3 = rgb(if st.tone == "bad" then "titleBad" else "sub")
			end
			setKeys(v.keys)

			badgeRing.Color = mc
			for name, i in badgeIcons do
				i.Visible = name == v.mode
				if i.Visible then
					paint(i, mc)
				end
			end
			local at = UserInputService:GetMouseLocation()
			badge.Position = UDim2.fromOffset(at.X + G.offset[1], at.Y + G.offset[2])
		end,
	}
end

return BuildHud
