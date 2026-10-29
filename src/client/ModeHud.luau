--!strict
-- The game modes' top bar (src/shared/ui/ModeHud.json, Config/ModeHud, Rules/ModeHud; user 2026-10-29, option B of
-- the mode HUD drafts, the front bar). Built once from the spec; each Refresh it reads the live mode's replicated state:
--   Territory Push: Workspace's Frontline folder (src/server/Frontline: West / East teams, Phase, Winner; a child
--     folder per sector with Index, Owner, Control and the West / East soldiers in its zone). The viewer's side is on
--     the left; one diamond per sector, filled as far as its control goes in the colour of the side it leans to.
--   Point Capture (the server's Mode is FFA): the zone marker on the Playtest map (src/server/ZoneMatch: Phase,
--     EndsAt, State, Holder, Leader, MoveAt, NextSpot, Winner) and the leader's ZoneScore: the clock centred, the point
--     leader under it, the zone's state, the move warning (user 2026-10-29: "center the timer and remove the bar
--     completely ... remove the top score and your score. just keep track of the score leader and display it"). The
--     leader's glow is the server's (src/server/ZoneMatch, Config/ZoneMatch.Leader).
-- Hidden when neither runs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
		local g = Instance.new("Frame")
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

-- (re)builds the diamonds and labels for `n` sectors, evenly spaced along the bar
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
end

local shownCount = -1
local shownSide: string? = "?"

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
	local leftKit, rightKit = if side == "East" then east else west, if side == "East" then west else east
	if side ~= shownSide then
		shownSide = side
		set("leftName", nation(leftKit))
		set("rightName", nation(rightKit))
		local leftFlag, rightFlag = nodes.LeftFlag :: ImageLabel, nodes.RightFlag :: ImageLabel
		leftFlag.Image = flagImage(leftKit)
		rightFlag.Image = flagImage(rightKit)
		nodes.LeftFill.BackgroundColor3 = teamRim(leftKit)
		nodes.RightFill.BackgroundColor3 = teamRim(rightKit)
	end
	local controls = {}
	for i, f in list do
		controls[i] = (f:GetAttribute("Control") :: number?) or 0
	end
	local front = Rules.seenFront(Rules.front(controls), side)
	nodes.LeftFill.Size = UDim2.fromScale(front, 1)
	nodes.RightFill.Size = UDim2.fromScale(1 - front, 1)
	nodes.FrontTick.Position = UDim2.fromScale(front, 0.5)
	local flashOn = (now // Cfg.FlashSeconds) % 2 == 0
	for slot = 1, n do
		local f = list[Rules.slot(slot, n, side)]
		local d = frontPins[slot]
		local s = SECTORS[f.Name]
		local hq = s ~= nil and s.isHQ == true
		local tmpl = find(Spec.root, if hq then "PinHQ" else "Pin")
		d.box.Size = udim(tmpl.size)
		frontLabels[slot].Text = if hq then "HQ" else f.Name
		local pin = Rules.pin(
			f:GetAttribute("Owner") :: string?,
			(f:GetAttribute("Control") :: number?) or 0,
			(f:GetAttribute("West") :: number?) or 0,
			(f:GetAttribute("East") :: number?) or 0
		)
		local kit = if pin.fillSide == "West" then west elseif pin.fillSide == "East" then east else nil
		fillDiamond(d, pin.fill, teamRim(kit))
		d.edge.Color = if pin.state == "Contested"
			then (if flashOn then tok("pinContested") else tok("pinEdge"))
			elseif pin.state == "Attacked" then tok("pinAttacked")
			else tok("pinEdge")
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

	task.spawn(function()
		while true do
			local now = os.clock()
			local folder = workspace:FindFirstChild(Cfg.FrontlineFolder)
			local map = workspace:FindFirstChild(Playtest.name)
			local zone = map and map:FindFirstChild(ZoneCfg.MarkerName)
			local ffa = zone ~= nil and workspace:GetAttribute(ModesCfg.Attribute) == "FFA"
			local front = not ffa and folder ~= nil and folder:IsA("Folder")
			nodes.FrontBar.Visible = front
			nodes.ZoneBar.Visible = ffa
			gui.Enabled = front or ffa
			if front then
				updateFront(folder :: Instance, now)
			elseif ffa then
				updateZone(zone :: Instance)
			end
			task.wait(Cfg.Refresh)
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
