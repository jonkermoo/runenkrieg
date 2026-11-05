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

local ContextActionService = game:GetService("ContextActionService")
local ContentProvider = game:GetService("ContentProvider")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Cutscenes)
local CamCfg = require(Shared.Config.Camera)
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
local MapLoader = require(script.Parent.MapLoader)
local PointSeal = require(script.Parent.PointSeal)
local Menus = require(script.Parent.Menus) :: any
local SketchMap = require(script.Parent.SketchMap)
local Speech = require(script.Parent.Speech)
local Settings = require(script.Parent.Settings)
local Net = require(Shared.Net)

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

-- the soldier's controls on or off, never waiting: the movement and jump keys sunk above the default controls (this
-- place has no PlayerModule: src/client/Artillery moveKeys; a wait on it never ended and the cut hung, the HUD hidden),
-- and the PlayerModule's controls too where there is one
local sinkKeys: { Enum.KeyCode } = {}
for _, name in Cfg.SinkKeys do
	table.insert(sinkKeys, (Enum.KeyCode :: any)[name])
end
local function controls(on: boolean)
	if on then
		ContextActionService:UnbindAction("MatchCutsceneKeys")
	else
		ContextActionService:BindActionAtPriority("MatchCutsceneKeys", function()
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value, table.unpack(sinkKeys))
	end
	local scripts = player:FindFirstChild("PlayerScripts")
	local pm = scripts and scripts:FindFirstChild("PlayerModule")
	if pm and pm:IsA("ModuleScript") then
		pcall(function()
			local c = (require(pm) :: any):GetControls()
			if on then
				c:Enable()
			else
				c:Disable()
			end
		end)
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
	controls(covers == 0)
	if Menus.cover then -- (set once the menus have started)
		Menus.cover(covers > 0)
	end
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

-- Each point's own shot turned round it until nothing stands between the camera and what it looks at (a tree, the
-- hill, another house): Config/Cutscenes.ClearView's turns tried in order, the first clear one kept (none clear: the
-- shot as written).
local function clearViews(
	cut: any,
	map: any,
	key: string,
	anchors: { [string]: { number } },
	points: { { number } }
): any
	local V = Cfg.ClearView
	local root = workspace:FindFirstChild(key)
	local buildings = root and root:FindFirstChild("Village") and (root :: any).Village:FindFirstChild("Buildings")
	local out = table.clone(cut)
	out.shots = table.clone(cut.shots)
	-- whether shot `s` from `t0` to `t1` through it has a clear view (a hit on `target`, its landmark, counts as clear);
	-- a shot marked `clear` (the opening) is turned as a whole the same way
	local function clearOf(s: any, t0: number, t1: number, target: Instance?): boolean
		for _, u in V.at do
			local pose = Rules.pose(s, t0 + (t1 - t0) * u, anchors, points, false, Cfg.Paper.up)
			local eye, look = world(pose.eye), world(pose.look)
			-- nothing right at the camera (a trunk filling half the frame)
			if #workspace:GetPartBoundsInRadius(eye, V.room) > 0 then
				return false
			end
			-- and nothing across the frame: rays to the spot looked at and to either side and over it
			local cf = CFrame.lookAt(eye, look)
			local half = (look - eye).Magnitude * math.tan(math.rad(pose.fov or Cfg.Fov) / 2) * V.wide
			for _, to in
				{ look, look + cf.RightVector * half, look - cf.RightVector * half, look + cf.UpVector * half * 0.6 }
			do
				local hit = workspace:Raycast(eye, to - eye)
				if
					hit
					and (hit.Position - to).Magnitude > V.near
					and not (target and hit.Instance:IsDescendantOf(target))
				then
					return false
				end
			end
		end
		return true
	end
	for k, shot in out.shots do
		if shot.clear then
			for _, spin in V.turns do
				local turned = Rules.turnShot(shot, spin)
				if clearOf(turned, 0, 1, nil) then
					out.shots[k] = turned
					break
				end
			end
		end
		if shot.kind == "Sectors" then
			local s = table.clone(shot)
			s.spins = {}
			for i = 1, #points do
				local id = Rules.landmark(map, i, Cfg.LandmarkReach)
				local target = id and buildings and buildings:FindFirstChild(id)
				local function clear(): boolean
					return clearOf(s, (i - 1) / #points, i / #points, target)
				end
				local found = false
				for _, spin in V.turns do
					s.spins[i] = spin
					if clear() then
						found = true
						break
					end
				end
				if not found then
					s.spins[i] = 0
				end
			end
			out.shots[k] = s
		end
	end
	return out
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
	-- (the drain and the cover take FadeSeconds from the phase's start; the victory screen then holds: Victory)
	local startAt = folder:GetAttribute("PhaseAt")
	local length = FrontCfg.FadeSeconds
	local t = if type(startAt) == "number" then workspace:GetServerTimeNow() - startAt else length
	local u = math.clamp(t / length, 0, 1)
	drain.Saturation = -math.clamp(u / Cfg.Fade.drain, 0, 1)
	local cover = math.clamp((u - (1 - Cfg.Fade.cover)) / Cfg.Fade.cover, 0, 1)
	fadeFill.BackgroundTransparency = 1 - cover
	big.TextTransparency = 1 - cover
	big.TextStrokeTransparency = 1 - cover * 0.6
	small.TextTransparency = 1 - cover
	small.TextStrokeTransparency = 1 - cover * 0.6
end

-- the player's camera zoom as the match ended (the game's camera still running), for the hand-over after the flight
local gameZoom: number? = nil

-- where the game's own camera will be behind the soldier, and its field of view (Config/Cutscenes.HandOver)
local function gameView(root: BasePart, humanoid: Humanoid?): (CFrame, number)
	local H = Cfg.HandOver
	local zoom = Rules.handZoom(gameZoom, H, CamCfg.FreeMinZoom, CamCfg.FreeMaxZoom)
	local offset = if humanoid then humanoid.CameraOffset else Vector3.zero
	local focus = root.Position + Vector3.new(0, H.focusUp, 0) + offset
	local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
	local pitch = math.rad(H.pitch)
	local dir = flat * math.cos(pitch) - Vector3.new(0, math.sin(pitch), 0)
	return CFrame.lookAt(focus - dir * zoom, focus), Settings.get("FieldOfView") :: number
end

local function startFade(folder: Instance)
	if fading then
		return
	end
	if camera.CameraType == Enum.CameraType.Custom then
		gameZoom = (camera.CFrame.Position - camera.Focus.Position).Magnitude
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
	-- (the player's own field of view, whatever the scene before left: user 2026-11-04, a narrow view after joining)
	camera.FieldOfView = Settings.get("FieldOfView") :: number
	if not MatchCam.running() then
		-- the game's own camera from where the flight left it (a skip too): its angle behind the soldier, its fov
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and p.kind == "Pre" then
			camera.CFrame, camera.FieldOfView = gameView(root, player.Character:FindFirstChildOfClass("Humanoid"))
		end
		camera.CameraType = Enum.CameraType.Custom
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then
			camera.CameraSubject = h
		end
	end
	MatchCutscene.cover(false)
	endedEvent:Fire(p.kind)
end

-- the spots on the ground shot `shot` of a cut looks at and looks from (its start, middle and end; each point's own
-- shot's middle)
local function looksOf(shot: any, anchors: { [string]: { number } }, points: { { number } }, flip: boolean): { Vector3 }
	local at = { 0, 0.5, 1 }
	if shot.kind == "Sectors" then
		for k = 1, #points do
			table.insert(at, (k - 0.5) / #points)
		end
	end
	local out = {}
	for _, u in at do
		local pose = Rules.pose(shot, u, anchors, points, flip, Cfg.Paper.up)
		table.insert(out, Vector3.new(pose.look.x, 0, pose.look.z))
		table.insert(out, Vector3.new(pose.eye.x, 0, pose.eye.z))
	end
	return out
end

local function streamAround(spot: Vector3)
	pcall(function()
		player:RequestStreamAroundAsync(spot)
	end)
end

-- asks for the ground round each upcoming shot's camera before it starts (StreamingEnabled)
local function streamAhead(p: Play, t: number)
	for i, shot in p.cut.shots do
		local t0 = Rules.start(p.cut, i)
		if not p.streamed[i] and t >= t0 - Cfg.StreamAhead and shot.kind ~= "Paper" then
			p.streamed[i] = true
			for _, look in looksOf(shot, p.anchors, p.points, Rules.mirrored(shot, p.home, p.winner)) do
				task.spawn(streamAround, look)
			end
		end
	end
end

-- The next map loaded in the armory (Net "MapLoad", src/server/Frontline): the WHOLE map (src/client/MapLoader; user
-- 2026-11-04: "during this time, we will be loading the map FULLY"), every spot its flight looks at too, for either
-- side and either winner (the sides are dealt after), then the server told.
local loadingKey = ""
local function loadMap(key: string, assets: { string })
	loadingKey = key
	local ok, map = pcall(LiveMap.get, key)
	if not ok or not map then
		Net.event("MapLoad"):FireServer(key)
		return
	end
	local cut = Rules.cut(Cfg, "Pre", key)
	local points = {}
	for _, s in map.sectors do
		table.insert(points, { s.x, s.z })
	end
	local spots: { Vector3 } = {}
	local function add(v: Vector3)
		for _, o in spots do
			if (o - v).Magnitude < Cfg.LoadSpacing then
				return
			end
		end
		table.insert(spots, v)
	end
	for _, home: Rules.Side in { "West", "East" } do
		for _, winner: Rules.Side in { "West", "East" } do
			local anchors = Rules.anchors(map, home, winner, Cfg.LandmarkReach)
			for _, shot in cut.shots do
				if shot.kind ~= "Paper" then
					for _, v in looksOf(shot, anchors, points, Rules.mirrored(shot, home, winner)) do
						add(v)
					end
				end
			end
		end
	end
	local this = MapLoader.load(key, spots, assets)
	while not this.finished do
		if loadingKey ~= key then
			return -- (a newer map asked for)
		end
		task.wait(0.1)
	end
	Net.event("MapLoad"):FireServer(key)
end

-- The flight toured unseen under the black before it (Net "MapTour", src/server/Frontline): the camera held at each
-- shot's start, middle and end (Rules/Cutscenes.tourAt) a few frames and till nothing is left to download, as a map's
-- textures and mesh detail load only once a camera looks at them; then the server told (Config/Cutscenes.Tour).
local function tour(key: string)
	local folder = workspace:FindFirstChild(FrontCfg.FolderName)
	local map = LiveMap.get(key)
	local T = Cfg.Tour
	local views: { { cf: CFrame, fov: number } } = {}
	if folder and map then
		local cut = Rules.cut(Cfg, "Pre", key)
		local points = {}
		for _, s in map.sectors do
			table.insert(points, { s.x, s.z })
		end
		local w = folder:GetAttribute("Winner")
		local winner: Rules.Side? = if w == "West" or w == "East" then w :: Rules.Side else nil
		local me = sideOfMe(folder)
		local homes: { Rules.Side } = if me then { me } else { "West", "East" }
		for _, home in homes do
			local anchors = Rules.anchors(map, home, winner, Cfg.LandmarkReach)
			for _, shot in clearViews(cut, map, key, anchors, points).shots do
				if shot.kind ~= "Paper" and shot.kind ~= "Self" then
					local flip = Rules.mirrored(shot, home, winner)
					for _, u in Rules.tourAt(shot, #points) do
						local pose = Rules.pose(shot, u, anchors, points, flip, Cfg.Paper.up)
						local eye, look = world(pose.eye), world(pose.look)
						table.insert(views, { cf = CFrame.lookAt(eye, look), fov = pose.fov or Cfg.Fov })
						task.spawn(streamAround, look)
					end
				end
			end
		end
	end
	local view = views[1]
	RunService:BindToRenderStep("MapTour", Enum.RenderPriority.Last.Value, function()
		if view then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = view.cf
			camera.FieldOfView = view.fov
		end
	end)
	local from = os.clock()
	for _, v in views do
		if os.clock() - from > T.max then
			break
		end
		view = v
		local heldAt = os.clock()
		for _ = 1, T.frames do
			RunService.RenderStepped:Wait()
		end
		while ContentProvider.RequestQueueSize > 0 and os.clock() - heldAt < T.each do
			RunService.RenderStepped:Wait()
		end
	end
	RunService:UnbindFromRenderStep("MapTour")
	camera.FieldOfView = Settings.get("FieldOfView") :: number
	Net.event("MapTour"):FireServer(key)
end

-- A match's end: the next map not asked for yet.
function MatchCutscene.forgetLoad()
	loadingKey = ""
	MapLoader.forget()
end

-- The next map the armory asked for is loaded here (or none was asked for: a joiner, a fresh server).
function MatchCutscene.ready(): boolean
	return loadingKey == "" or MapLoader.loaded(loadingKey)
end

-- How much of the next map is streamed in (0..1; 0 before the server asks).
function MatchCutscene.loaded(): number
	local st = MapLoader.state()
	if loadingKey == "" or not st or st.key ~= loadingKey then
		return 0
	end
	return MapLoader.progress()
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
	local fov = pose.fov or Cfg.Fov
	if shot.kind == "Self" then
		-- round your own soldier, then one move to the game's own camera behind it, held still for the hand-over
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local a, blend = Rules.selfPose(shot, u)
			local back = CFrame.Angles(0, a, 0):VectorToWorldSpace(-root.CFrame.LookVector)
			local feet = root.Position - Vector3.new(0, 3, 0)
			local round = CFrame.lookAt(
				feet + back * shot.radius + Vector3.new(0, shot.up, 0),
				feet + Vector3.new(0, shot.lookUp, 0)
			)
			local view, viewFov = gameView(root, player.Character:FindFirstChildOfClass("Humanoid"))
			cf = round:Lerp(view, blend)
			fov += (viewFov - fov) * blend
		end
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cf
	camera.FieldOfView = fov
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
	local anchors = Rules.anchors(map, home, winner, Cfg.LandmarkReach)
	cut = clearViews(cut, map, key, anchors, points)
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
		anchors = anchors,
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
			Rules.partTwo(Cfg.Speech, cut, if type(ownKit) == "string" then ownKit else nil, key, #map.sectors, {
				map = map.name,
				places = Rules.placeNames(map, Cfg.Names, Cfg.LandmarkReach, Cfg.Speech.fallback.unnamed),
			})
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
		local d = if folder and folder:GetAttribute(FrontCfg.DipKindAttribute) == "Flight"
			then Cfg.FlightDip
			else Cfg.Dip
		local k = Rules.dip(workspace:GetServerTimeNow(), if type(at) == "number" then at else nil, d)
		black.Visible = k > 0
		black.BackgroundTransparency = 1 - k
	end)
end

function MatchCutscene.start()
	build()
	dips()
	Net.event("MapLoad").OnClientEvent:Connect(function(key: unknown, assets: unknown)
		if type(key) == "string" then
			loadMap(key, if type(assets) == "table" then assets :: { string } else {})
		end
	end)
	Net.event("MapTour").OnClientEvent:Connect(function(key: unknown)
		if type(key) == "string" then
			tour(key)
		end
	end)
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
			-- (a slow connection: the next map not loaded here yet, so the armory stays, src/client/EndScenes, and the
			-- flight joins where it is once it's in)
			local waiting = phase == "Countdown" and not MatchCutscene.ready()
			if phase ~= seen and not waiting then
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
