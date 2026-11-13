--!strict
-- The title screen and the loadout menu (user 2026-10-27), over the live match (src/client/MatchCam). There is no
-- character until the player deploys (src/server/Deploy): the title screen shows on join (Play, Customization still
-- locked, Settings), Play opens the loadout menu, and the loadout menu opens again Config/Classes.MenuAfterDeath
-- seconds after every death; its Back button returns to the title screen. Where teams are kept (Config/Teams; the
-- state's `teams`) its "Change team" button opens a card for each team in play (user 2026-10-27; the match's two in
-- Normal, user 2026-11-04): a gradient placeholder for the team's art (Palette UI.Hud.Teams) with its name and its
-- soldiers in the middle ("players + bots" in Normal: "2 + 4"; else "count / room"), the text white where you can join,
-- red where you can't (Rules/Teams.blocked) and grey on your own. A card you can join asks for a second click (the
-- change resets your Marks), then goes to the server (Net "Loadout" "Team"), which checks the balance again. The menu's orders sheet (user 2026-11-11) lists the classes as rows
-- (Config/Classes.List: rune, name, blurb, price and its note; picked filled with ink, locked or not affordable faded with
-- the Marks you're short), the match currency (shown only here, user: "they only see their match currency in the loadout menu
-- when they are respawning"), and the soldier you'll spawn as, turning slowly: the server's "LoadoutPreview" rig in a
-- ViewportFrame, playing its primary's ready hold. Deploy lights up once the respawn delay is over (Net "Loadout").
-- Layout, sizes and the one basic font come from src/shared/ui/TitleScreen.json and LoadoutMenu.json (the local
-- layout check and preview read the same files); offsets are reference pixels, scaled here by the GUI height. Colours:
-- Config/Palette UI.Settings, or the palette a spec's theme names (the title screen: UI.Grimoire, the UI overhaul's
-- Field Grimoire, user 2026-10-30; its ink drawing is src/client/Ink, its live map src/client/SketchMap). No
-- CanvasGroup: every element sets its own transparency.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Classes = require(Shared.Config.Classes)
local BotCfg = require(Shared.Config.Bots)
local FrontCfg = require(Shared.Config.Frontline)
local FrontRules = require(Shared.Rules.Frontline)
local Locomotion = require(Shared.Config.Locomotion)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local W = require(Shared.Config.Weapons)
local MovementSet = require(Shared.Rules.MovementSet)
local Net = require(Shared.Net)
local TitleSpec = require(Shared.ui.TitleScreen) :: any
local LoadoutSpec = require(Shared.ui.LoadoutMenu) :: any
local JoinSpec = require(Shared.ui.JoinLoading) :: any
local JoinCfg = require(Shared.Config.JoinLoading)
local JoinRules = require(Shared.Rules.JoinLoading)
local MapLoader = require(script.Parent.MapLoader)
local SketchCfg = require(Shared.Config.SketchMap) :: any
local Ink = require(script.Parent.Ink)
local MatchCam = require(script.Parent.MatchCam)
local SettingsMenu = require(script.Parent.SettingsMenu)
local SquadPanel = require(script.Parent.SquadPanel)
local Squad = require(script.Parent.Squad)
local SquadCfg = require(Shared.Config.Squads)
local SketchMap = require(script.Parent.SketchMap)
local DevPanel = require(script.Parent.DevPanel)
local ModesCfg = require(Shared.Config.Modes)
local Playtest = require(Shared.Config.Maps.Playtest)
local LiveMap = require(Shared.LiveMap)

local Menus = {}
-- set by src/client/EndScenes: the armory's cinematic behind the join's loading screen on (yields until its set
-- stands) or off
Menus.joinScene = nil :: ((boolean) -> ())?

-- (set by Menus.start: the title screen and the screen switch, for the join's loading screen)
local titleScreen: any = nil
local openScreen: (any) -> () = function(_: any) end
local joinGui: Instance? = nil
local localPlayer = Players.LocalPlayer

local C = Palette.UI.Settings :: any
local GR = (Palette.UI :: any).Grimoire
local function gcol(name: string): Color3
	local c = GR[name]
	return Color3.fromRGB(c[1], c[2], c[3])
end
local Anims = MovementSet.animations(Locomotion) :: any
local DEV_GAP = 16 -- reference pixels between the map and an open dev panel
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
	follow: { [string]: Frame }, -- a map node's FFA map, by the node's id
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
	local screen: Screen =
		{ gui = gui, node = {}, spec = {}, relayout = function() end, maps = {}, runes = {}, follow = {} }
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
			screen.maps[n.id] = SketchMap.new(obj, LiveMap.key(), { deploy = n.deploy, teammates = n.deploy })
			if n.follow then
				-- a second map, the zone-capture FFA's (only the zone on it), shown in place of the first in FFA
				local other = Instance.new("Frame")
				other.Name = n.id .. "FFA"
				other.BackgroundTransparency = 1
				other.AnchorPoint = Vector2.new(0.5, 0.5)
				other.Position = UDim2.fromScale(0.5, 0.5)
				other.Size = UDim2.fromScale(1, 1)
				other.Visible = false
				local shape = Instance.new("UIAspectRatioConstraint") -- its own image's shape inside the first's place
				local size = SketchCfg.Maps[Playtest.name].size
				shape.AspectRatio = size[1] / size[2]
				shape.Parent = other
				other.Parent = obj
				screen.maps[n.id .. "FFA"] = SketchMap.new(other, Playtest.name, { zone = true })
				screen.follow[n.id] = other
			end
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
			if n.kind == "overlay" then
				-- the screen is laid out under Roblox's top bar; a shade reaches up under it too (user 2026-10-31: "the
				-- shade overlay is not filling the whole screen")
				local inset = GuiService:GetGuiInset().Y
				obj.Position -= UDim2.fromOffset(0, inset)
				obj.Size += UDim2.fromOffset(0, inset)
			end
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
-- (the results screen is built the same way: src/client/Results)
Menus.build = build

function Menus.start()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")
	joinGui = playerGui
	local title = build(TitleSpec, "TitleScreen", playerGui)
	local loadout = build(LoadoutSpec, "LoadoutMenu", playerGui)
	-- a match cutscene or an end scene over the menus (src/client/MatchCutscene, src/client/EndScenes): their contents
	-- hidden meanwhile, the menus otherwise as they are (open or not, the menu camera running under the cut)
	function Menus.cover(on: boolean)
		for screen, spec in { [title] = TitleSpec, [loadout] = LoadoutSpec } do
			local root = screen.node[spec.root.id]
			if root then
				root.Visible = not on
			end
		end
	end
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
	-- one row of the orders sheet per class (user 2026-11-11): rune, name, blurb, price and the note under the price
	type Row = {
		button: TextButton,
		name: TextLabel,
		blurb: TextLabel,
		cost: TextLabel,
		note: TextLabel,
		rune: Ink.Canvas?,
		hover: boolean,
	}
	local rows: { [string]: Row } = {}
	local order: { string } = {}
	local PARTS = { name = "Name", blurb = "Blurb", cost = "Cost", note = "Note" }
	for i, key in Classes.List do
		local b = template:Clone() :: TextButton
		b.Name = "Row" .. key
		b.LayoutOrder = i
		b.BackgroundColor3 = gcol("ink")
		local r: any = { button = b, hover = false }
		for part, suffix in PARTS do
			r[part] = b:FindFirstChild("Rifleman" .. suffix) :: TextLabel
		end
		r.name.Text = Classes.Defs[key].name
		r.blurb.Text = Classes.Defs[key].blurb
		r.blurb.TextYAlignment = Enum.TextYAlignment.Top
		b.Parent = list
		local glyph = b:FindFirstChild("RiflemanRune") :: Frame?
		r.rune = glyph and Ink.canvas(glyph)
		rows[key] = r
		table.insert(order, key)
	end
	-- the copies follow the template's place, one step apart (scaled with the rest)
	local baseRelayout = loadout.relayout
	function loadout.relayout()
		baseRelayout()
		local base = template.Position
		for i, key in order do
			local b = rows[key].button
			local s = template.Size
			local k = s.Y.Offset / loadout.spec.RowRifleman.size[4]
			b.Size = s
			local step = (i - 1) * rowStep * k
			b.Position = UDim2.new(base.X.Scale, base.X.Offset, base.Y.Scale, base.Y.Offset)
				+ (if across then UDim2.fromOffset(step, 0) else UDim2.fromOffset(0, step))
			for _, suffix in { "Rune", "Rule" } do
				local own, tg =
					b:FindFirstChild("Rifleman" .. suffix) :: GuiObject?,
					template:FindFirstChild("Rifleman" .. suffix) :: GuiObject?
				if own and tg then
					own.Position, own.Size = tg.Position, tg.Size
				end
			end
			for part, suffix in PARTS do
				local cell = (rows[key] :: any)[part] :: TextLabel
				local t = template:FindFirstChild("Rifleman" .. suffix) :: TextLabel
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
	local fallback: string? = nil -- the class you'll deploy as instead of the picked one (render)
	local function render()
		if not state then
			return
		end
		local marks = L.Marks :: TextLabel
		marks.Text = `{Classes.Currency} {math.floor(state.points)}`
		local picked = state.picked
		local magic = GR.Magic[state.kit]
		for _, card in state.classes do
			local r = rows[card.key]
			if r then
				local can = not card.locked and card.affordable
				local on = card.key == picked
				-- the picked row filled with ink (paper words, the rune in the team's magic colour); one you can't take,
				-- faded, its price in red pencil with how many Marks you're short; the row under the mouse a faint ink
				local fade = if can or on then 0 else Cards.faded
				r.button.BackgroundTransparency = if on then 0 elseif r.hover and can then Cards.hover else 1
				r.name.TextColor3 = gcol(if on then "text" else "ink")
				r.blurb.TextColor3 = gcol(if on then "dim" else "inkDim")
				-- (picked but too dear: the server spawns you as the Rifleman, so the shortfall shows, amber on the ink)
				r.note.TextColor3 =
					gcol(if can then (if on then "dim" else "inkDim") elseif on then "amber" else "pencil")
				r.cost.TextColor3 = gcol(if on then "text" elseif can then "blue" else "pencil")
				r.name.TextTransparency, r.blurb.TextTransparency = fade, fade
				r.cost.TextTransparency, r.note.TextTransparency = 0, 0
				-- (user 2026-11-12: its unlock until unlocked this match, the first life included, then the fee each
				-- respawn) (in plain words: the big number is what this life costs, the note what it is made of)
				r.cost.Text = if card.locked then "Soon" elseif card.cost == 0 then "Free" else tostring(card.cost)
				local short = math.ceil(card.cost - state.points)
				local terms = if card.unlocked
					then `Unlocked · each life: {card.fee}`
					else `Unlock: {card.unlock}, first life free · then {card.fee} a life`
				local brief = if card.unlocked
					then `each life: {card.fee}`
					else `{card.unlock} to unlock, then {card.fee} a life`
				r.note.Text = if card.locked
					then "Not ready yet"
					elseif card.cost == 0 then "Always free"
					elseif not card.affordable and short > 0 then `{short} {Classes.Currency} short\n{brief}`
					else terms
				local runeName = Cards.runes[card.key]
				local canvas = r.rune
				if canvas and runeName then
					local colour = if on and magic then Color3.fromRGB(magic[1], magic[2], magic[3]) else gcol("blue")
					canvas.set(function(holder, w, h)
						Ink.rune(holder, runeName, 0, 0, w, h, math.max(1.5, h * 0.09), colour, fade)
					end)
				end
			end
		end
		local def = Classes.Defs[picked]
		local className = L.ClassName :: TextLabel
		className.Text = if def then def.name else ""
		-- (picked but too dear or not ready: the server spawns you as the Default class; the preview's name and Deploy
		-- say so, never a surprise)
		fallback = nil
		for _, card in state.classes do
			if card.key == picked and picked ~= Classes.Default and (card.locked or not card.affordable) then
				local d = Classes.Defs[Classes.Default]
				fallback = d and d.name
				if fallback and def then
					className.Text = `{fallback} · {def.name} needs more {Classes.Currency}`
				end
			end
		end
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
	-- the bots on team `kit`'s side in a Normal match (src/server/Bots), nil elsewhere
	local function botsOn(kit: string): number?
		local pair = FrontRules.parsePair(workspace:GetAttribute(FrontCfg.TeamsAttribute))
		local side = FrontRules.sideOf(pair, kit)
		local f = workspace:FindFirstChild(BotCfg.Folder)
		if not side then
			return nil
		end
		local n = f and f:GetAttribute(BotCfg.SideAttribute .. side)
		return if type(n) == "number" then n else 0
	end
	-- team `kit`'s soldiers as a card or the caption shows them
	local function countText(t: any, kit: string): string
		local bots = botsOn(kit)
		return if bots then `{t.counts[kit] or 0} + {bots}` else `{t.counts[kit] or 0} / {t.room}`
	end
	-- each card's place in the spec (reference pixels), for laying out only the teams in play
	local cardX: { [string]: number } = {}
	local cardW = 1
	local function specNodes(n: any)
		for kit in cards do
			if n.id == "Card" .. nameOf(kit) then
				cardX[kit], cardW = n.pos[2], n.size[2]
			end
		end
		for _, c in n.children or {} do
			specNodes(c)
		end
	end
	specNodes(LoadoutSpec.root)
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
		-- only the teams in play, centred where the three sat
		local inPlay = {}
		for _, kit in U.Teams do
			if cards[kit] and table.find(t.list, kit) then
				table.insert(inPlay, kit)
			end
		end
		local slots = {}
		for _, kit in U.Teams do
			if cardX[kit] then
				table.insert(slots, cardX[kit])
			end
		end
		local step = if #slots > 1 then slots[2] - slots[1] else 0
		local left = (slots[1] or 0) + (#slots - #inPlay) * step / 2
		for kit, card in cards do
			local at = table.find(inPlay, kit)
			card.Visible = at ~= nil
			local k = card.Size.X.Offset / cardW -- (the screen's scale: Screen.relayout)
			if at then
				card.Position = UDim2.new(
					card.Position.X.Scale,
					(left + (at - 1) * step) * k,
					card.Position.Y.Scale,
					card.Position.Y.Offset
				)
			end
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
			count.Text = countText(t, kit)
			local stroke = card:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = rgb(if kit == armed then "selLine" else "line")
			end
		end
		teamNote.Text = if armed
			then `Click {nameOf(armed)} again to join: your Marks reset`
			else "Changing team resets your Marks"
	end
	local teamsRelayout = loadout.relayout
	function loadout.relayout()
		teamsRelayout()
		renderTeams() -- (the relayout puts every card back where the spec has it)
	end
	-- the Squad button (Config/Squads): your squad and its head count, or an invitation; opens the squad panel
	local squadButton = L.Squad :: TextButton
	local function squadWords(): string
		local own = Squad.mine()
		return if own then `Squad: {own.name} {#own.members} / {SquadCfg.Max}` else "Join a squad"
	end
	squadButton.Activated:Connect(function()
		SquadPanel.open()
	end)
	task.spawn(function()
		while true do
			if loadout.gui.Enabled then
				squadButton.Visible = Squad.team() ~= nil
				local words = squadButton:FindFirstChild("Words") :: TextLabel?
				local text = squadWords()
				squadButton.Text = text
				if words then
					words.Text = text
				end
			end
			task.wait(SquadCfg.Panel.Refresh)
		end
	end)
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
	titleScreen, openScreen = title, open

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
		r.button.MouseEnter:Connect(function()
			r.hover = true
			render()
		end)
		r.button.MouseLeave:Connect(function()
			r.hover = false
			render()
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
				if c and table.find(t.list, kit) then
					table.insert(parts, `{nameOf(kit)} {countText(t, kit)}`)
				end
			end
		end
		caption.Text = table.concat(parts, " · ")
	end

	-- the bots come and go without a new state: their counts on the cards kept up once a second
	task.spawn(function()
		while true do
			task.wait(1)
			if loadout.gui.Enabled and cardsOpen then
				renderTeams()
			end
		end
	end)

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
	local function deployWord(): string
		return if fallback then `Deploy as {fallback}` else "Deploy"
	end
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
	-- the match moved to another map (the vote's pick): the menus' maps are drawn again for it
	workspace:GetAttributeChangedSignal(FrontCfg.MapAttribute):Connect(function()
		local key = LiveMap.key()
		if not SketchCfg.Maps[key] then
			return
		end
		for _, screen in { title, loadout } do
			local old, n = screen.maps.Map, screen.spec.Map
			if old and n then
				old.destroy()
				screen.maps.Map = SketchMap.new(screen.node.Map, key, { deploy = n.deploy, teammates = n.deploy })
			end
		end
		titleMap, loadoutMap = title.maps.Map, loadout.maps.Map
	end)
	local loadoutCaption = L.Caption :: TextLabel
	-- the maps follow the live mode: the zone-capture FFA's map in place of Map 1 (its own image under the first's)
	local function follow(screen: Screen)
		local ffa = workspace:GetAttribute(ModesCfg.Attribute) == "FFA"
		for id, other in screen.follow do
			other.Visible = ffa
			local first = screen.node[id]:FindFirstChild("SketchMap") :: GuiObject?
			if first then
				first.Visible = not ffa
			end
		end
	end
	-- a dev panel open on the right (src/client/DevPanel, 260 px wide at 12 from the edge) pushes the map left of it
	local function clearDevPanels(screen: Screen)
		local holder = screen.node.MapHolder
		local n = screen.spec.MapHolder
		if not holder or not n then
			return
		end
		local s = holder.Size.Y.Offset / n.size[4]
		local parent = holder.Parent :: GuiObject
		-- the map's right edge where it stands with no panel open (anchored at its right)
		local right = parent.AbsolutePosition.X + parent.AbsoluteSize.X * n.pos[1] + n.pos[2] * s
		local push = 0
		for _, name in DevPanel.Panels do
			local g = playerGui:FindFirstChild(name) :: ScreenGui?
			local panel = g and g.Enabled and g:FindFirstChild("Panel") :: GuiObject?
			if panel and panel.Visible and name ~= "SettingsMenu" then
				push = math.max(push, right - panel.AbsolutePosition.X + DEV_GAP * s)
			end
		end
		holder.Position = UDim2.new(n.pos[1], n.pos[2] * s - push, n.pos[3], n.pos[4] * s)
	end
	RunService.RenderStepped:Connect(function()
		if title.gui.Enabled then
			clearDevPanels(title)
		end
		if loadout.gui.Enabled then
			clearDevPanels(loadout)
		end
		if title.gui.Enabled then
			follow(title)
			writeCaption()
		end
		if loadout.gui.Enabled then
			follow(loadout)
		end
		if loadout.gui.Enabled and loadoutMap then
			loadoutMap.deploy(state and state.kit)
			local at = loadoutMap.deployName()
			loadoutCaption.Text = if at then `You deploy at {at}` else ""
		end
		if loadout.gui.Enabled then
			local left = deployAt - os.clock()
			-- a Normal match's next wave (src/server/Frontline; user 2026-10-31: the countdown on the Deploy button)
			local front = workspace:FindFirstChild(FrontCfg.FolderName)
			local waveAt = front and front:GetAttribute(FrontCfg.WaveAttribute)
			if type(waveAt) == "number" then
				if left > 0 then
					setDeploy(`Ready in {math.ceil(left)}`, false)
				else
					local wave = math.max(math.ceil(waveAt - workspace:GetServerTimeNow()), 0)
					setDeploy(`{if fallback then `As {fallback}` else "Deploy"} · wave in {wave}`, true)
				end
			elseif left > 0 then
				setDeploy(`Deploy in {math.ceil(left)}`, false)
			else
				setDeploy(deployWord(), true)
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

	-- the join (user 2026-11-04: "require all players to go through the runenkrieg loading screen while the cinematic
	-- loading screen loads ... keep the runenkrieg words over [it]"): the RUNENKRIEG words and the load's progress over
	-- the armory's cinematic (src/client/EndScenes, Menus.joinScene) while the whole current map loads (src/client/
	-- MapLoader). No skip: only once it's loaded does the title screen open (its Play and Settings appear under the same
	-- words), the cinematic still behind it until the title closes (unless a soldier is already out, e.g. a respawn from
	-- the dev tools). Between matches there is none (the armory loads the next map, src/client/MatchCutscene).
	if player.Character then
		state = { alive = true }
	else
		Net.event("Loadout"):FireServer("Ask") -- (the team line and the preview get ready meanwhile)
		Menus.replayJoin(true)
	end
end

-- The join's loading screen (above; the admin's "Replay the join load" too: `first` false, the map loaded again from
-- the start and the title screen only if no soldier is out).
local joinOpen = false
-- The join's loading screen is up (src/client/EndScenes: the end scenes wait for it, not for the title screen).
function Menus.joinLoading(): boolean
	return joinOpen
end

function Menus.replayJoin(first: boolean?)
	if joinOpen then
		return
	end
	joinOpen = true
	local loading = build(JoinSpec, "JoinLoading", joinGui :: Instance)
	loading.gui.DisplayOrder = DISPLAY_ORDER + 1
	loading.gui.Enabled = true
	loading.relayout()
	local status = loading.node.Status :: TextLabel
	status.Text = JoinRules.status(0)
	-- black until the cinematic's set stands, then it fades to the shade under the words
	local curtain = Instance.new("Frame")
	curtain.Name = "Curtain"
	curtain.BackgroundColor3 = Color3.new(0, 0, 0)
	curtain.BorderSizePixel = 0
	curtain.Position = UDim2.fromOffset(0, -GuiService:GetGuiInset().Y)
	curtain.Size = UDim2.new(1, 0, 1, GuiService:GetGuiInset().Y)
	curtain.ZIndex = 0
	curtain.Parent = loading.gui
	if first then
		MatchCam.start() -- (the menus' camera out, until the cinematic takes the camera)
	end
	task.spawn(function()
		while not Menus.joinScene do -- (set by src/client/EndScenes once it has started)
			task.wait()
		end
		Menus.joinScene(true) -- (yields until its set stands and is preloaded)
		TweenService:Create(curtain, TweenInfo.new(JoinCfg.Reveal), { BackgroundTransparency = 1 }):Play()
	end)
	local key = LiveMap.key()
	local load = MapLoader.load(key)
	if not first and load.finished then
		MapLoader.forget()
		load = MapLoader.load(key)
	end
	local conn = MapLoader.changed:Connect(function()
		status.Text = JoinRules.status(MapLoader.progress())
	end)
	task.spawn(function()
		while not load.finished do
			if MapLoader.state() ~= load then -- (another map asked for meanwhile: load what's live now)
				load = MapLoader.load(LiveMap.key())
			end
			task.wait(0.1)
		end
		conn:Disconnect()
		status.Text = JoinRules.status(1)
		task.wait(JoinCfg.Hold)
		loading.gui:Destroy()
		joinOpen = false
		local function done()
			if Menus.joinScene then
				Menus.joinScene(false)
			end
		end
		if localPlayer.Character or not titleScreen then
			done()
			return
		end
		openScreen(titleScreen)
		-- the cinematic stays behind the title screen until it closes (Play opens the loadout over the live match)
		local c: RBXScriptConnection
		c = titleScreen.gui:GetPropertyChangedSignal("Enabled"):Connect(function()
			if not titleScreen.gui.Enabled then
				c:Disconnect()
				done()
			end
		end)
	end)
end

return Menus
