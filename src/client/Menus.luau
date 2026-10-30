--!strict
-- The title screen and the loadout menu (user 2026-10-27), over the live match (src/client/MatchCam). There is no
-- character until the player deploys (src/server/Deploy): the title screen shows on join (Play, Customization still
-- locked, Settings), Play opens the loadout menu, and the loadout menu opens again Config/Classes.MenuAfterDeath
-- seconds after every death; its Back button returns to the title screen. Where teams are kept (Config/Teams; the
-- state's `teams`) its "Change team" button opens three team cards (user 2026-10-27): a gradient placeholder for the
-- team's art (Palette UI.Hud.Teams) with its name and "count / room" in the middle, the text white where you can join,
-- red where you can't (Rules/Teams.blocked) and grey on your own. A card you can join asks for a second click (the
-- change resets your Marks), then goes to the server (Net "Loadout" "Team"), which checks the balance again. The menu lists the classes (Config/Classes.List: name, blurb, cost; picked, locked or
-- not affordable), the match currency (shown only here, user: "they only see their match currency in the loadout menu
-- when they are respawning"), and the soldier you'll spawn as, turning slowly: the server's "LoadoutPreview" rig in a
-- ViewportFrame, playing its primary's ready hold. Deploy lights up once the respawn delay is over (Net "Loadout").
-- Layout, sizes and the one basic font come from src/shared/ui/TitleScreen.json and LoadoutMenu.json (the local
-- layout check and preview read the same files); offsets are reference pixels, scaled here by the GUI height. Colours:
-- Config/Palette UI.Settings, or the palette a spec's theme names (the title screen: UI.Grimoire, the UI overhaul's
-- Field Grimoire, user 2026-10-30; its ink drawing is src/client/Ink, its live map src/client/SketchMap). No
-- CanvasGroup: every element sets its own transparency.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared.Config.Classes)
local Locomotion = require(Shared.Config.Locomotion)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local W = require(Shared.Config.Weapons)
local MovementSet = require(Shared.Rules.MovementSet)
local Net = require(Shared.Net)
local TitleSpec = require(Shared.ui.TitleScreen) :: any
local LoadoutSpec = require(Shared.ui.LoadoutMenu) :: any
local SketchCfg = require(Shared.Config.SketchMap) :: any
local Ink = require(script.Parent.Ink)
local MatchCam = require(script.Parent.MatchCam)
local SettingsMenu = require(script.Parent.SettingsMenu)
local SketchMap = require(script.Parent.SketchMap)

local Menus = {}

local C = Palette.UI.Settings :: any
local GR = (Palette.UI :: any).Grimoire
local function gcol(name: string): Color3
	local c = GR[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end
local Anims = MovementSet.animations(Locomotion) :: any
local DISPLAY_ORDER = 5 -- under the settings menu (Config/Settings.Menu.DisplayOrder)

local function rgb(name: string): Color3
	local c = C[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function fontOf(spec: any): Font
	local f = spec.theme.fonts.body
	return Font.new(`rbxasset://fonts/families/{f.family}.json`, (Enum.FontWeight :: any)[f.weight])
end

local ALIGN = { left = Enum.TextXAlignment.Left, right = Enum.TextXAlignment.Right }

-- One screen built from its spec: every node by id, laid out again at the GUI's scale when the window changes; its
-- live maps and rune inscriptions by node id.
type Runes = { canvas: Ink.Canvas, names: { string }, fade: number }
type Screen = {
	gui: ScreenGui,
	node: { [string]: GuiObject },
	spec: { [string]: any },
	relayout: () -> (),
	maps: { [string]: any },
	runes: { [string]: Runes },
}

-- paints a node's rune inscription (spec `runes`) in a colour
local function paintRunes(r: Runes, colour: Color3)
	r.canvas.set(function(holder, w, h)
		local rw, gap = h * 0.62, h * 0.34
		local x = w - #r.names * (rw + gap) + gap
		for _, n in r.names do
			Ink.rune(holder, n, x, 0, rw, h, math.max(1, h * 0.1), colour, r.fade)
			x += rw + gap
		end
	end)
end

local function build(spec: any, name: string, parent: Instance): Screen
	local T = spec.theme
	local font = fontOf(spec)
	local own = T.palette and (Palette.UI :: any)[T.palette]
	local function col(n: string): Color3
		local c = (own and own[n]) or C[n]
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = DISPLAY_ORDER
	gui.Enabled = false
	local screen: Screen = { gui = gui, node = {}, spec = {}, relayout = function() end, maps = {}, runes = {} }
	local placed: { { obj: GuiObject, n: any } } = {}

	local function make(n: any, into: Instance)
		local obj: GuiObject
		if n.kind == "button" then
			local b = Instance.new("TextButton")
			b.AutoButtonColor = false
			obj = b
		elseif n.kind == "label" then
			obj = Instance.new("TextLabel")
		elseif n.kind == "model" then
			obj = Instance.new("ViewportFrame")
		elseif n.kind == "image" then
			local img = Instance.new("ImageLabel")
			img.ScaleType = Enum.ScaleType.Fit
			obj = img
		else
			obj = Instance.new("Frame")
		end
		obj.Name = n.id
		obj.BorderSizePixel = 0
		obj.BackgroundTransparency = 1
		if (n.kind == "panel" or n.kind == "button") and not n.clear and not n.slab then
			obj.BackgroundTransparency = 0
			obj.BackgroundColor3 = col(n.color or "field")
			local corner = Instance.new("UICorner")
			corner.Parent = obj
			if n.line then
				local stroke = Instance.new("UIStroke")
				stroke.Color = col(n.line)
				stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				stroke.Parent = obj
			end
		end
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			obj.FontFace = font
			obj.Text = n.text or ""
			obj.TextColor3 = col(n.textColor or "text")
			obj.TextXAlignment = ALIGN[n.align] or Enum.TextXAlignment.Center
			obj.TextTruncate = Enum.TextTruncate.AtEnd
			obj.RichText = true
			obj.TextTransparency = n.fade or 0
			obj.LineHeight = n.lineHeight or 1
			if n.shade then
				obj.TextStrokeColor3 = col("shade")
				obj.TextStrokeTransparency = n.shade
			end
			if n.padLeft then
				local pad = Instance.new("UIPadding")
				pad.Parent = obj
			end
			if n.wrap then
				obj.TextWrapped = true
				obj.TextTruncate = Enum.TextTruncate.None
			end
			if n.slab then
				-- the ink plate under the words: the words move to a label over it (a child draws over its parent)
				Ink.slab(obj, if n.tint then col(n.tint) else nil)
				local words = Instance.new("TextLabel")
				words.Name = "Words"
				words.BackgroundTransparency = 1
				words.Size = UDim2.fromScale(1, 1)
				words.FontFace = obj.FontFace
				words.Text = obj.Text
				words.TextColor3 = obj.TextColor3
				words.TextXAlignment = obj.TextXAlignment
				words.RichText = true
				obj.TextTransparency = 1
				words.Parent = obj
			end
			if n.runes then
				local box = Instance.new("Frame")
				box.Name = "Runes"
				box.BackgroundTransparency = 1
				box.AnchorPoint = Vector2.new(1, 0.5)
				box.Position = UDim2.new(1, -14, 0.5, 0)
				box.Size = UDim2.fromScale(0.45, 0.3)
				box.Parent = obj
				local r: Runes = { canvas = Ink.canvas(box), names = n.runes, fade = n.runesFade or 0.6 }
				screen.runes[n.id] = r
				paintRunes(r, col("text"))
			end
		end
		if n.card then
			-- a paper card (Config/SketchMap.Paper) with a red pencil edge kept for when it's picked
			obj.BackgroundTransparency = 1
			local p = SketchCfg.Paper
			local sheet = Instance.new("ImageLabel")
			sheet.Name = "Paper"
			sheet.BackgroundTransparency = 1
			sheet.Image = `rbxassetid://{p.image}`
			sheet.ScaleType = Enum.ScaleType.Slice
			sheet.SliceCenter = Rect.new(p.slice[1], p.slice[2], p.slice[3], p.slice[4])
			sheet.SliceScale = 0.5
			sheet.Size = UDim2.fromScale(1, 1)
			sheet.Parent = obj
			local edge = Instance.new("UIStroke")
			edge.Name = "Pick"
			edge.Color = col("pencil")
			edge.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			edge.LineJoinMode = Enum.LineJoinMode.Miter
			edge.Enabled = false
			edge.Parent = obj
		end
		if n.kind == "overlay" then
			obj.BackgroundTransparency = 0
			obj.BackgroundColor3 = col("overlay")
			local g = Instance.new("UIGradient")
			g.Transparency = NumberSequence.new(n.from or 0.5, n.to or n.from or 0.5)
			g.Rotation = if n.vertical then 90 else 0
			g.Parent = obj
		elseif n.kind == "trench" then
			Ink.trench(obj, col("ink"), col("text"))
		elseif n.kind == "sketchmap" then
			screen.maps[n.id] = SketchMap.new(obj, nil, { deploy = n.deploy })
		end
		if n.rotation then
			obj.Rotation = n.rotation
		end
		if n.aspect then
			local a = Instance.new("UIAspectRatioConstraint")
			a.AspectRatio = n.aspect
			a.DominantAxis = Enum.DominantAxis.Width
			a.Parent = obj
		end
		if obj:IsA("ViewportFrame") then
			obj.BackgroundTransparency = 1
		end
		if n.anchor then
			obj.AnchorPoint = Vector2.new(n.anchor[1], n.anchor[2])
		end
		screen.node[n.id] = obj
		screen.spec[n.id] = n
		table.insert(placed, { obj = obj, n = n })
		for _, c in n.children or {} do
			make(c, obj)
		end
		obj.Parent = into
	end
	make(spec.root, gui)

	function screen.relayout()
		local h = gui.AbsoluteSize.Y
		if h <= 0 then
			return
		end
		local s = math.clamp(h / T.scale.referenceHeight, T.scale.min, T.scale.max)
		for _, p in placed do
			local n, obj = p.n, p.obj
			local pos, size = n.pos or { 0, 0, 0, 0 }, n.size or { 1, 0, 1, 0 }
			obj.Position = UDim2.new(pos[1], pos[2] * s, pos[3], pos[4] * s)
			obj.Size = UDim2.new(size[1], size[2] * s, size[3], size[4] * s)
			if obj:IsA("TextLabel") or obj:IsA("TextButton") then
				obj.TextSize = (n.textSize or 20) * s
				local words = obj:FindFirstChild("Words") :: TextLabel?
				if words then
					words.TextSize = obj.TextSize
				end
				local pad = obj:FindFirstChildOfClass("UIPadding")
				if pad and n.padLeft then
					pad.PaddingLeft = UDim.new(0, n.padLeft * s)
				end
			end
			local corner = obj:FindFirstChildOfClass("UICorner")
			if corner then
				corner.CornerRadius = UDim.new(0, T.corner * s)
			end
			local stroke = obj:FindFirstChildOfClass("UIStroke")
			if stroke then
				-- the screen's own panel: the theme's stroke, else thin
				stroke.Thickness = if n.id == "Panel" then C.stroke else C.thin
			end
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(screen.relayout)
	gui.Parent = parent
	return screen
end

function Menus.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	local title = build(TitleSpec, "TitleScreen", playerGui)
	local loadout = build(LoadoutSpec, "LoadoutMenu", playerGui)
	local L = loadout.node

	-- the class rows: the spec's first row is the template, one copy per class (the samples go)
	local list = L.List
	local template = L.RowRifleman
	local across = loadout.spec.List.axis == "x" -- kit cards side by side (else rows down)
	local axis = if across then 2 else 4
	local rowStep = (loadout.spec.RowGrenadier.pos[axis] - loadout.spec.RowRifleman.pos[axis]) :: number
	local Cards = Classes.Cards
	for _, c in list:GetChildren() do
		if c ~= template then
			c:Destroy()
		end
	end
	template.Parent = nil
	type Row = { button: TextButton, name: TextLabel, blurb: TextLabel, cost: TextLabel, rune: Ink.Canvas? }
	local rows: { [string]: Row } = {}
	local order: { string } = {}
	for i, key in Classes.List do
		local b = template:Clone() :: TextButton
		b.Name = "Row" .. key
		b.LayoutOrder = i
		local name = b:FindFirstChild("RiflemanName") :: TextLabel
		local blurb = b:FindFirstChild("RiflemanBlurb") :: TextLabel
		local cost = b:FindFirstChild("RiflemanCost") :: TextLabel
		name.Text = Classes.Defs[key].name
		blurb.Text = Classes.Defs[key].blurb
		b.Parent = list
		local glyph = b:FindFirstChild("RiflemanRune") :: Frame?
		rows[key] = { button = b, name = name, blurb = blurb, cost = cost, rune = glyph and Ink.canvas(glyph) }
		table.insert(order, key)
	end
	-- the copies follow the template's place, one step apart (scaled with the rest)
	local baseRelayout = loadout.relayout
	local raised: string? = nil -- the picked kit card, raised
	function loadout.relayout()
		baseRelayout()
		local base = template.Position
		for i, key in order do
			local b = rows[key].button
			local s = template.Size
			local k = s.Y.Offset / loadout.spec.RowRifleman.size[4]
			b.Size = s
			local step = (i - 1) * rowStep * k
			local lift = if key == raised then -Cards.raise * k else 0
			b.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset)
				+ (if across then UDim2.fromOffset(step, lift) else UDim2.fromOffset(0, step))
			local edge = b:FindFirstChild("Pick") :: UIStroke?
			if edge then
				edge.Thickness = Cards.edge * k
			end
			local glyph, tg =
				b:FindFirstChild("RiflemanRune") :: Frame?, template:FindFirstChild("RiflemanRune") :: Frame?
			if glyph and tg then
				glyph.Position, glyph.Size = tg.Position, tg.Size
			end
			for _, part in { "name", "blurb", "cost" } do
				local cell = (rows[key] :: any)[part] :: TextLabel
				local t = template:FindFirstChild("Rifleman" .. part:sub(1, 1):upper() .. part:sub(2)) :: TextLabel
				cell.Position, cell.Size, cell.TextSize = t.Position, t.Size, t.TextSize
			end
		end
	end
	loadout.gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(loadout.relayout)

	-- the soldier you'll spawn as
	local view = L.Model :: ViewportFrame
	local P = Classes.Preview
	view.Ambient = Color3.fromRGB(P.Ambient[1], P.Ambient[2], P.Ambient[3])
	view.LightColor = Color3.fromRGB(P.Light[1], P.Light[2], P.Light[3])
	view.LightDirection = Vector3.new(-1, -1, -1)
	local viewCam = Instance.new("Camera")
	viewCam.FieldOfView = P.Fov
	viewCam.Parent = view
	view.CurrentCamera = viewCam
	local world = Instance.new("WorldModel")
	world.Parent = view
	local shown: Model? = nil
	local function showPreview()
		if shown then
			shown:Destroy()
			shown = nil
		end
		local rig = playerGui:FindFirstChild("LoadoutPreview")
		if not rig or not rig:IsA("Model") then
			return
		end
		local m = rig:Clone()
		m.Parent = world
		shown = m
		local humanoid = m:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		local function play(id: number?, priority: Enum.AnimationPriority)
			if not id or id == 0 then
				return
			end
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. id
			local t = (animator :: Animator):LoadAnimation(a)
			t.Priority = priority
			t.Looped = true
			t:Play(0)
		end
		play(Anims.idle and Anims.idle.id, Enum.AnimationPriority.Core)
		local primary = m:GetAttribute("Primary")
		local w = type(primary) == "string" and W[primary]
		if w then
			play(w.holds.ready, Enum.AnimationPriority.Action)
		end
	end
	playerGui.ChildAdded:Connect(function(c)
		if c.Name == "LoadoutPreview" then
			task.defer(showPreview)
		end
	end)

	local state: any = nil
	local deployAt = 0
	local function render()
		if not state then
			return
		end
		local marks = L.Marks :: TextLabel
		marks.Text = `{Classes.Currency}  {state.points}`
		local picked = state.picked
		for _, card in state.classes do
			local r = rows[card.key]
			if r then
				local can = not card.locked and card.affordable
				local on = card.key == picked
				-- a paper card: picked, raised with a red pencil edge; one you can't take, faded
				local fade = if can or on then 0 else Cards.faded
				local paper = r.button:FindFirstChild("Paper") :: ImageLabel?
				if paper then
					paper.ImageTransparency = fade
				end
				local edge = r.button:FindFirstChild("Pick") :: UIStroke?
				if edge then
					edge.Enabled = on
				end
				r.name.TextColor3, r.blurb.TextColor3 = gcol("ink"), gcol("inkDim")
				r.cost.TextColor3 = gcol(if card.cost == 0 and not card.locked then "blue" else "pencil")
				for _, l in { r.name, r.blurb, r.cost } do
					l.TextTransparency = fade
				end
				r.cost.Text = if card.locked then "Soon" elseif card.cost == 0 then "Free" else tostring(card.cost)
				local runeName = Cards.runes[card.key]
				local canvas = r.rune
				if canvas and runeName then
					local colour = gcol(if on then "blue" else "ink")
					canvas.set(function(holder, w, h)
						Ink.rune(holder, runeName, 0, 0, w, h, math.max(1.5, h * 0.09), colour, fade)
					end)
				end
				if on then
					raised = card.key
				end
			end
		end
		local def = Classes.Defs[picked]
		local className = L.ClassName :: TextLabel
		className.Text = if def then def.name else ""
		loadout.relayout()
	end

	-- the title's team line, "For <team>" with the name in its colour (user 2026-10-30: no "Kingdom of"), and Play's
	-- runes in the team's magic colour
	local function setTeam(kit: any)
		local k = type(kit) == "string" and (U.Kits :: any)[kit]
		local team = title.node.Team :: TextLabel
		local nameColour = k and GR.Name[kit]
		team.Text = if k
				and k.team
				and nameColour
			then `For <font color="#{Color3.fromRGB(nameColour[1], nameColour[2], nameColour[3]):ToHex()}">{k.team}</font>`
			else ""
		local magic = k and GR.Magic[kit]
		local runes = title.runes.Play
		if runes and magic then
			paintRunes(runes, Color3.fromRGB(magic[1], magic[2], magic[3]))
		end
	end

	-- the team cards (only where teams are kept: the state's `teams`, src/server/Deploy)
	local teamGroup, cardsGroup = L.Team, L.Teams
	local changeTeam = L.ChangeTeam :: TextButton
	local teamName = L.TeamName :: TextLabel
	local teamNote = L.TeamNote :: TextLabel
	local HudTeams = (Palette.UI :: any).Hud.Teams
	local cardsOpen = false
	local armed: string? = nil -- the card clicked once, waiting for the second click
	local function nameOf(kit: string): string
		local k = (U.Kits :: any)[kit]
		return if k and k.team then k.team else kit
	end
	local cards: { [string]: TextButton } = {}
	for _, kit in U.Teams do
		local card = L["Card" .. nameOf(kit)] :: TextButton?
		if card then
			cards[kit] = card
			-- the placeholder for the team's art: its box colours, dark in the middle under the text
			local t = HudTeams[kit]
			if t then
				card.BackgroundColor3 = Color3.new(1, 1, 1)
				local g = Instance.new("UIGradient")
				g.Rotation = 90
				local field, rim = Color3.fromRGB(table.unpack(t.field)), Color3.fromRGB(table.unpack(t.rim))
				g.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, rim:Lerp(field, 0.5)),
					ColorSequenceKeypoint.new(0.45, field),
					ColorSequenceKeypoint.new(1, rim),
				})
				g.Parent = card
			end
			-- its flag over its name, for now (user 2026-10-30: "put team flags there")
			local k = (U.Kits :: any)[kit]
			local flag = L["Flag" .. nameOf(kit)] :: ImageLabel?
			if flag then
				flag.Image = if k and k.flag then `rbxassetid://{k.flag.full}` else ""
			end
		end
	end
	local function renderTeams()
		local t = state and state.teams
		teamGroup.Visible = t ~= nil
		cardsGroup.Visible = t ~= nil and cardsOpen
		changeTeam.TextTransparency = if cardsOpen then 0 else (loadout.spec.ChangeTeam.fade or 0)
		if not t then
			armed = nil
			return
		end
		teamName.Text = `{nameOf(t.own)} army`
		if armed and t.closed[armed] ~= "" then
			armed = nil
		end
		for kit, card in cards do
			local color = if kit == t.own then "textDim" elseif t.closed[kit] ~= "" then "noText" else "selText"
			local name = L["Name" .. nameOf(kit)] :: TextLabel
			local count = L["Count" .. nameOf(kit)] :: TextLabel
			name.TextColor3, count.TextColor3 = rgb(color), rgb(color)
			local flag = L["Flag" .. nameOf(kit)] :: ImageLabel?
			if flag then
				-- (a closed team's flag dimmed)
				flag.ImageTransparency = if t.closed[kit] ~= "" then 0.6 else 0
			end
			count.Text = `{t.counts[kit] or 0} / {t.room}`
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = rgb(if kit == armed then "selLine" else "line")
			end
		end
		teamNote.Text = if armed
			then `Click {nameOf(armed)} again to join: your Marks reset`
			else "Changing team resets your Marks"
	end
	changeTeam.Activated:Connect(function()
		cardsOpen = not cardsOpen
		armed = nil
		renderTeams()
	end)
	for kit, card in cards do
		card.Activated:Connect(function()
			local t = state and state.teams
			if not t or t.closed[kit] ~= "" then
				return
			end
			if armed == kit then
				armed, cardsOpen = nil, false
				Net.event("Loadout"):FireServer("Team", kit)
			else
				armed = kit
			end
			renderTeams()
		end)
	end

	local menuOpen = false
	local function refresh()
		menuOpen = title.gui.Enabled or loadout.gui.Enabled
		if menuOpen then
			MatchCam.start()
		else
			MatchCam.stop()
		end
	end
	local function open(which: Screen?)
		title.gui.Enabled = which == title
		loadout.gui.Enabled = which == loadout
		if which then
			which.relayout()
		end
		if which == loadout then
			loadout.relayout()
		end
		refresh()
	end

	for key, r in rows do
		r.button.Activated:Connect(function()
			local card = state
				and (function()
					for _, c in state.classes do
						if c.key == key then
							return c
						end
					end
					return nil
				end)()
			if card and not card.locked and card.affordable then
				Net.event("Loadout"):FireServer("Pick", key)
			end
		end)
	end
	local back = L.Back :: TextButton
	back.Activated:Connect(function()
		cardsOpen, armed = false, nil
		renderTeams()
		open(title)
	end)
	local deploy = L.Deploy :: TextButton
	deploy.Activated:Connect(function()
		if state and os.clock() >= deployAt then
			Net.event("Loadout"):FireServer("Deploy")
		end
	end)
	local play = title.node.Play :: TextButton
	play.Activated:Connect(function()
		open(loadout)
		Net.event("Loadout"):FireServer("Ask")
	end)
	local settings = title.node.Settings :: TextButton
	settings.Activated:Connect(function()
		SettingsMenu.open()
	end)
	-- a faded word comes up under the mouse (not the locked one)
	settings.MouseEnter:Connect(function()
		settings.TextTransparency = 0
	end)
	settings.MouseLeave:Connect(function()
		settings.TextTransparency = title.spec.Settings.fade or 0
	end)
	-- under the map: where the front is and the head counts, where known
	local caption = title.node.Caption :: TextLabel
	local titleMap = title.maps.Map
	local function writeCaption()
		local parts = {}
		local at = titleMap and titleMap.front()
		if at then
			table.insert(parts, `The front at {at}`)
		end
		local t = state and state.teams
		if t and t.counts then
			for _, kit in U.Teams do
				local c = t.counts[kit]
				if c then
					table.insert(parts, `{nameOf(kit)} {c}`)
				end
			end
		end
		caption.Text = table.concat(parts, " · ")
	end

	local deathSeen = 0
	Net.event("Loadout").OnClientEvent:Connect(function(s: any)
		local wasAlive = state and state.alive
		state = s
		deployAt = os.clock() + (s.wait or 0)
		setTeam(s.kit)
		render()
		renderTeams()
		-- a death (the state the server sends as the soldier falls): the menu after a moment, the death seen first
		if wasAlive ~= false and s.alive == false and not title.gui.Enabled and not loadout.gui.Enabled then
			deathSeen += 1
			local mine = deathSeen
			task.delay(Classes.MenuAfterDeath, function()
				if mine == deathSeen and state and not state.alive and not title.gui.Enabled then
					open(loadout)
				end
			end)
		end
	end)

	-- deployed: the menus go, the game's camera comes back
	player.CharacterAdded:Connect(function()
		deathSeen += 1
		if state then
			state.alive = true
		end
		open(nil)
	end)

	-- Deploy on its ink plate, the plate red once you can go; where you'll deploy, under the loadout's map
	local deployWords = deploy:FindFirstChild("Words") :: TextLabel?
	local deploySlab = deploy:FindFirstChild("Slab") :: ImageLabel?
	local function setDeploy(text: string, ready: boolean)
		deploy.Text = text
		if deployWords then
			deployWords.Text = text
			deployWords.TextTransparency = if ready then 0 else 0.35
		end
		if deploySlab then
			deploySlab.ImageColor3 = gcol(if ready then "pencil" else "ink")
		end
	end
	local loadoutMap = loadout.maps.Map
	local loadoutCaption = L.Caption :: TextLabel
	RunService.RenderStepped:Connect(function()
		if title.gui.Enabled then
			writeCaption()
		end
		if loadout.gui.Enabled and loadoutMap then
			loadoutMap.deploy(state and state.kit)
			local at = loadoutMap.deployName()
			loadoutCaption.Text = if at then `You deploy at {at}` else ""
		end
		if loadout.gui.Enabled then
			local left = deployAt - os.clock()
			if left > 0 then
				setDeploy(`Deploy in {math.ceil(left)}`, false)
			else
				setDeploy("Deploy", true)
			end
			-- the soldier turns slowly in its view
			local t = os.clock() * P.Turn
			local look = Vector3.new(0, P.Look, 0)
			local out = Vector3.new(math.sin(t) * P.Distance, P.Up, -math.cos(t) * P.Distance)
			viewCam.CFrame = CFrame.lookAt(look + out, look)
		end
		if menuOpen then
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end
	end)

	-- the join: the title screen (unless a soldier is already out, e.g. a respawn from the dev tools)
	if player.Character then
		state = { alive = true }
	else
		open(title)
		Net.event("Loadout"):FireServer("Ask") -- (the team line and the preview get ready meanwhile)
	end
end

return Menus
