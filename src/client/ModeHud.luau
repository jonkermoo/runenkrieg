--!strict
-- The game modes' top bar (src/shared/ui/ModeHud.json, Config/ModeHud, Rules/ModeHud; user 2026-10-29, option B of
-- the mode HUD drafts, the front bar). Built once from the spec; each Refresh it reads the live mode's replicated state:
--   Territory Push: Workspace's Frontline folder (src/server/Frontline: West / East teams, Phase, Winner; a child
--     folder per sector with Index, Owner, Control and the West / East soldiers in its zone). The viewer's side is on
--     the left; one seal per sector (user 2026-11-12, "seal chain 2": the point's rune, ringed as far as its control
--     goes in the colour of the side it leans to, ATTACK / DEFEND over the points in play). Shown on the loadout screen; in play only while M is held, fading fast, with a dot over each teammate
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
local PaperArt = require(script.Parent.PaperArt)
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

-- one point on the front strip (user 2026-11-12, "seal chain 2", then drawn: "Both B", a map ribbon with wax seals;
-- Config/PaperArt): a wax seal in its holder's colour with the point's rune pressed in it in ink; over its face a disc
-- in the colour of the side it leans to, swept round clockwise from the top as far as its capture goes (two clipped
-- halves, each with a hard-edged gradient turned to the sweep); a pencil loop round it while it is in play; the pulse
-- while contested, its tag above (ATTACK / DEFEND) and its line under; `key` the sector and side it was drawn for
type Seat = {
	box: Frame,
	seal: PointSeal.Seal,
	wax: ImageLabel,
	loop: ImageLabel,
	arcs: { ImageLabel },
	sweeps: { UIGradient },
	pulse: UIScale,
	tag: TextLabel,
	name: TextLabel,
	title: string,
	key: string,
}

local gui: ScreenGui
local nodes: { [string]: GuiObject } = {}
local binds: { [string]: TextLabel } = {}
local seats: { Seat } = {}
local links: { ImageLabel } = {} -- the track between neighbouring seats, in the colour of the side holding both ends

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
	else -- panel (bare when it has a shape: the code draws it)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		if n.shape then
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

-- a side's magic colour (the seals' and the map's, Palette UI.Grimoire.Magic), neutral for none
local function magic(kit: string?): Color3
	local G = (Palette.UI :: any).Grimoire
	local m = kit and G.Magic[kit]
	return rgb(m or G.neutral)
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

-- (re)builds the seats and the track for the sectors in `list` (west to east) as the viewer's side sees them, evenly
-- spaced along the bar
local function layoutPins(list: { Instance }, side: string?)
	for _, seat in seats do
		seat.box:Destroy()
		seat.tag:Destroy()
		seat.name:Destroy()
	end
	for _, l in links do
		l:Destroy()
	end
	table.clear(seats)
	table.clear(links)
	local bar = nodes.FrontBar
	local G = (Palette.UI :: any).Grimoire
	local n = #list
	local lineY = (find(Spec.root, "Line").pos :: { number })[4]
	for slot = 1, n do
		local x = (slot - 0.5) / n
		local f = list[Rules.slot(slot, n, side)]
		local s = sectorOf(f.Name)
		local hq = s ~= nil and s.isHQ == true
		local box = make(find(Spec.root, if hq then "PinHQ" else "Pin"), nil) :: Frame
		box.Position = UDim2.new(x, 0, box.Position.Y.Scale, box.Position.Y.Offset)
		local pulse = Instance.new("UIScale")
		pulse.Parent = box
		local R = Cfg.Strip.ring
		-- the wax seal (its drawing's blob `wax.size` of the box across), the capture disc over its face in two clipped
		-- halves (right, then left), the pencil loop round it
		local Wx = Cfg.Strip.wax
		local wax = PaperArt.new("wax")
		wax.Size = UDim2.fromScale(Wx.size, Wx.size)
		wax.ZIndex = 1
		wax.Parent = box
		local arcs, sweeps = {}, {}
		for half = 1, 2 do
			local clip = Instance.new("Frame")
			clip.Name = if half == 1 then "Right" else "Left"
			clip.BackgroundTransparency = 1
			clip.ClipsDescendants = true
			clip.AnchorPoint = Vector2.new(if half == 1 then 0 else 1, 0.5)
			clip.Position = UDim2.fromScale(0.5, 0.5)
			clip.Size = UDim2.fromScale(Wx.size / 2, Wx.size)
			clip.ZIndex = 2
			clip.Parent = box
			local d = PaperArt.new("disc")
			d.Size = UDim2.fromScale(2, 1)
			d.Position = UDim2.fromScale(if half == 1 then 0 else 1, 0.5)
			d.Parent = clip
			local g = Instance.new("UIGradient")
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.499, 0),
				NumberSequenceKeypoint.new(0.501, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
			g.Parent = d
			table.insert(arcs, d)
			table.insert(sweeps, g)
		end
		local loop = PaperArt.new("loop")
		loop.Size = UDim2.fromScale(Wx.loop, Wx.loop)
		loop.ZIndex = 4
		loop.Visible = false
		loop.Parent = box
		local disc = Instance.new("Frame")
		disc.Name = "Seal"
		disc.AnchorPoint = Vector2.new(0.5, 0.5)
		disc.Position = UDim2.fromScale(0.5, 0.5)
		disc.Size = UDim2.fromScale(R.seal, R.seal)
		disc.ZIndex = 3
		disc.Parent = box
		local index = (f:GetAttribute("Index") :: number?) or Rules.slot(slot, n, side)
		-- (the rune alone, pressed in the wax: no disc or ring of its own)
		local seal = PointSeal.new(disc, PointSeal.rune(index, n), rgb(G.ink), rgb(G.neutral))
		seal.ring.Enabled = false
		disc.BackgroundTransparency = 1
		box.Parent = bar
		local tag = make(find(Spec.root, "PinTag"), nil) :: TextLabel
		tag.Position = UDim2.new(x, 0, tag.Position.Y.Scale, tag.Position.Y.Offset)
		tag.Visible = false
		tag.Parent = bar
		local name = make(find(Spec.root, "PinName"), nil) :: TextLabel
		name.Position = UDim2.new(x, 0, name.Position.Y.Scale, name.Position.Y.Offset)
		-- (a point named only by its id, "S2", goes by its rune alone)
		local title = if hq then Cfg.Strip.hq elseif s and s.name ~= s.id then string.upper(s.name) else ""
		name.Text = title
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = rgb(G.ink) -- (written on the paper)
		name.TextStrokeTransparency = 1
		name.Parent = bar
		table.insert(seats, {
			box = box,
			seal = seal,
			wax = wax,
			loop = loop,
			arcs = arcs,
			sweeps = sweeps,
			pulse = pulse,
			tag = tag,
			name = name,
			title = title,
			key = f.Name,
		})
		if slot < n then
			local link = PaperArt.new("stroke")
			link.Name = "Link"
			link.AnchorPoint = Vector2.new(0, 0.5)
			link.Position = UDim2.new(x, 0, 0, lineY)
			link.Size = UDim2.new(1 / n, 0, 0, Cfg.Strip.link)
			link.ZIndex = 3
			link.Parent = bar
			table.insert(links, link)
		end
	end
	local line = nodes.Line
	local ends = if n > 0 then 0.5 / n else 0.5
	line.Position = UDim2.new(ends, 0, line.Position.Y.Scale, line.Position.Y.Offset)
	line.Size = UDim2.new(1 - 2 * ends, 0, line.Size.Y.Scale, line.Size.Y.Offset)
	local plate = nodes.Plate
	plate.Size = UDim2.new(1 - 2 * ends, 2 * Cfg.Strip.plate.pad, plate.Size.Y.Scale, plate.Size.Y.Offset)
end

-- a seat's capture: the disc swept clockwise from the top to `share` of the way round, in `color`
local function fillSeat(seat: Seat, share: number, color: Color3)
	local a = 360 * math.clamp(share, 0, 1)
	seat.sweeps[1].Rotation = math.min(a, 180)
	seat.sweeps[2].Rotation = math.max(a, 180)
	for _, arc in seat.arcs do
		arc.ImageColor3 = color
		arc.Visible = share > Cfg.Fill.min
	end
end

local shownCount = -1
local shownSide: string? = "?"

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

-- the strip's cue in play (Cfg.Strip): until when it shows by itself, and what the last refresh saw
local alertUntil = 0
local lastControl: { [string]: number } = {}
local lastOpen: { [string]: boolean } = {}

local function updateFront(folder: Instance, now: number)
	local side = mySide(folder)
	local list = sectorsOf(folder)
	local n = #list
	-- (the seats are drawn for the sectors as this side sees them: built again when either changes)
	local stale = n ~= shownCount or side ~= shownSide
	for slot, seat in seats do
		local f = list[Rules.slot(slot, n, side)]
		stale = stale or f == nil or seat.key ~= f.Name
	end
	if stale then
		layoutPins(list, side)
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
	-- the points that can be taken now (either side's next: Rules/Frontline.target), marked in the world
	local state = { owner = {}, control = {} }
	for i, f in list do
		state.owner[i] = (f:GetAttribute("Owner") :: string?) or "Neutral"
		state.control[i] = (f:GetAttribute("Control") :: number?) or 0
	end
	local open: { [string]: boolean } = {}
	local ours: { [string]: boolean } = {} -- (the viewer's side's next point: ATTACK; the enemy's: DEFEND)
	if folder:GetAttribute("Phase") == "Playing" then
		for _, s in { "West", "East" } do
			local t = FrontRules.target(state, s)
			if t then
				open[list[t].Name] = true
				if s == side then
					ours[list[t].Name] = true
				end
			end
		end
	end
	-- a point newly open (the match's first ones too): the strip shows for a while
	local clock = os.clock()
	for name in open do
		if not lastOpen[name] then
			alertUntil = math.max(alertUntil, clock + Cfg.Strip.fresh)
		end
	end
	lastOpen = open
	for slot = 1, n do
		local f = list[Rules.slot(slot, n, side)]
		local seat = seats[slot]
		local s = sectorOf(f.Name)
		local owner = f:GetAttribute("Owner") :: string?
		local pin = Rules.pin(
			owner,
			(f:GetAttribute("Control") :: number?) or 0,
			(f:GetAttribute("West") :: number?) or 0,
			(f:GetAttribute("East") :: number?) or 0
		)
		-- the wax in its holder's colour (toward amber, beating, while contested: the seal swells with it), its rune in
		-- ink, the capture disc over it in the colour of the side it leans to
		local holder = if owner == "West" then west elseif owner == "East" then east else nil
		local contested = pin.state == "Contested"
		local own, beat = PointSeal.colours(holder, contested, now)
		local inkC = rgb(((Palette.UI :: any).Grimoire).ink)
		PointSeal.paint(seat.seal, inkC, inkC)
		seat.wax.ImageColor3 = (if contested then beat else own):Lerp(Color3.new(), Cfg.Strip.wax.shade)
		local leans = if pin.fillSide == "West" then west elseif pin.fillSide == "East" then east else nil
		fillSeat(seat, pin.fill, magic(leans))
		local P = Cfg.Strip.pulse
		seat.pulse.Scale = if contested
			then 1 + P.grow * (math.sin(now / P.seconds * 2 * math.pi) + 1) / 2
			elseif pin.state == "Attacked" then 1 + P.grow
			else 1
		-- the points in play: ATTACK (the viewer's side's next) in red, DEFEND (the enemy's) in the viewer's colour
		local isOpen = open[f.Name] == true
		local attack = ours[f.Name] == true
		seat.tag.Visible = isOpen
		seat.loop.Visible = isOpen
		if isOpen then
			-- (in pencil: red to attack, the viewer's own colour to defend; the loop round the seal the same)
			seat.tag.Text = if attack or side == nil then Cfg.Strip.attack else Cfg.Strip.defend
			local myKit = if side == "West" then west elseif side == "East" then east else nil
			local pencil = if attack or side == nil
				then tok("tagAttack")
				else magic(myKit):Lerp(Color3.new(), Cfg.Strip.defendShade)
			seat.tag.TextColor3 = pencil
			seat.loop.ImageColor3 = pencil
		end
		-- under it: its name, and how far it's taken while it's being taken (not full, not empty)
		local moving = pin.fill > Cfg.Fill.min and pin.fill < 1 - Cfg.Fill.min and pin.state ~= "Held"
		local pct = if moving then `{math.floor(pin.fill * 100 + 0.5)}%` else ""
		seat.name.Text = if seat.title ~= "" and pct ~= "" then `{seat.title} · {pct}` else seat.title .. pct
		seat.name.TextTransparency = if isOpen or moving then 0 else Cfg.Strip.nameDim
		-- the track to the next seat in the side's colour where that side holds both ends
		local link = links[slot]
		if link then
			local nf = list[Rules.slot(slot + 1, n, side)]
			local nOwner = nf and nf:GetAttribute("Owner") :: string?
			local both = owner == nOwner and (owner == "West" or owner == "East")
			link.Visible = both
			if both then
				link.ImageColor3 = magic(holder):Lerp(Color3.new(), Cfg.Strip.linkShade)
			end
		end
		-- a point being taken: the strip shows while it is and a little after
		local control = (f:GetAttribute("Control") :: number?) or 0
		local was = lastControl[f.Name]
		lastControl[f.Name] = control
		if pin.state == "Contested" or pin.state == "Attacked" or (was ~= nil and math.abs(control - was) > 1e-3) then
			alertUntil = math.max(alertUntil, clock + Cfg.Strip.linger)
		end
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
	-- in a leather map case (drawn: Config/PaperArt; user 2026-11-12: "Both B"), a little past the sheet all round
	local function cased(box: Frame)
		local case = PaperArt.new("case", H.case.slice)
		case.Size = UDim2.new(1, 2 * H.case.pad, 1, 2 * H.case.pad)
		case.ZIndex = 0
		case.Parent = box
	end
	cased(mapBox)
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
	cased(ffaBox)
	ffaBox.Size = UDim2.fromOffset(H.width, tall(Playtest.name))
	ffaBox.Parent = gui
	SketchMap.new(ffaBox, Playtest.name, { you = true, zone = true })
	nodes.SketchMapFFA = ffaBox
	local scales: { [UIScale]: boolean } = {} -- (true: also by the HUD size setting)
	local barScale: UIScale? = nil -- the front bar's (smaller in play: Cfg.Strip)
	local screenK = 1
	-- the wave countdown, shown only while the soldier stands in its wave line
	nodes.WaveBar.Visible = false
	do
		-- the strip's plate: a ribbon of map paper, torn at its ends (user 2026-11-12: "Both B"; Config/PaperArt), and
		-- the track along it inked in dashes
		local plate = nodes.Plate
		plate.ZIndex = 0
		plate.BackgroundTransparency = 1
		local P = Cfg.Strip.plate
		PaperArt.new("ribbon", P.slice).Parent = plate
		local line = nodes.Line
		line.BackgroundTransparency = 1
		line.Size = UDim2.new(line.Size.X.Scale, line.Size.X.Offset, 0, P.dash[2])
		local dashes = PaperArt.new("dash")
		dashes.ScaleType = Enum.ScaleType.Tile
		dashes.TileSize = UDim2.new(0, P.dash[1], 1, 0)
		dashes.Parent = line
	end
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
	local wasLive = false -- (in play last frame, past the wave hold)
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
		-- the front bar: big for the result; in play a smaller strip while M is held, a point is being taken or one has
		-- just opened (Cfg.Strip), off while the wave countdown stands in its place
		local character = Players.LocalPlayer.Character
		local waveAt = character and character:GetAttribute(FrontlineCfg.HoldAttribute)
		local waiting = front and not title and not loadout and type(waveAt) == "number"
		local live = inPlay and not results and not waiting
		if live and not wasLive then
			alertUntil = math.max(alertUntil, os.clock() + Cfg.Strip.fresh) -- (into play: where the fight is)
		end
		wasLive = live
		local strip = live and (held or os.clock() < alertUntil)
		-- (your side's flag and name only off play, on the loadout screen; not over the result)
		nodes.LeftFlag.Visible = not live and not results
		nodes.LeftName.Visible = not live and not results
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
