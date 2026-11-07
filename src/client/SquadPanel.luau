--!strict
-- The squad panel (Config/Squads; user 2026-11-06): opened by the loadout menu's Squad button (src/client/Menus) or the
-- Squad key in the field (Config/Settings Key_Squad, J); the key again, Esc, X or a click outside close it. Left page:
-- your squad, its rune, name and head count, each member's name over their status (Config/Squads.Status, in its ink),
-- the open slots, and Leave. Right page: your army's squads (rune, name, count, a diamond per member in its status
-- ink) with Join, or the words Yours / Full; New squad at the foot. Requests go to the server (Net "Squad",
-- src/server/Squads); what it shows comes from the players' squad attributes (src/client/Squad), redrawn every
-- Panel.Refresh seconds while open when anything changed.
-- Layout from src/shared/ui/SquadPanel.json (the local check and preview scripts read the same file); Field Grimoire's
-- notebook like the settings menu (src/client/SettingsMenu): the paper sheet folded in two, one font, one UIScale.
-- While open the Player's "MenuOpen" attribute frees the mouse (src/client/WeaponCamera).

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Squads)
local Palette = require(Shared.Config.Palette)
local SketchCfg = require(Shared.Config.SketchMap)
local U = require(Shared.Config.Uniforms)
local Rules = require(Shared.Rules.Squads)
local Spec = require(Shared.ui.SquadPanel) :: any
local Net = require(Shared.Net)
local Ink = require(script.Parent.Ink)
local Settings = require(script.Parent.Settings)
local Squad = require(script.Parent.Squad)

local SquadPanel = {}

-- set by start
function SquadPanel.open() end
function SquadPanel.toggle() end

local T = Spec.theme
local C = (Palette.UI :: any).Grimoire[T.palette] :: any

local function rgb(name: string): Color3
	local c = C[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local FONT =
	Font.new(`rbxasset://fonts/families/{T.fonts.body.family}.json`, (Enum.FontWeight :: any)[T.fonts.body.weight])

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

local function udim(a: { number }): UDim2
	return UDim2.new(a[1], a[2], a[3], a[4])
end

local function place(obj: GuiObject, n: any)
	obj.Position = udim(n.pos or { 0, 0, 0, 0 })
	obj.Size = udim(n.size or { 1, 0, 1, 0 })
	if n.anchor then
		obj.AnchorPoint = Vector2.new(n.anchor[1], n.anchor[2])
	end
end

local ALIGN = { left = Enum.TextXAlignment.Left, right = Enum.TextXAlignment.Right }

local function label(parent: Instance, n: any, s: string?): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = n.id
	l.BackgroundTransparency = 1
	place(l, n)
	l.Text = s or n.text or ""
	l.FontFace = FONT
	l.TextSize = n.textSize
	l.TextColor3 = rgb(n.textColor or "text")
	l.TextXAlignment = ALIGN[n.align] or Enum.TextXAlignment.Center
	l.TextTruncate = Enum.TextTruncate.AtEnd
	if n.wrap then
		l.TextWrapped = true
		l.TextTruncate = Enum.TextTruncate.None
		l.TextYAlignment = Enum.TextYAlignment.Top
	end
	l.Parent = parent
	return l
end

local function frame(parent: Instance, n: any): Frame
	local f = Instance.new("Frame")
	f.Name = n.id
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	place(f, n)
	f.Parent = parent
	return f
end

-- a flat box: fill and a thin line
local function box(obj: GuiObject, fill: string, line: string?)
	obj.BackgroundColor3 = rgb(fill)
	obj.BackgroundTransparency = 0
	obj.BorderSizePixel = 0
	if line then
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = C.thin
		stroke.Color = rgb(line)
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = obj
	end
end

local function button(parent: Instance, n: any): TextButton
	local b = Instance.new("TextButton")
	b.Name = n.id
	b.AutoButtonColor = false
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	place(b, n)
	if not n.clear then
		box(b, n.color or "field", n.line)
	end
	b.Text = n.text or ""
	b.FontFace = FONT
	b.TextSize = n.textSize
	b.TextColor3 = rgb(n.textColor or "text")
	b.Parent = parent
	return b
end

-- a rune drawn in ink inside a spec node's box
local function glyph(parent: Instance, n: any, rune: string): Frame
	local f = frame(parent, n)
	Ink.draw(f, function(holder, w, h)
		Ink.rune(holder, rune, 0, 0, w, h, math.max(1.5, h * 0.11), rgb("text"))
	end)
	return f
end

-- a small diamond (a square turned 45 degrees inside the node's box) in `ink`
local function pip(parent: Instance, n: any, ink: string): Frame
	local side = n.size[2] / math.sqrt(2)
	local d = Instance.new("Frame")
	d.Name = n.id
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Position = UDim2.new(n.pos[1], n.pos[2] + n.size[2] / 2, n.pos[3], n.pos[4] + n.size[4] / 2)
	d.Size = UDim2.fromOffset(side, side)
	d.Rotation = 45
	d.BorderSizePixel = 0
	d.BackgroundColor3 = rgb(ink)
	d.Parent = parent
	return d
end

local function armyName(team: string?): string
	local k = team and (U.Kits :: any)[team]
	return if k and k.team then `{k.team} squads` else "Squads"
end

function SquadPanel.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "SquadPanel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Cfg.Panel.DisplayOrder
	gui.Enabled = false

	-- behind the panel: a click outside closes it (and never reaches the game); it dims the game a little
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.BorderSizePixel = 0
	backdrop.BackgroundColor3 = rgb("backdrop")
	backdrop.BackgroundTransparency = C.backdropTransparency
	local inset = GuiService:GetGuiInset().Y
	backdrop.Position = UDim2.fromOffset(0, -inset)
	backdrop.Size = UDim2.new(1, 0, 1, inset)
	backdrop.Parent = gui

	local pn = node("Panel")
	local panel = frame(gui, pn)
	panel.Active = true
	local paper = SketchCfg.Paper
	local sheet = Instance.new("ImageLabel")
	sheet.Name = "Paper"
	sheet.BackgroundTransparency = 1
	sheet.Image = `rbxassetid://{paper.image}`
	sheet.ScaleType = Enum.ScaleType.Slice
	sheet.SliceCenter = Rect.new(paper.slice[1], paper.slice[2], paper.slice[3], paper.slice[4])
	sheet.Size = UDim2.fromScale(1, 1)
	sheet.Parent = panel
	local fn = node("Fold")
	local fold = frame(panel, fn)
	fold.BackgroundColor3 = rgb(fn.color)
	fold.BackgroundTransparency = C.foldTransparency or 0.8
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function rescale()
		local h = gui.AbsoluteSize.Y
		scale.Scale =
			math.min(math.clamp(h / T.scale.referenceHeight, T.scale.min, T.scale.max), (h - T.fitMargin) / pn.size[4])
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)

	label(panel, node("Title"))
	local rn = node("Rule")
	local rule = frame(panel, rn)
	rule.BackgroundColor3 = rgb(rn.color)
	rule.BackgroundTransparency = 0
	local close = button(panel, node("Close"))
	label(panel, node("Footer"), `{Settings.get("Key_Squad")} or Esc closes`)
	Settings.changed("Key_Squad", function(k)
		(panel:FindFirstChild("Footer") :: TextLabel).Text = `{k} or Esc closes`
	end)

	-- left page: your squad
	local mine = frame(panel, node("Mine"))
	local mineRune = frame(mine, node("MineRune"))
	local squadName = label(mine, node("SquadName"), "")
	local squadCount = label(mine, node("SquadCount"), "")
	local mn = node("Members")
	local members = frame(mine, mn)
	local noSquad = label(mine, node("NoSquad"))
	local leave = button(panel, node("Leave"))
	local m1, pip1, name1, status1 = node("Member1"), node("Pip1"), node("Name1"), node("Status1")
	type Slot = { name: TextLabel, status: TextLabel, pip: Frame }
	local slots: { Slot } = {}
	for i = 1, Cfg.Max do
		local r = frame(members, m1)
		r.Name = `Member{i}`
		r.Position = UDim2.fromOffset(0, (i - 1) * (mn.rowHeight + mn.gap))
		slots[i] = { name = label(r, name1, ""), status = label(r, status1, ""), pip = pip(r, pip1, "text") }
	end

	-- right page: the army's squads
	local page = frame(panel, node("Page"))
	local army = label(page, node("Army"), "")
	local arn = node("ArmyRule")
	local armyRule = frame(page, arn)
	armyRule.BackgroundColor3 = rgb(arn.color)
	armyRule.BackgroundTransparency = 0
	local ln = node("List")
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	place(list, ln)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ScrollBarThickness = T.scrollBar
	list.ScrollBarImageColor3 = rgb("lineStrong")
	list.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, ln.gap)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local newSquad = button(page, node("NewSquad"))
	local empty = label(
		list,
		{ id = "Empty", textSize = 18, textColor = "textDim", align = "left", size = { 1, -10, 0, 30 } },
		""
	)

	local rowN, runeN, nameN, countN, pipsN, joinN, lineN =
		node("Row1"),
		node("RowRune"),
		node("RowName"),
		node("RowCount"),
		node("RowPips"),
		node("RowJoin"),
		node("RowLine")
	local pipN = node("RowPip1")

	local function addRow(row: Rules.Row, myKey: string?, team: string, counts: { [string]: number })
		local r = frame(list, rowN)
		r.Name = row.key
		r.Position = UDim2.new()
		r.LayoutOrder = row.n
		local line = frame(r, lineN)
		line.BackgroundColor3 = rgb(lineN.color)
		line.BackgroundTransparency = 0
		glyph(r, runeN, Cfg.Names[row.n])
		label(r, nameN, row.name)
		label(r, countN, `{#row.members} / {Cfg.Max}`)
		local pips = frame(r, pipsN)
		for i, m in row.members do
			local n = table.clone(pipN)
			n.id = `Pip{i}`
			n.pos = { 0, 1 + (i - 1) * pipsN.pitch, 0, 1 }
			pip(pips, n, Cfg.Status[(m :: any).status].ink)
		end
		local why = Rules.blocked(Cfg, counts, team, myKey, row.key)
		if why == nil then
			local join = button(r, joinN)
			join.Activated:Connect(function()
				Net.event("Squad"):FireServer("Join", row.key)
			end)
		else
			local n = table.clone(joinN)
			n.textColor = if why == "Already" then "text" else "textDim"
			label(r, n, if why == "Already" then "Yours" else "Full")
		end
	end

	local drawn = ""
	local function render()
		local team = Squad.team()
		local myKey = Squad.key()
		local rows = Squad.rows()
		-- what's shown, to redraw only on a change
		local parts = { team or "-", myKey or "-" }
		for _, row in rows do
			table.insert(parts, row.key)
			for _, m in row.members do
				table.insert(parts, `{m.name}={(m :: any).status}`)
			end
		end
		local sig = table.concat(parts, "|")
		if sig == drawn then
			return
		end
		drawn = sig

		army.Text = armyName(team)
		local own: Rules.Row? = nil
		for _, row in rows do
			if row.key == myKey then
				own = row
			end
		end
		mineRune:ClearAllChildren()
		if own then
			squadName.Text = `{own.name} squad`
			squadCount.Text = `{#own.members} of {Cfg.Max} soldiers`
			Ink.draw(mineRune, function(holder, w, h)
				Ink.rune(holder, Cfg.Names[own.n], 0, 0, w, h, math.max(1.5, h * 0.11), rgb("text"))
			end)
			for i, s in slots do
				local m = own.members[i] :: any
				if m then
					local st = Cfg.Status[m.status]
					s.name.Text = m.name
					s.name.TextColor3 = rgb("text")
					s.status.Text = st.text
					s.status.TextColor3 = rgb(st.ink)
					s.pip.BackgroundColor3 = rgb(st.ink)
					s.pip.Visible = true
				else
					s.name.Text = Cfg.Open
					s.name.TextColor3 = rgb("textDim")
					s.status.Text = ""
					s.pip.Visible = false
				end
			end
		else
			squadName.Text = "No squad"
			squadCount.Text = ""
		end
		members.Visible = own ~= nil
		leave.Visible = own ~= nil
		noSquad.Visible = own == nil
		noSquad.Text = if team
			then "Not in a squad yet. Join one on the right, or start your own."
			else "No squads in a free-for-all."

		for _, c in list:GetChildren() do
			if c:IsA("GuiObject") and c ~= empty then
				c:Destroy()
			end
		end
		local of = {}
		for _, row in rows do
			for _ in row.members do
				table.insert(of, row.key)
			end
		end
		local counts = Rules.counts(of)
		for _, row in rows do
			addRow(row, myKey, team :: string, counts)
		end
		empty.Visible = #rows == 0
		empty.Text = if team then "No squads yet." else ""
		newSquad.Visible = team ~= nil and Rules.free(Cfg, counts, team) ~= nil
	end

	local function setOpen(open: boolean)
		gui.Enabled = open
		player:SetAttribute("MenuOpen", open)
		if open then
			rescale()
			drawn = ""
			render()
		end
	end
	SquadPanel.open = function()
		setOpen(true)
	end
	SquadPanel.toggle = function()
		setOpen(not gui.Enabled)
	end
	close.Activated:Connect(function()
		setOpen(false)
	end)
	backdrop.Activated:Connect(function()
		setOpen(false)
	end)
	leave.Activated:Connect(function()
		Net.event("Squad"):FireServer("Leave")
	end)
	newSquad.Activated:Connect(function()
		Net.event("Squad"):FireServer("New")
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if gui.Enabled and input.KeyCode == Enum.KeyCode.Escape then
			setOpen(false)
			return
		end
		if not processed and Settings.pressed("Key_Squad", input) then
			setOpen(not gui.Enabled)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(Cfg.Panel.Refresh)
			if gui.Enabled then
				render()
			end
		end
	end)

	gui.Parent = player:WaitForChild("PlayerGui")
	rescale()
end

return SquadPanel
