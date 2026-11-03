--!strict
-- The match's cutscenes (user 2026-11-02: "cutscene animations before and after matches"; Config/Cutscenes, Rules/
-- Cutscenes): the pre-match flight over the countdown after a match (Workspace.Frontline's Phase "Countdown": a shot
-- round each point's landmark as the narrator gives its order; a fresh server's first countdown is a loading screen
-- instead, src/client/EndScenes), the dips to black between the end's scenes, and, at a match's end,
-- the fade to the winner's colour (Phase "Fade": the world's colour drained, then the winner's land colour with their
-- name; it holds until src/client/EndScenes takes over with the battle table). Every player sees them on the server's
-- clock (PhaseEndsAt), so a player who comes in late joins where it is. Over the flight: the widescreen bars, the title
-- cards, the point seals stamped along the bottom bar, the sketch-map sheet it opens on; the narrator speaks the plan
-- (src/client/Speech, Config/Cutscenes.Speech part two) when the folder's Speech attribute names the match before.
-- While anything plays the HUD, the dev pins, the menus' contents and the world's sounds are put away and the
-- soldier's controls are off (MatchCutscene.cover, counted: EndScenes covers too). Holding Space (or the Skip button
-- on a touch screen) ends the flight early: the camera goes back to the soldier (still frozen until the whistle).
--   MatchCutscene.start(), MatchCutscene.playing(kind?) -> boolean, MatchCutscene.ended: Event (kind),
--   MatchCutscene.cover(on), MatchCutscene.clearFade() (EndScenes: its set is up)

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Cutscenes)
local FrontCfg = require(Shared.Config.Frontline)
local DevCfg = require(Shared.Config.DevTools)
local SketchCfg = require(Shared.Config.SketchMap) :: any
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local LiveMap = require(Shared.LiveMap)
local Rules = require(Shared.Rules.Cutscenes)
local Ink = require(script.Parent.Ink)
local Audio = require(script.Parent.Audio)
local DevPanel = require(script.Parent.DevPanel)
local MatchCam = require(script.Parent.MatchCam)
local PointSeal = require(script.Parent.PointSeal)
local Menus = require(script.Parent.Menus) :: any
local SketchMap = require(script.Parent.SketchMap)
local Speech = require(script.Parent.Speech)

local MatchCutscene = {}

local endedEvent = Instance.new("BindableEvent")
MatchCutscene.ended = endedEvent.Event

local GR = (Palette.UI :: any).Grimoire
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local FONT = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
local HIDE = table.clone(DevCfg.Admin.Cinematic.HudGuis)
table.insert(HIDE, "Chat")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

type Play = {
	kind: string,
	cut: any,
	length: number,
	startAt: number, -- server time of the cut's 0
	map: any,
	anchors: { [string]: { number } },
	points: { { number } },
	home: Rules.Side?,
	winner: Rules.Side?,
	fill: { [string]: string },
	shot: number,
	skipHeld: number,
	streamed: { [number]: boolean },
	fov: number,
	mapKey: string,
	sealsDrawn: string,
}
local play: Play? = nil

function MatchCutscene.playing(kind: string?): boolean
	return play ~= nil and (kind == nil or (play :: Play).kind == kind)
end

-- the gui
local gui: ScreenGui
local topBar: Frame, bottomBar: Frame
local big: TextLabel, small: TextLabel, place: TextLabel, skip: TextButton
local white: Frame
local sheet: Frame -- the sketch-map sheet over the world
local sheets: { [string]: Frame } = {}
local sealRow: Frame
local seals: { { disc: Frame, ring: UIStroke, canvas: Ink.Canvas, rune: string } } = {}
local grade: ColorCorrectionEffect
local fadeFill: Frame
local drain: ColorCorrectionEffect

local function label(name: string, size: number, parent: Instance): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.FontFace = FONT
	l.TextSize = size
	l.TextColor3 = rgb(GR.text)
	l.TextStrokeColor3 = rgb(GR.shade)
	l.TextStrokeTransparency = 0.4
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = UDim2.fromScale(1, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Text = ""
	l.Parent = parent
	return l
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "MatchCutscene"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = Cfg.DisplayOrder
	gui.Enabled = false
	-- the sheet: an ink ground with the live map's sketch in the middle (each map's made once, when first needed)
	sheet = Instance.new("Frame")
	sheet.Name = "Sheet"
	sheet.Size = UDim2.fromScale(1, 1)
	sheet.BackgroundColor3 = rgb(GR.ink)
	sheet.BorderSizePixel = 0
	sheet.Parent = gui
	white = Instance.new("Frame")
	white.Name = "Impact"
	white.Size = UDim2.fromScale(1, 1)
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BorderSizePixel = 0
	white.Visible = false
	white.Parent = gui
	for i, name in { "Top", "Bottom" } do
		local bar = Instance.new("Frame")
		bar.Name = name
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(1, Cfg.Bars)
		bar.AnchorPoint = Vector2.new(0, i - 1)
		bar.Position = UDim2.fromScale(0, i - 1)
		bar.ZIndex = 2
		bar.Parent = gui
		if i == 1 then
			topBar = bar
		else
			bottomBar = bar
		end
	end
	big = label("Big", 64, gui)
	big.ZIndex = 3
	small = label("Small", 28, gui)
	small.ZIndex = 3
	small.TextColor3 = rgb(GR.dim)
	-- the seals along the bottom bar and the name of the place they've reached
	sealRow = Instance.new("Frame")
	sealRow.Name = "Seals"
	sealRow.BackgroundTransparency = 1
	sealRow.AnchorPoint = Vector2.new(0.5, 0.5)
	sealRow.Position = UDim2.fromScale(0.5, 1 - Cfg.Bars / 2)
	sealRow.Size = UDim2.fromScale(0.5, Cfg.Bars * 0.6)
	sealRow.ZIndex = 3
	sealRow.Parent = gui
	local list = Instance.new("UIListLayout")
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Padding = UDim.new(0, 12)
	list.Parent = sealRow
	place = label("Place", 24, gui)
	place.ZIndex = 3
	place.Position = UDim2.fromScale(0.5, 1 - Cfg.Bars - 0.04)
	place.TextColor3 = rgb(GR.text)
	-- skip: the key's prompt on the bottom bar, a button on touch screens
	skip = Instance.new("TextButton")
	skip.Name = "Skip"
	skip.BackgroundTransparency = 1
	skip.FontFace = FONT
	skip.TextSize = 18
	skip.TextColor3 = rgb(GR.key)
	skip.TextXAlignment = Enum.TextXAlignment.Right
	skip.AnchorPoint = Vector2.new(1, 0.5)
	skip.Position = UDim2.new(1, -24, 1 - Cfg.Bars / 2, 0)
	skip.Size = UDim2.fromOffset(220, 44)
	skip.ZIndex = 4
	skip.Parent = gui
	-- the fade's colour fill (under the bars) and the colour drain
	fadeFill = Instance.new("Frame")
	fadeFill.Name = "Fade"
	fadeFill.Size = UDim2.fromScale(1, 1)
	fadeFill.BorderSizePixel = 0
	fadeFill.Visible = false
	fadeFill.Parent = gui
	drain = Instance.new("ColorCorrectionEffect")
	drain.Name = "CutsceneDrain"
	drain.Enabled = false
	drain.Parent = Lighting
	grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "CutsceneImpact"
	grade.Saturation = -1
	grade.Contrast = 0.8
	grade.Brightness = -0.05
	grade.Enabled = false
	grade.Parent = Lighting
	gui.Parent = player:WaitForChild("PlayerGui")
end

local function sheetFor(key: string): Frame?
	local m = SketchCfg.Maps[key]
	if not m then
		return nil
	end
	local f = sheets[key]
	if not f then
		f = Instance.new("Frame")
		f.Name = key
		f.BackgroundTransparency = 1
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.55)
		f.Size = UDim2.fromScale(0.9, 0.9)
		local shape = Instance.new("UIAspectRatioConstraint")
		shape.AspectRatio = m.size[1] / m.size[2]
		shape.Parent = f
		f.Parent = sheet
		SketchMap.new(f, key, {})
		sheets[key] = f
	end
	return f
end

local function makeSeals(map: any)
	for _, s in seals do
		s.disc:Destroy()
	end
	table.clear(seals)
	for i in map.sectors do
		local disc = Instance.new("Frame")
		disc.Name = "Seal" .. i
		disc.BackgroundColor3 = rgb(GR.ink)
		disc.BorderSizePixel = 0
		disc.Size = UDim2.fromScale(1, 1) -- (the aspect fits it to a square the row's height)
		disc.LayoutOrder = i
		disc.ZIndex = 3
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = disc
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = disc
		local ring = Instance.new("UIStroke")
		ring.Thickness = 3
		ring.Parent = disc
		local box = Instance.new("Frame")
		box.BackgroundTransparency = 1
		box.AnchorPoint = Vector2.new(0.5, 0.5)
		box.Position = UDim2.fromScale(0.5, 0.5)
		box.Size = UDim2.fromScale(0.38, 0.62)
		box.ZIndex = 4
		box.Parent = disc
		disc.Parent = sealRow
		table.insert(
			seals,
			{ disc = disc, ring = ring, canvas = Ink.canvas(box), rune = PointSeal.rune(i, #map.sectors) }
		)
	end
end

-- the colour a seal is ringed in: its starting holder's magic (the pre-match), or the winner's once stamped
local function magicOf(kit: unknown): Color3
	local c = type(kit) == "string" and GR.Magic[kit]
	return if c then rgb(c) else rgb(GR.neutral)
end

local function paintSeals(shown: number, owners: { Color3 })
	for i, s in seals do
		s.disc.Visible = i <= shown
		s.ring.Color = owners[i] or rgb(GR.neutral)
		s.canvas.set(function(holder, w, h)
			Ink.rune(holder, s.rune, 0, 0, w, h, math.max(1, h * 0.13), rgb(GR.text))
		end)
	end
end

-- HUD guis kept off while the cut plays (what their owners set meanwhile comes back after)
type Held = { wanted: boolean, ours: boolean, conn: RBXScriptConnection }
local held: { [LayerCollector]: Held } = {}
local function holdOff(g: LayerCollector)
	if held[g] then
		return
	end
	local h: Held = { wanted = g.Enabled, ours = g.Enabled, conn = nil :: any }
	h.conn = g:GetPropertyChangedSignal("Enabled"):Connect(function()
		if g.Enabled then
			h.wanted, h.ours = true, true
			g.Enabled = false
		elseif h.ours then
			h.ours = false
		else
			h.wanted = false
		end
	end)
	held[g] = h
	g.Enabled = false
end
-- the dev pins and the settings gear (src/client/DevPanel) put away too, as they were before
local pins: { [GuiObject]: boolean } = {}
local function releaseAll()
	for g, h in held do
		h.conn:Disconnect()
		if g.Parent then
			g.Enabled = h.wanted
		end
	end
	table.clear(held)
	for b, was in pins do
		b.Visible = was
	end
	table.clear(pins)
end
local function hideHud()
	for _, g in player:WaitForChild("PlayerGui"):GetChildren() do
		if g:IsA("LayerCollector") and table.find(HIDE, g.Name) then
			holdOff(g)
		end
		if g:IsA("LayerCollector") and table.find(DevPanel.Panels, g.Name) then
			for _, name in { "Pin", "Gear" } do
				local b = g:FindFirstChild(name)
				if b and b:IsA("GuiObject") and pins[b] == nil then
					pins[b] = b.Visible
					b.Visible = false
				end
			end
		end
	end
end

local function controls(on: boolean)
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
	end)
	if ok and module then
		local c = module:GetControls()
		if on then
			c:Enable()
		else
			c:Disable()
		end
	end
end

-- The screen cleared for a cut or an end scene (src/client/EndScenes): the HUD, the dev pins and the menus' contents
-- put away, the world's sounds silenced and the soldier's controls off; each cover(true) is undone by one cover(false)
-- (the last gives them back).
local covers = 0
local worldVolume = 1
function MatchCutscene.cover(on: boolean)
	local was = covers
	covers = math.max(covers + (if on then 1 else -1), 0)
	if (was > 0) == (covers > 0) then
		return
	end
	local sounds = Audio.effects()
	if covers > 0 then
		hideHud()
		worldVolume = sounds.Volume
		sounds.Volume = 0
	else
		releaseAll()
		sounds.Volume = worldVolume
	end
	Menus.cover(covers > 0)
	controls(covers == 0)
end

-- the ground under (x, z): terrain only, so a roof or a treetop never lifts the camera
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true
local function groundAt(x: number, z: number): number
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), terrainOnly)
	return if hit then hit.Position.Y else 0
end
local function world(p: Rules.Place): Vector3
	return Vector3.new(p.x, groundAt(p.x, p.z) + p.up, p.z)
end

local function sideOfMe(folder: Instance): Rules.Side?
	local c = player.Character
	local kit = c and c:GetAttribute("Kit")
	if kit and kit == folder:GetAttribute("West") then
		return "West"
	elseif kit and kit == folder:GetAttribute("East") then
		return "East"
	end
	return nil
end

local function nation(kit: unknown): string
	local k = type(kit) == "string" and (U.Kits :: any)[kit]
	return if k then k.team else ""
end

-- the fade at a match's end: the world drained of colour, then the winner's land colour over it with their name;
-- held until EndScenes' set is up (MatchCutscene.clearFade)
local fadeFolder: Instance? = nil
local fading = false
local function fadeStep()
	local folder = fadeFolder
	if not folder then
		return
	end
	local endsAt = folder:GetAttribute("PhaseEndsAt")
	local length = FrontCfg.FadeSeconds
	local t = if type(endsAt) == "number" then length - (endsAt - workspace:GetServerTimeNow()) else length
	local u = math.clamp(t / length, 0, 1)
	drain.Saturation = -math.clamp(u / Cfg.Fade.drain, 0, 1)
	local cover = math.clamp((u - (1 - Cfg.Fade.cover)) / Cfg.Fade.cover, 0, 1)
	fadeFill.BackgroundTransparency = 1 - cover
	big.TextTransparency = 1 - cover
	big.TextStrokeTransparency = 1 - cover * 0.6
	small.TextTransparency = 1 - cover
	small.TextStrokeTransparency = 1 - cover * 0.6
end

local function startFade(folder: Instance)
	if fading then
		return
	end
	fading = true
	fadeFolder = folder
	local winner = folder:GetAttribute("Winner")
	local kit = if winner == "West" or winner == "East" then folder:GetAttribute(winner) else nil
	local wash = type(kit) == "string" and GR.Wash[kit]
	fadeFill.BackgroundColor3 = if wash then rgb(wash) else rgb(Cfg.Fade.noWinner)
	local c = Cfg.Captions.Winner
	big.Text = if kit then string.upper(nation(kit)) else c.noWinner
	big.TextColor3 = rgb(GR.text)
	big.Position = UDim2.fromScale(0.5, 0.45)
	small.Text = if kit then c.small else ""
	small.Position = UDim2.fromScale(0.5, 0.53)
	place.Text, skip.Text = "", ""
	sealRow.Visible = false
	sheet.BackgroundTransparency = 1
	for _, f in sheets do
		f.Visible = false
	end
	drain.Enabled = true
	fadeFill.Visible = true
	MatchCutscene.cover(true)
	gui.Enabled = true
	RunService:BindToRenderStep("MatchFade", Enum.RenderPriority.Camera.Value + 2, fadeStep)
end

function MatchCutscene.clearFade()
	if not fading then
		return
	end
	fading = false
	fadeFolder = nil
	RunService:UnbindFromRenderStep("MatchFade")
	drain.Enabled = false
	fadeFill.Visible = false
	big.Text, small.Text = "", ""
	if not play then
		gui.Enabled = false
	end
	MatchCutscene.cover(false)
end

local function finish()
	local p = play
	if not p then
		return
	end
	play = nil
	RunService:UnbindFromRenderStep("MatchCutscene")
	gui.Enabled = false
	grade.Enabled = false
	white.Visible = false
	camera.FieldOfView = p.fov
	if not MatchCam.running() then
		camera.CameraType = Enum.CameraType.Custom
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then
			camera.CameraSubject = h
		end
	end
	MatchCutscene.cover(false)
	endedEvent:Fire(p.kind)
end

-- asks for the ground round each upcoming shot's camera before it starts (StreamingEnabled)
local function streamAhead(p: Play, t: number)
	for i, shot in p.cut.shots do
		local t0 = Rules.start(p.cut, i)
		if not p.streamed[i] and t >= t0 - Cfg.StreamAhead and shot.kind ~= "Paper" then
			p.streamed[i] = true
			local flip = Rules.mirrored(shot, p.home, p.winner)
			local at = { 0, 0.5, 1 }
			if shot.kind == "Sectors" then -- (each point's own shot)
				for k = 1, #p.points do
					table.insert(at, (k - 0.5) / #p.points)
				end
			end
			for _, u in at do
				local pose = Rules.pose(shot, u, p.anchors, p.points, flip, Cfg.Paper.up)
				local look = Vector3.new(pose.look.x, 0, pose.look.z)
				task.spawn(function()
					pcall(function()
						player:RequestStreamAroundAsync(look)
					end)
				end)
			end
		end
	end
end

local function caption(p: Play, shot: any)
	local c = shot.caption and Cfg.Captions[shot.caption]
	big.Text, small.Text = "", ""
	if not c then
		return
	end
	local text = Rules.text(c.big, p.fill)
	if shot.caption == "Winner" and not p.winner then
		big.Text = c.noWinner
		return
	end
	big.Text = string.upper(text)
	small.Text = Rules.text(c.small, p.fill)
	local onSheet = shot.kind == "Paper"
	big.Position = UDim2.fromScale(0.5, if onSheet then 0.2 else 0.42)
	small.Position = UDim2.fromScale(0.5, if onSheet then 0.27 else 0.5)
	if shot.caption == "West" or shot.caption == "East" then
		big.TextColor3 = magicOf(p.fill[shot.caption .. "Kit"])
	else
		big.TextColor3 = rgb(GR.text)
	end
end

local function step(dt: number)
	local p = play
	if not p then
		return
	end
	local t = workspace:GetServerTimeNow() - p.startAt
	-- skip: Space held (not while typing), or the button
	if
		UserInputService:IsKeyDown((Enum.KeyCode :: any)[Cfg.Skip.key])
		and UserInputService:GetFocusedTextBox() == nil
	then
		p.skipHeld += dt
	else
		p.skipHeld = 0
	end
	if t >= p.length or p.skipHeld >= Cfg.Skip.hold then
		finish()
		return
	end
	streamAhead(p, t)
	local shot, i, u = Rules.at(p.cut, t)
	if i ~= p.shot then
		p.shot = i
		caption(p, shot)
		place.Text = ""
	end
	local flip = Rules.mirrored(shot, p.home, p.winner)
	local pose = Rules.pose(shot, u, p.anchors, p.points, flip, Cfg.Paper.up)
	local eye, look = world(pose.eye), world(pose.look)
	local cf = CFrame.lookAt(eye, look) * CFrame.Angles(0, 0, math.rad(pose.roll))
	if shot.kind == "Eyes" then
		local head = player.Character and player.Character:FindFirstChild("Head") :: BasePart?
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if head and root then
			local at = head.Position + Vector3.new(0, 0.4, 0)
			local into = CFrame.lookAt(at, at + root.CFrame.LookVector)
			cf = cf:Lerp(into, Rules.ease(u))
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cf
	camera.FieldOfView = pose.fov or Cfg.Fov
	-- the movie layer: the sheet, the impact frame, the caption fading in, the seals
	-- (the ink ground fades; the sketch on it, drawn in many pieces, cuts in or out halfway)
	local paper = Rules.paper(shot, u, Cfg.Paper.fade)
	sheet.BackgroundTransparency = 1 - paper
	for _, f in sheets do
		f.Visible = paper >= 0.5 and f.Name == p.mapKey
	end
	white.Visible = shot.flash == true and u < 0.5
	grade.Enabled = shot.flash == true and u >= 0.5
	local fadeIn = math.clamp((t - Rules.start(p.cut, i)) / 0.35, 0, 1)
	big.TextTransparency, small.TextTransparency = 1 - fadeIn, 1 - fadeIn
	big.TextStrokeTransparency, small.TextStrokeTransparency = 1 - fadeIn * 0.6, 1 - fadeIn * 0.6
	local owners: { Color3 } = {}
	local shown = 0
	if shot.stamps then
		shown = Rules.stamped(shot, u, #p.map.sectors)
		for k, s in p.map.sectors do
			owners[k] = if s.startOwner == "West"
				then magicOf(p.fill.WestKit)
				elseif s.startOwner == "East" then magicOf(p.fill.EastKit)
				else rgb(GR.neutral)
		end
		if shot.kind == "Front" or shot.kind == "Sectors" then
			local id = Rules.landmark(p.map, shown, Cfg.LandmarkReach)
			local name = id and Cfg.Names[id]
			place.Text = if name then `{p.map.sectors[shown].name} · {name}` else p.map.sectors[shown].name
		end
	end
	sealRow.Visible = shot.stamps == true
	local sealKey = tostring(shown)
	for _, c in owners do
		sealKey ..= c:ToHex()
	end
	if sealKey ~= p.sealsDrawn then
		p.sealsDrawn = sealKey
		paintSeals(shown, owners)
	end
end

local function begin(kind: string, folder: Instance)
	local endsAt = folder:GetAttribute("PhaseEndsAt")
	if type(endsAt) ~= "number" then
		return
	end
	local key = LiveMap.key()
	local cut = Rules.cut(Cfg, kind, key)
	local length = Rules.length(cut)
	local startAt = endsAt - length
	if workspace:GetServerTimeNow() - startAt > length - 0.3 then
		return -- (all but over: not worth a cut)
	end
	finish()
	local map = LiveMap.get(key)
	local winnerAttr = folder:GetAttribute("Winner")
	local winner: Rules.Side? = if winnerAttr == "West" or winnerAttr == "East" then winnerAttr :: Rules.Side else nil
	local home = sideOfMe(folder)
	local points = {}
	for _, s in map.sectors do
		table.insert(points, { s.x, s.z })
	end
	local westKit, eastKit = folder:GetAttribute("West"), folder:GetAttribute("East")
	local fill = {
		map = map.name,
		west = nation(westKit),
		east = nation(eastKit),
		winner = if winner == "West" then nation(westKit) elseif winner == "East" then nation(eastKit) else "",
		WestKit = if type(westKit) == "string" then westKit else "",
		EastKit = if type(eastKit) == "string" then eastKit else "",
	}
	fill.West, fill.East = fill.west, fill.east
	play = {
		kind = kind,
		cut = cut,
		length = length,
		startAt = startAt,
		map = map,
		anchors = Rules.anchors(map, home, winner, Cfg.LandmarkReach),
		points = points,
		home = home,
		winner = winner,
		fill = fill,
		shot = 0,
		skipHeld = 0,
		streamed = {},
		fov = camera.FieldOfView,
		mapKey = key,
		sealsDrawn = "",
	}
	sheetFor(key)
	makeSeals(map)
	-- the narrator's plan over the flight, its closing call by the player's own kit
	local spoken = folder:GetAttribute(FrontCfg.SpeechAttribute)
	if kind == "Pre" and type(spoken) == "string" then
		local ownKit = if home then folder:GetAttribute(home) else nil
		local lines =
			Rules.partTwo(Cfg.Speech, cut, if type(ownKit) == "string" then ownKit else nil, key, #map.sectors)
		Speech.queue(lines, os.clock() + (startAt - workspace:GetServerTimeNow()))
	end
	skip.Text = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
		then Cfg.Skip.touch
		else Cfg.Skip.text
	MatchCutscene.cover(true)
	gui.Enabled = true
	RunService:BindToRenderStep("MatchCutscene", Enum.RenderPriority.Camera.Value + 2, step)
end

-- The dips to black between scenes (Config/Cutscenes.Dip; the folder's DipAt, set by src/server/Frontline as it
-- changes scene): a black screen over everything, the bars, the subtitles and the end scenes too.
local function dips()
	local g = Instance.new("ScreenGui")
	g.Name = "SceneDip"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = Cfg.DisplayOrder + 5
	local black = Instance.new("Frame")
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BorderSizePixel = 0
	black.Visible = false
	black.Parent = g
	g.Parent = player:WaitForChild("PlayerGui")
	RunService.RenderStepped:Connect(function()
		local folder = workspace:FindFirstChild(FrontCfg.FolderName)
		local at = folder and folder:GetAttribute(FrontCfg.DipAttribute)
		local k = Rules.dip(workspace:GetServerTimeNow(), if type(at) == "number" then at else nil, Cfg.Dip)
		black.Visible = k > 0
		black.BackgroundTransparency = 1 - k
	end)
end

function MatchCutscene.start()
	build()
	dips()
	skip.Activated:Connect(function()
		if play then
			(play :: Play).skipHeld = math.huge
		end
	end)
	topBar.Active, bottomBar.Active = false, false
	local seen: string? = nil
	task.spawn(function()
		while true do
			local folder = workspace:FindFirstChild(FrontCfg.FolderName)
			local phase = folder and folder:GetAttribute("Phase")
			if phase ~= seen then
				seen = phase :: string?
				if folder and phase == "Countdown" then
					MatchCutscene.clearFade()
					-- (after a match only: a fresh server's first countdown is a loading screen, src/client/EndScenes)
					if type(folder:GetAttribute(FrontCfg.SpeechAttribute)) == "string" then
						begin("Pre", folder)
					end
				elseif folder and phase == "Fade" then
					finish()
					startFade(folder)
				elseif play then
					finish() -- (the phase moved on: an admin's restart, the mode switched)
				end
				if phase ~= "Fade" and phase ~= "Table" and phase ~= "Vote" and phase ~= "Loading" then
					MatchCutscene.clearFade() -- (EndScenes never took over: a restart, a switch of mode)
				end
			end
			task.wait(0.1)
		end
	end)
end

return MatchCutscene
