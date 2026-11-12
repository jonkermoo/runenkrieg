--!strict
-- The game modes' top bar (src/shared/ui/ModeHud.json, Config/ModeHud, Rules/ModeHud; user 2026-10-29, option B of
-- the mode HUD drafts, the front bar). Built once from the spec; each Refresh it reads the live mode's replicated state:
--   Territory Push: Workspace's Frontline folder (src/server/Frontline: West / East teams, Phase, Winner; a child
--     folder per sector with Index, Owner, Control and the West / East soldiers in its zone). The viewer's side is on
--     the left; one diamond per sector joined by a line, filled as far as its control goes in the colour of the side it
--     leans to. Shown on the loadout screen; in play only while M is held, fading fast, with a dot over each teammate
--     seen through walls (user 2026-10-29: "make the bar appear and a dot above all teammates that you can see through
--     walls appear (with a fast fade) when players hold v"), and a diamond over each point that can be taken now, its
--     fill the bar's (user 2026-10-30: "show where the point is when you hold v", "only show the ones that arent
--     locked"). Only the viewer's own nation is named (the enemy's flag dropped, user 2026-10-30).
--   Point Capture (the server's Mode is FFA): the zone marker on the Playtest map (src/server/ZoneMatch: Phase,
--     EndsAt, State, Holder, Leader, MoveAt, NextSpot, Winner) and the leader's ZoneScore: the clock centred, the point
--     leader under it, the zone's state, the move warning (user 2026-10-29: "center the timer and remove the bar
--     completely ... remove the top score and your score. just keep track of the score leader and display it"). The
--     leader's glow is the server's (src/server/ZoneMatch, Config/ZoneMatch.Leader).
-- Hidden when neither runs, and on the title screen ("dont show the status of the game until players are on or past
-- the loadout screen"; src/client/Menus' TitleScreen and LoadoutMenu).
-- UI overhaul (user 2026-10-30: "lets do the sketch map", "maps top left"): in Territory Push the sketch map
-- (src/client/SketchMap, Config/SketchMap.Hud) stands top left in play while M is held (in Point Capture too: the
-- Playtest map with only you and the zone, user 2026-10-30: "make the hold v to show map appear for FFA mode ... just
-- have your player and the moving point") (user 2026-10-30: "make the map
-- appear with V too when in game"), with the soldier as a red pencil arrow and the teammate dots and the open points'
-- markers, in place of the front bar; the bar shows only for the result at the match's end.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.ModeHud)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local BotsCfg = require(Shared.Config.Bots)
local ModesCfg = require(Shared.Config.Modes)
local Palette = require(Shared.Config.Palette)
local SketchCfg = require(Shared.Config.SketchMap) :: any
local FrontlineCfg = require(Shared.Config.Frontline)
local SketchMap = require(script.Parent.SketchMap)
local U = require(Shared.Config.Uniforms)
local LiveMap = require(Shared.LiveMap)
local PointSeal = require(script.Parent.PointSeal)
local Settings = require(script.Parent.Settings)
local Playtest = require(Shared.Config.Maps.Playtest)
local Rules = require(Shared.Rules.ModeHud)
local ZoneRules = require(Shared.Rules.ZoneMatch)
local FrontRules = require(Shared.Rules.Frontline)
local PoleCfg = require(Shared.Config.Flagpole)
local Spec = require(Shared.ui.ModeHud) :: any

local ModeHud = {}

local C = Palette.UI.Hud :: any
local T = Spec.theme
local FONT = Font.new(`rbxasset://fonts/families/{T.fonts.body.family}.json`, Enum.FontWeight.Bold)
local ALIGN = { left = Enum.TextXAlignment.Left, right = Enum.TextXAlignment.Right }
local DIAG = math.sqrt(0.5) -- a diamond's side in its box (the square turned 45 degrees fits the box)
-- a diamond's fill runs up the screen: the gradient turned against the square's own 45 degrees
local FILL_ROTATION = 225

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local function tok(name: string): Color3
	return rgb(C[name])
end

local function udim(a: { number }): UDim2
	return UDim2.new(a[1], a[2], a[3], a[4])
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

-- a sector's id -> its map entry (isHQ), on the match's map (src/shared/LiveMap: the vote can move the match)
local function sectorOf(id: string): any
	for _, s in LiveMap.map.sectors do
		if s.id == id then
			return s
		end
	end
	return nil
end

type Diamond = { box: Frame, face: Frame, grad: UIGradient, edge: UIStroke }

local gui: ScreenGui
local nodes: { [string]: GuiObject } = {}
local binds: { [string]: TextLabel } = {}
local frontPins: { Diamond } = {}
local frontLabels: { TextLabel } = {}

-- One spec node (and its children) as an instance; templates (Pin, PinHQ, PinLabel) are kept unparented.
local function make(n: any, parent: Instance?): GuiObject
	local obj: GuiObject
	if n.kind == "label" then
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Text = n.text or ""
		l.FontFace = FONT
		l.TextSize = n.textSize
		l.TextColor3 = tok(n.textColor)
		l.TextXAlignment = ALIGN[n.align] or Enum.TextXAlignment.Center
		if n.stroke then
			l.TextStrokeColor3 = tok(n.stroke)
			l.TextStrokeTransparency = 0.4
		end
		if n.bind then
			binds[n.bind] = l
		end
		obj = l
	elseif n.kind == "image" then
		local i = Instance.new("ImageLabel")
		i.BackgroundTransparency = 1
		i.ScaleType = Enum.ScaleType.Crop
		obj = i
	elseif n.kind == "group" then
		-- (a group that fades as one is a CanvasGroup)
		local g: GuiObject = if n.fade then Instance.new("CanvasGroup") else Instance.new("Frame")
		g.BackgroundTransparency = 1
		obj = g
	else -- panel (a diamond when shape = "diamond")
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		if n.shape == "diamond" then
			f.BackgroundTransparency = 1
		else
			f.BackgroundColor3 = tok(n.color)
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, T.corner)
			corner.Parent = f
		end
		obj = f
	end
	obj.Name = n.id
	obj.Position = udim(n.pos or { 0, 0, 0, 0 })
	obj.Size = udim(n.size or { 1, 0, 1, 0 })
	if n.anchor then
		obj.AnchorPoint = Vector2.new(n.anchor[1], n.anchor[2])
	end
	obj.ZIndex = if n.overlay then 4 else 2
	nodes[n.id] = obj
	for _, c in n.children or {} do
		make(c, obj)
	end
	obj.Parent = parent
	return obj
end

-- A diamond in a spec template's box: the turned square (face) with the theme's one outline, filled by a hard-edged
-- gradient from its bottom tip.
local function diamond(template: any, parent: Instance, x: number): Diamond
	local box = make(template, nil) :: Frame
	box.Position = UDim2.new(x, 0, box.Position.Y.Scale, box.Position.Y.Offset)
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.AnchorPoint = Vector2.new(0.5, 0.5)
	face.Position = UDim2.fromScale(0.5, 0.5)
	face.Size = UDim2.fromScale(DIAG, DIAG)
	face.Rotation = 45
	face.BorderSizePixel = 0
	face.BackgroundColor3 = Color3.new(1, 1, 1) -- (the gradient's colours tint it)
	face.ZIndex = box.ZIndex
	face.Parent = box
	local grad = Instance.new("UIGradient")
	grad.Rotation = FILL_ROTATION
	grad.Color = ColorSequence.new(tok("pinEmpty"))
	grad.Parent = face
	local edge = Instance.new("UIStroke")
	edge.Thickness = T.outline
	edge.Color = tok("pinEdge")
	edge.Parent = face
	box.Parent = parent
	return { box = box, face = face, grad = grad, edge = edge }
end

-- The diamond filled to `share` (0..1, from the bottom tip) in `color`, the rest empty.
local function fillDiamond(d: Diamond, share: number, color: Color3)
	local empty = tok("pinEmpty")
	local seq
	if share <= Cfg.Fill.min then
		seq = ColorSequence.new(empty)
	elseif share >= 1 - Cfg.Fill.min then
		seq = ColorSequence.new(color)
	else
		local e = Cfg.Fill.edge
		seq = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(share - e, color),
			ColorSequenceKeypoint.new(share, empty),
			ColorSequenceKeypoint.new(1, empty),
		})
	end
	d.grad.Color = seq
end

local function set(bind: string, text: string)
	local l = binds[bind]
	if l and l.Text ~= text then
		l.Text = text
	end
end

local function teamRim(kit: string?): Color3
	local t = kit and C.Teams[kit]
	return if t then rgb(t.rim) else tok("pinEmpty")
end

local function nation(kit: string?): string
	local k = kit and U.Kits[kit]
	return if k then string.upper(k.team) else ""
end

local function flagImage(kit: string?): string
	local k = kit and U.Kits[kit]
	return if k and k.flag then `rbxassetid://{k.flag.pole}` else ""
end

local function mySide(folder: Instance): string?
	local character = Players.LocalPlayer.Character
	local kit = character and character:GetAttribute("Kit")
	if kit == nil then
		return nil
	end
	if kit == folder:GetAttribute("West") then
		return "West"
	elseif kit == folder:GetAttribute("East") then
		return "East"
	end
	return nil
end

-- the sector folders west to east
local function sectorsOf(folder: Instance): { Instance }
	local list = folder:GetChildren()
	table.sort(list, function(a, b)
		return ((a:GetAttribute("Index") :: number?) or 0) < ((b:GetAttribute("Index") :: number?) or 0)
	end)
	return list
end

-- (re)builds the diamonds and labels for `n` sectors, evenly spaced along the bar, the line from the first to the last
local function layoutPins(list: { Instance })
	for _, d in frontPins do
		d.box:Destroy()
	end
	for _, l in frontLabels do
		l:Destroy()
	end
	table.clear(frontPins)
	table.clear(frontLabels)
	local bar = nodes.FrontBar
	local n = #list
	for slot = 1, n do
		local x = (slot - 0.5) / n
		table.insert(frontPins, diamond(find(Spec.root, "Pin"), bar, x))
		local label = make(find(Spec.root, "PinLabel"), nil) :: TextLabel
		binds.pin = nil -- (each clone is set directly)
		label.Position = UDim2.new(x, 0, label.Position.Y.Scale, label.Position.Y.Offset)
		label.Parent = bar
		table.insert(frontLabels, label)
	end
	local line = nodes.Line
	local ends = if n > 0 then 0.5 / n else 0.5
	line.Position = UDim2.new(ends, 0, line.Position.Y.Scale, line.Position.Y.Offset)
	line.Size = UDim2.new(1 - 2 * ends, 0, line.Size.Y.Scale, line.Size.Y.Offset)
end

local shownCount = -1
local shownSide: string? = "?"

-- a diamond painted as its sector stands: filled toward the side its control leans to, its edge contested / attacked
local function paint(d: Diamond, pin: Rules.Pin, west: string?, east: string?, flashOn: boolean)
	local kit = if pin.fillSide == "West" then west elseif pin.fillSide == "East" then east else nil
	fillDiamond(d, pin.fill, teamRim(kit))
	d.edge.Color = if pin.state == "Contested"
		then (if flashOn then tok("pinContested") else tok("pinEdge"))
		elseif pin.state == "Attacked" then tok("pinAttacked")
		else tok("pinEdge")
end

-- Territory Push: the points that can be taken now, marked in the world over their flagpole (src/server/Flagpoles), seen
-- through walls: the point's seal as the sketch map draws it (src/client/PointSeal; user 2026-11-02: "make the flag
-- beacons match its symbol on the map"), its map name under it, and a thin bar of its capture (the side it leans to)
type Marker = { gui: BillboardGui, group: CanvasGroup, seal: PointSeal.Seal, label: TextLabel, fill: Frame }
local markers: { [string]: Marker } = {}

-- the pole standing on sector `id` now (src/server/Flagpoles stands them again for each map: every map's points share
-- the ids S1..S5)
local function poleOf(id: string): BasePart?
	local poles = workspace:FindFirstChild(PoleCfg.FolderName)
	local model = poles and poles:FindFirstChild(id)
	return model and (model :: Model).PrimaryPart
end

local function newMarker(pole: BasePart, text: string, rune: string): Marker
	local M = Cfg.Marker
	local g = Instance.new("BillboardGui")
	g.Name = "ModeHudPoint"
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.ResetOnSpawn = false
	g.Size = UDim2.fromOffset(M.size[1], M.size[2])
	g.Adornee = pole
	g.StudsOffsetWorldSpace = Vector3.new(0, pole.Size.Y / 2 + M.above, 0)
	g.Enabled = false
	-- (one group, so the whole beacon fades with the M key)
	local group = Instance.new("CanvasGroup")
	group.BackgroundTransparency = 1
	group.Size = UDim2.fromScale(1, 1)
	group.Parent = g
	local G = (Palette.UI :: any).Grimoire
	local disc = Instance.new("Frame")
	disc.Name = "Seal"
	disc.AnchorPoint = Vector2.new(0.5, 0)
	disc.Position = UDim2.new(0.5, 0, 0, M.ring)
	disc.Size = UDim2.fromOffset(M.seal, M.seal)
	disc.Parent = group
	local seal = PointSeal.new(disc, rune, rgb(G.ink), rgb(G.neutral))
	seal.ring.Thickness = M.ring
	local label = make(find(Spec.root, "PinLabel"), nil) :: TextLabel
	binds.pin = nil -- (set directly)
	label.Text = text
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, M.seal + 2 * M.ring)
	label.Parent = group
	local track = Instance.new("Frame")
	track.Name = "Capture"
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.fromScale(0.5, 1)
	track.Size = UDim2.fromOffset(M.bar[1], M.bar[2])
	track.BackgroundColor3 = rgb(G.ink)
	track.BorderSizePixel = 0
	track.Parent = group
	local fill = Instance.new("Frame")
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	g.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	return { gui = g, group = group, seal = seal, label = label, fill = fill }
end

-- a beacon now: the seal in its holder's colours (contested: the beat), its capture bar as far as the control goes, in
-- the colour of the side it leans to
local function paintMarker(m: Marker, pin: Rules.Pin, owner: string?, west: string?, east: string?, now: number)
	local holder = if owner == "West" then west elseif owner == "East" then east else nil
	PointSeal.paint(m.seal, PointSeal.colours(holder, pin.state == "Contested", now))
	local kit = if pin.fillSide == "West" then west elseif pin.fillSide == "East" then east else nil
	m.fill.Size = UDim2.fromScale(math.clamp(pin.fill, 0, 1), 1)
	m.fill.BackgroundColor3 = teamRim(kit)
end

local function showMarkers(shown: number)
	for _, m in markers do
		m.gui.Enabled = shown > 0
		m.group.GroupTransparency = 1 - shown
	end
end

local function clearMarkers()
	for id, m in markers do
		m.gui:Destroy()
		markers[id] = nil
	end
end

local function updateFront(folder: Instance, now: number)
	local side = mySide(folder)
	local list = sectorsOf(folder)
	local n = #list
	if n ~= shownCount then
		layoutPins(list)
		shownCount = n
		shownSide = "?"
	end
	local west, east = folder:GetAttribute("West") :: string?, folder:GetAttribute("East") :: string?
	-- (only the viewer's own nation: user 2026-10-30, the enemy's flag not shown)
	local leftKit = if side == "East" then east else west
	if side ~= shownSide then
		shownSide = side
		set("leftName", nation(leftKit))
		local leftFlag = nodes.LeftFlag :: ImageLabel
		leftFlag.Image = flagImage(leftKit)
	end
	local flashOn = (now // Cfg.FlashSeconds) % 2 == 0
	-- the points that can be taken now (either side's next: Rules/Frontline.target), marked in the world
	local state = { owner = {}, control = {} }
	for i, f in list do
		state.owner[i] = (f:GetAttribute("Owner") :: string?) or "Neutral"
		state.control[i] = (f:GetAttribute("Control") :: number?) or 0
	end
	local open: { [string]: boolean } = {}
	if folder:GetAttribute("Phase") == "Playing" then
		for _, s in { "West", "East" } do
			local t = FrontRules.target(state, s)
			if t then
				open[list[t].Name] = true
			end
		end
	end
	for slot = 1, n do
		local f = list[Rules.slot(slot, n, side)]
		local d = frontPins[slot]
		local s = sectorOf(f.Name)
		local hq = s ~= nil and s.isHQ == true
		local tmpl = find(Spec.root, if hq then "PinHQ" else "Pin")
		d.box.Size = udim(tmpl.size)
		local label = if hq then "HQ" else f.Name
		frontLabels[slot].Text = label
		local pin = Rules.pin(
			f:GetAttribute("Owner") :: string?,
			(f:GetAttribute("Control") :: number?) or 0,
			(f:GetAttribute("West") :: number?) or 0,
			(f:GetAttribute("East") :: number?) or 0
		)
		paint(d, pin, west, east, flashOn)
		local m = markers[f.Name]
		local pole = poleOf(f.Name)
		-- (a beacon over a pole that's gone, the match moved to another map or the poles stood again, is built anew on
		-- the new one; a pole not standing yet is looked for again next frame)
		if m and (not open[f.Name] or m.gui.Adornee ~= pole) then
			m.gui:Destroy()
			markers[f.Name] = nil
			m = nil
		end
		if open[f.Name] and pole then
			local index = (f:GetAttribute("Index") :: number?) or slot
			m = m or newMarker(pole, if s then s.name else f.Name, PointSeal.rune(index, n))
			markers[f.Name] = m
			paintMarker(m :: Marker, pin, f:GetAttribute("Owner") :: string?, west, east, now)
		end
	end
	if folder:GetAttribute("Phase") == "Results" then
		local winner = folder:GetAttribute("Winner") :: string?
		local kit = if winner == "West" then west elseif winner == "East" then east else nil
		set("result", if kit then `{nation(kit)} WINS` else Cfg.NoWinner)
	else
		set("result", "")
	end
end

-- a soldier's name and zone score by id: a player's, or a bot's from the bots' folder (src/server/Bots, ZoneMatch)
local function soldier(id: number?): (string?, number)
	if id == nil then
		return nil, 0
	end
	if id < 0 then
		local f = workspace:FindFirstChild(BotsCfg.Folder)
		local name = f and f:GetAttribute(BotsCfg.NameAttribute .. tostring(-id))
		local s = f and f:GetAttribute(BotsCfg.ScoreAttribute .. tostring(-id))
		return if type(name) == "string" then name else nil, math.floor((if type(s) == "number" then s else 0) + 1e-6)
	end
	local p = Players:GetPlayerByUserId(id)
	return p and p.DisplayName, p and math.floor(((p:GetAttribute(ZoneCfg.ScoreAttribute) :: number?) or 0) + 1e-6) or 0
end

local function updateZone(zone: Instance)
	local me = Players.LocalPlayer
	local serverNow = workspace:GetServerTimeNow()
	local results = zone:GetAttribute("Phase") == "Results"
	set("clock", ZoneRules.clock(((zone:GetAttribute("EndsAt") :: number?) or serverNow) - serverNow))
	-- the point leader (the winner during the results): "You" on their own screen
	local id = zone:GetAttribute(if results then "Winner" else ZoneCfg.LeaderAttribute) :: number?
	local name, score = soldier(id)
	set("leader", Rules.leaderLine(name, id ~= nil and id == me.UserId, score, results))
	if results then
		set("zone", "")
		set("warning", "")
	else
		local state = zone:GetAttribute("State") :: string?
		local holder = zone:GetAttribute("Holder") :: number?
		set("zone", Rules.zoneLine(state, holder == me.UserId, (soldier(holder))))
		local moveAt = zone:GetAttribute("MoveAt") :: number?
		set(
			"warning",
			if zone:GetAttribute("NextSpot") ~= nil and moveAt
				then string.format(Cfg.Warning, math.max(0, math.ceil(moveAt - serverNow)))
				else ""
		)
	end
end

-- Territory Push: a dot over each teammate's head, drawn on top of the world so it shows through walls
type Dot = { gui: BillboardGui, face: Frame, edge: UIStroke }
local dots: { [Instance]: Dot } = {} -- (by player, or by bot model)

local function newDot(): Dot
	local d = Cfg.Dot
	local g = Instance.new("BillboardGui")
	g.Name = "ModeHudTeamDot"
	g.AlwaysOnTop = true
	g.LightInfluence = 0
	g.ResetOnSpawn = false
	g.Size = UDim2.fromOffset(d.size, d.size)
	g.StudsOffset = Vector3.new(0, d.above, 0)
	g.Enabled = false
	local face = Instance.new("Frame")
	face.Size = UDim2.fromScale(1, 1)
	face.BorderSizePixel = 0
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = face
	local edge = Instance.new("UIStroke")
	edge.Thickness = T.outline
	edge.Color = tok("pinEdge")
	edge.Parent = face
	face.Parent = g
	g.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	return { gui = g, face = face, edge = edge }
end

-- each teammate (a soldier of the viewer's kit: players and bot soldiers, src/server/Bots) gets a dot on their head;
-- the others' go
local function updateDots(kit: string?)
	local me = Players.LocalPlayer
	local function mark(key: Instance, character: Model?)
		local head = character and character:FindFirstChild("Head")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local mate = kit ~= nil
			and head ~= nil
			and humanoid ~= nil
			and humanoid.Health > 0
			and (character :: Model):GetAttribute("Kit") == kit
		local dot = dots[key]
		if mate then
			dot = dot or newDot()
			dots[key] = dot
			dot.gui.Adornee = head :: BasePart
			dot.face.BackgroundColor3 = teamRim(kit :: string)
		elseif dot then
			dot.gui:Destroy()
			dots[key] = nil
		end
	end
	for _, p in Players:GetPlayers() do
		if p ~= me then
			mark(p, p.Character)
		end
	end
	for _, m in CollectionService:GetTagged(BotsCfg.Tag) do
		if m:IsA("Model") then
			mark(m, m)
		end
	end
	for key, dot in dots do
		if key.Parent == nil then
			dot.gui:Destroy()
			dots[key] = nil
		end
	end
end

local function showDots(shown: number)
	local d = Cfg.Dot
	local eye = workspace.CurrentCamera.CFrame.Position
	for _, dot in dots do
		local head = dot.gui.Adornee
		if shown > 0 and head and head:IsA("BasePart") then
			local px = Rules.dotSize((head.Position - eye).Magnitude, d.size, d.near, d.min)
			dot.gui.Size = UDim2.fromOffset(px, px)
		end
		dot.gui.Enabled = shown > 0
		dot.face.BackgroundTransparency = 1 - shown
		dot.edge.Transparency = 1 - shown
	end
end

function ModeHud.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "ModeHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false -- (laid out under the top bar, as tools/ui/check.py does)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	make(Spec.root, gui)
	-- the templates come out of the tree: the code places its own
	for _, id in { "Pin", "PinHQ", "PinLabel" } do
		nodes[id]:Destroy()
		nodes[id] = nil :: any
	end
	binds.pin = nil
	-- one UIScale per panel (a panel scales about its own anchor; on the full-screen Root it shrank everything toward
	-- the top-left, pulling the bars off centre)
	-- the sketch map, top left (its size in reference pixels; the image's aspect)
	local H = SketchCfg.Hud
	local mapBox = Instance.new("Frame")
	mapBox.Name = "SketchMap"
	mapBox.BackgroundTransparency = 1
	mapBox.Position = UDim2.fromOffset(H.x, H.y)
	local function tall(key: string): number
		local size = SketchCfg.Maps[key].size
		return H.width * size[2] / size[1]
	end
	mapBox.Size = UDim2.fromOffset(H.width, tall(FrontlineCfg.MapKey))
	mapBox.Visible = false
	mapBox.Parent = gui
	-- one sheet per frontline map with sketch art, the match's map shown (the vote can move the match)
	local sheets: { [string]: Frame } = {}
	for _, key in LiveMap.frontline() do
		if SketchCfg.Maps[key] then
			local sheet = Instance.new("Frame")
			sheet.Name = key
			sheet.BackgroundTransparency = 1
			sheet.Size = UDim2.fromScale(1, 1)
			sheet.Parent = mapBox
			SketchMap.new(sheet, key, { you = true, teammates = true })
			sheets[key] = sheet
		end
	end
	local function showSheet()
		local live = LiveMap.key()
		for key, sheet in sheets do
			sheet.Visible = key == live
		end
		if sheets[live] then
			mapBox.Size = UDim2.fromOffset(H.width, tall(live))
		end
	end
	showSheet()
	workspace:GetAttributeChangedSignal(FrontlineCfg.MapAttribute):Connect(showSheet)
	nodes.SketchMap = mapBox
	local ffaBox = mapBox:Clone()
	ffaBox.Name = "SketchMapFFA"
	ffaBox:ClearAllChildren()
	ffaBox.Size = UDim2.fromOffset(H.width, tall(Playtest.name))
	ffaBox.Parent = gui
	SketchMap.new(ffaBox, Playtest.name, { you = true, zone = true })
	nodes.SketchMapFFA = ffaBox
	local scales: { [UIScale]: boolean } = {} -- (true: also by the HUD size setting)
	local barScale: UIScale? = nil -- the front bar's (smaller in play: Cfg.Strip)
	local screenK = 1
	-- the wave countdown, shown only while the soldier stands in its wave line
	nodes.WaveBar.Visible = false
	set("waveTitle", Cfg.Wave.title)
	for _, id in { "FrontBar", "ZoneBar", "WaveBar", "SketchMap", "SketchMapFFA" } do
		local scale = Instance.new("UIScale")
		scale.Parent = nodes[id]
		-- the map follows the HUD size setting too (user 2026-11-05: "can you make the map scale with the HUD size?";
		-- it grows from its top-left corner, so it stays in its place)
		scales[scale] = id == "SketchMap" or id == "SketchMapFFA"
		if id == "FrontBar" then
			barScale = scale
		end
	end
	local function rescale()
		local k = math.clamp(gui.AbsoluteSize.Y / T.scale.referenceHeight, T.scale.min, T.scale.max)
		screenK = k
		local size = tonumber(Settings.get("HudSize")) or 1
		for scale, sized in scales do
			scale.Scale = if sized then k * size else k
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	Settings.changed("HudSize", rescale)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	rescale()

	local playerGui = gui.Parent :: PlayerGui
	local function screenOn(name: string): boolean
		local g = playerGui:FindFirstChild(name)
		return g ~= nil and g:IsA("ScreenGui") and g.Enabled
	end

	local front = false -- Territory Push is running
	local results = false -- and showing its result
	local ffaOn = false -- Point Capture is running
	local myKit: string? = nil
	local barShown, dotsShown = 0, 0
	task.spawn(function()
		while true do
			local now = os.clock()
			local folder = workspace:FindFirstChild(Cfg.FrontlineFolder)
			local map = workspace:FindFirstChild(Playtest.name)
			local zone = map and map:FindFirstChild(ZoneCfg.MarkerName)
			-- (the match's cutscenes and end scenes hide the HUD: src/client/MatchCutscene, src/client/EndScenes)
			local title = screenOn("TitleScreen") or screenOn("MatchCutscene") or screenOn("EndScenes")
			local ffa = zone ~= nil and workspace:GetAttribute(ModesCfg.Attribute) == "FFA"
			ffaOn = ffa
			front = not ffa and folder ~= nil and folder:IsA("Folder")
			results = front and (folder :: Instance):GetAttribute("Phase") == "Results"
			nodes.ZoneBar.Visible = ffa and not title
			gui.Enabled = (front or ffa) and not title
			if front then
				updateFront(folder :: Instance, now)
				local character = Players.LocalPlayer.Character
				local side = mySide(folder :: Instance)
				myKit = if side and character then character:GetAttribute("Kit") :: string? else nil
			else
				myKit = nil
				clearMarkers()
				if ffa then
					updateZone(zone :: Instance)
				end
			end
			updateDots(myKit)
			task.wait(Cfg.Refresh)
		end
	end)
	-- the map, the dots and the markers while M is held in play; the bar only for the result
	RunService.RenderStepped:Connect(function(dt)
		local title, loadout = screenOn("TitleScreen"), screenOn("LoadoutMenu")
		local held = Settings.held("Key_Map")
		local inPlay = front and not title and not loadout
		-- the front bar: big for the result; in play always on as a smaller strip (review 2026-11-12: the objective
		-- only on M was backwards), off while the wave countdown stands in its place
		local character = Players.LocalPlayer.Character
		local waveAt = character and character:GetAttribute(FrontlineCfg.HoldAttribute)
		local waiting = front and not title and not loadout and type(waveAt) == "number"
		local strip = inPlay and not results and not waiting
		barShown = Rules.fade(
			barShown,
			if results and not title then 1 elseif strip then Cfg.Strip.shown else 0,
			dt,
			Cfg.FadeSeconds
		)
		if barScale then
			barScale.Scale = screenK * (if results then 1 else Cfg.Strip.scale)
		end
		nodes.SketchMap.Visible = inPlay and held
		nodes.SketchMapFFA.Visible = ffaOn and held and not title and not loadout
		dotsShown = Rules.fade(dotsShown, if inPlay and held then 1 else 0, dt, Cfg.FadeSeconds)
		local bar = nodes.FrontBar :: CanvasGroup
		bar.Visible = barShown > 0
		bar.GroupTransparency = 1 - barShown
		showDots(dotsShown)
		showMarkers(dotsShown)
		-- frozen in the wave line (src/server/Frontline's WaveHold: the wave's server time): the seconds until it goes
		nodes.WaveBar.Visible = waiting
		if waiting then
			set("waveClock", tostring(math.max(math.ceil((waveAt :: number) - workspace:GetServerTimeNow()), 0)))
		end
	end)
	-- FFA: the point leader's glow is for everyone else; on the leader's own screen it's off (kept from the old
	-- zone match readout, src/client/ZoneHud; the server turns it back on as the lead changes)
	local me = Players.LocalPlayer
	RunService.Heartbeat:Connect(function()
		local glow = me.Character and me.Character:FindFirstChild(ZoneCfg.Leader.name)
		if glow and glow:IsA("Highlight") and glow.Enabled then
			glow.Enabled = false
		end
	end)
end

return ModeHud
