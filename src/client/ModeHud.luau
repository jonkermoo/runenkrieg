--!strict
-- The game modes' top bar (src/shared/ui/ModeHud.json, Config/ModeHud, Rules/ModeHud; user 2026-10-29, option B of
-- the mode HUD drafts, the front bar). Built once from the spec; each Refresh it reads the live mode's replicated state:
--   Territory Push: Workspace's Frontline folder (src/server/Frontline: West / East teams, Phase, Winner; a child
--     folder per sector with Index, Owner, Control and the West / East soldiers in its zone). The viewer's side is on
--     the left; one diamond per sector joined by a line, filled as far as its control goes in the colour of the side it
--     leans to. Shown on the loadout screen; in play only while V is held, fading fast, with a dot over each teammate
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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.ModeHud)
local ZoneCfg = require(Shared.Config.ZoneMatch)
local ModesCfg = require(Shared.Config.Modes)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local Map1 = require(Shared.Config.Maps.Map1)
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

-- a sector's id -> its map entry (isHQ)
local SECTORS: { [string]: any } = {}
for _, s in Map1.sectors do
	SECTORS[s.id] = s
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
-- through walls: the bar's diamond and its label
type Marker = { gui: BillboardGui, diamond: Diamond, label: TextLabel }
local markers: { [string]: Marker } = {}

local function newMarker(id: string, text: string): Marker?
	local poles = workspace:FindFirstChild(PoleCfg.FolderName)
	local model = poles and poles:FindFirstChild(id)
	local pole = model and (model :: Model).PrimaryPart
	if not pole then
		return nil
	end
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
	local d = diamond(find(Spec.root, "PinHQ"), g, 0.5)
	d.box.AnchorPoint = Vector2.new(0.5, 0)
	d.box.Position = UDim2.fromScale(0.5, 0)
	local label = make(find(Spec.root, "PinLabel"), nil) :: TextLabel
	binds.pin = nil -- (set directly)
	label.Text = text
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 1)
	label.Parent = g
	g.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	return { gui = g, diamond = d, label = label }
end

local function showMarkers(shown: number)
	for _, m in markers do
		m.gui.Enabled = shown > 0
		m.diamond.face.BackgroundTransparency = 1 - shown
		m.diamond.edge.Transparency = 1 - shown
		m.label.TextTransparency = 1 - shown
		m.label.TextStrokeTransparency = 1 - shown * 0.6
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
		local s = SECTORS[f.Name]
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
		if open[f.Name] then
			m = m or newMarker(f.Name, label)
			if m then
				markers[f.Name] = m
				paint(m.diamond, pin, west, east, flashOn)
			end
		elseif m then
			m.gui:Destroy()
			markers[f.Name] = nil
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

local function updateZone(zone: Instance)
	local me = Players.LocalPlayer
	local serverNow = workspace:GetServerTimeNow()
	local results = zone:GetAttribute("Phase") == "Results"
	set("clock", ZoneRules.clock(((zone:GetAttribute("EndsAt") :: number?) or serverNow) - serverNow))
	-- the point leader (the winner during the results): "You" on their own screen
	local id = zone:GetAttribute(if results then "Winner" else ZoneCfg.LeaderAttribute) :: number?
	local p = id and Players:GetPlayerByUserId(id)
	local score = p and math.floor(((p:GetAttribute(ZoneCfg.ScoreAttribute) :: number?) or 0) + 1e-6) or 0
	set("leader", Rules.leaderLine(p and p.DisplayName, id ~= nil and id == me.UserId, score, results))
	if results then
		set("zone", "")
		set("warning", "")
	else
		local state = zone:GetAttribute("State") :: string?
		local holder = zone:GetAttribute("Holder") :: number?
		local holderPlayer = holder and Players:GetPlayerByUserId(holder)
		set("zone", Rules.zoneLine(state, holder == me.UserId, holderPlayer and holderPlayer.DisplayName))
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
local dots: { [Player]: Dot } = {}

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

-- each teammate (a soldier of the viewer's kit) gets a dot on their head; the others' go
local function updateDots(kit: string?)
	local me = Players.LocalPlayer
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local head = character and character:FindFirstChild("Head")
		local mate = kit ~= nil and p ~= me and head ~= nil and (character :: Model):GetAttribute("Kit") == kit
		local dot = dots[p]
		if mate then
			dot = dot or newDot()
			dots[p] = dot
			dot.gui.Adornee = head :: BasePart
			dot.face.BackgroundColor3 = teamRim(kit)
		elseif dot then
			dot.gui:Destroy()
			dots[p] = nil
		end
	end
	for p, dot in dots do
		if p.Parent == nil then
			dot.gui:Destroy()
			dots[p] = nil
		end
	end
end

local function showDots(shown: number)
	for _, dot in dots do
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
	local scales = {}
	for _, id in { "FrontBar", "ZoneBar" } do
		local scale = Instance.new("UIScale")
		scale.Parent = nodes[id]
		table.insert(scales, scale)
	end
	local function rescale()
		local k = math.clamp(gui.AbsoluteSize.Y / T.scale.referenceHeight, T.scale.min, T.scale.max)
		for _, scale in scales do
			scale.Scale = k
		end
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	rescale()

	local playerGui = gui.Parent :: PlayerGui
	local function screenOn(name: string): boolean
		local g = playerGui:FindFirstChild(name)
		return g ~= nil and g:IsA("ScreenGui") and g.Enabled
	end

	local front = false -- Territory Push is running
	local myKit: string? = nil
	local barShown, dotsShown = 0, 0
	task.spawn(function()
		while true do
			local now = os.clock()
			local folder = workspace:FindFirstChild(Cfg.FrontlineFolder)
			local map = workspace:FindFirstChild(Playtest.name)
			local zone = map and map:FindFirstChild(ZoneCfg.MarkerName)
			local title = screenOn("TitleScreen")
			local ffa = zone ~= nil and workspace:GetAttribute(ModesCfg.Attribute) == "FFA"
			front = not ffa and folder ~= nil and folder:IsA("Folder")
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
	-- the bar fades in on the loadout screen and while V is held in play; the dots only while V is held in play
	RunService.RenderStepped:Connect(function(dt)
		local title, loadout = screenOn("TitleScreen"), screenOn("LoadoutMenu")
		local held = UserInputService:IsKeyDown(Cfg.ShowKey) and UserInputService:GetFocusedTextBox() == nil
		local inPlay = front and not title and not loadout
		barShown = Rules.fade(barShown, if front and not title and (loadout or held) then 1 else 0, dt, Cfg.FadeSeconds)
		dotsShown = Rules.fade(dotsShown, if inPlay and held then 1 else 0, dt, Cfg.FadeSeconds)
		local bar = nodes.FrontBar :: CanvasGroup
		bar.Visible = barShown > 0
		bar.GroupTransparency = 1 - barShown
		showDots(dotsShown)
		showMarkers(dotsShown)
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
