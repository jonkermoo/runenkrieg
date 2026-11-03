--!strict
-- The end of a Normal match after the fade (user 2026-11-02; Config/Cutscenes Table / Board / Armory / Speech,
-- Workspace.Frontline's Phase "Table", "Vote", "Loading"), on the server's clock for every player:
-- - Table: the battle table in the command tent, the played map's sketch sheet flat on it with this match's captures
--   redrawn in red pencil, the after-action report flat beside it typing itself out (Net "MatchResults": the winner,
--   the length, the honours, your own line), the camera drifting over both;
-- - Vote: the camera turns round to the map board on the tent wall: "ORDERS · THE NEXT FRONT", a sheet per offered map
--   (a placeholder for an empty slot) and the operations plan. Those who may sign (the Player's MaySign, src/server/
--   MapVote) click a sheet to sign it (Net "MapVote"); every signature is written letter by letter in the signer's
--   nation's ink. At the pick (VotePick) an R6 arm in the winners' uniform holding a wooden stamp stamps NEXT on it;
-- - Loading: the empty armory, a slow drift on each approved angle in turn, while the narrator speaks the first part
--   (src/client/Speech); it gives way to the pre-match flight at the countdown (src/client/MatchCutscene), or, if the
--   match waits for players, once the narrator is done.
-- The sets are built on each client at Config/Cutscenes.Stage (placeholders until the approved renders are modelled).
-- Widescreen bars throughout; the HUD and the rest are covered (MatchCutscene.cover).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Cutscenes)
local FrontCfg = require(Shared.Config.Frontline)
local Palette = require(Shared.Config.Palette)
local U = require(Shared.Config.Uniforms)
local LiveMap = require(Shared.LiveMap)
local Net = require(Shared.Net)
local Rules = require(Shared.Rules.Cutscenes)
local MatchCam = require(script.Parent.MatchCam)
local MatchCutscene = require(script.Parent.MatchCutscene)
local SketchMap = require(script.Parent.SketchMap)
local Speech = require(script.Parent.Speech)

local EndScenes = {}

local GR = (Palette.UI :: any).Grimoire
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local PAPER, INK, PENCIL = rgb(GR.paper), rgb(GR.ink), rgb(GR.pencil)
local TYPE = Font.fromEnum(Enum.Font.Code)
local HAND = Font.fromEnum(Enum.Font.IndieFlower)
local BOLD = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Bold)
local V = Vector3.new
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function v3(a: { number }): Vector3
	return V(a[1], a[2], a[3])
end
local function nationOf(kit: string?): string
	local k = kit and (U.Kits :: any)[kit]
	return if k then k.team else ""
end
-- a nation's ink on paper: its name colour taken most of the way to ink
local function inkOf(kit: string?): Color3
	local c = kit and GR.Name[kit]
	return if c then rgb(c):Lerp(INK, 0.55) else INK
end

-- the sets ------------------------------------------------------------------------------------------------------------
local set: Folder? = nil
local tableTop: Vector3, boardBase: Vector3, armory: Vector3
local mapSurface: Frame, reportLines: { TextLabel } = nil :: any, {}
local mapSheet: any = nil
local sheetGuis: { SurfaceGui } = {}

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Size, p.CFrame, p.Color = size, cf, color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = set
	return p
end

local function surface(on: BasePart, face: Enum.NormalId, interactive: boolean?): (SurfaceGui, Frame)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = Cfg.PixelsPerStud
	g.LightInfluence = 0.6
	g.Adornee = on
	g.ResetOnSpawn = false
	-- (a gui that takes clicks lives in the PlayerGui, pointed at its part)
	g.Parent = if interactive then player:WaitForChild("PlayerGui") else on
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = PAPER
	f.BorderSizePixel = 0
	f.Parent = g
	return g, f
end

local function text(parent: Instance, s: string, font: Font, color: Color3, y: number, h: number): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextColor3 = color
	l.TextScaled = true
	l.Text = s
	l.Position = UDim2.fromScale(0.06, y)
	l.Size = UDim2.fromScale(0.88, h)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function buildTent(origin: Vector3)
	local T, B = Cfg.Table, Cfg.Board
	local canvas, wood, dark = Color3.fromRGB(154, 140, 104), Color3.fromRGB(108, 76, 46), Color3.fromRGB(62, 46, 32)
	part("Floor", V(40, 1, 40), CFrame.new(origin - V(0, 0.5, 0)), Color3.fromRGB(92, 78, 58), Enum.Material.WoodPlanks)
	for _, w in
		{
			{ V(40, 16, 1), V(0, 8, -20) },
			{ V(40, 16, 1), V(0, 8, 20) },
			{ V(1, 16, 40), V(-20, 8, 0) },
			{ V(1, 16, 40), V(20, 8, 0) },
		}
	do
		part("Canvas", w[1], CFrame.new(origin + w[2]), canvas, Enum.Material.Fabric)
	end
	part("Roof", V(40, 1, 40), CFrame.new(origin + V(0, 16, 0)), canvas, Enum.Material.Fabric)
	tableTop = origin + V(0, T.top, 0)
	part("TableTop", V(T.size[1], 0.4, T.size[2]), CFrame.new(tableTop - V(0, 0.2, 0)), wood, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local at = V(sx * (T.size[1] / 2 - 0.6), T.top / 2, sz * (T.size[2] / 2 - 0.6))
			part("Leg", V(0.5, T.top - 0.4, 0.5), CFrame.new(origin + at - V(0, 0.2, 0)), dark, Enum.Material.Wood)
		end
	end
	local lamp = part("Lamp", V(1.2, 0.8, 1.2), CFrame.new(tableTop + V(0, 7, 0)), Color3.fromRGB(70, 60, 44))
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = 24, 2.2, Color3.fromRGB(255, 214, 160)
	light.Shadows = true
	light.Parent = lamp
	-- the played map, flat on the table (its replay drawn on it), and the after-action report beside it
	local m = T.map
	local sheet =
		part("MapSheet", V(m.size[1], 0.05, m.size[2]), CFrame.new(tableTop + V(m.at[1], 0.03, m.at[2])), PAPER)
	local _, f = surface(sheet, Enum.NormalId.Top)
	f.BackgroundTransparency = 1
	mapSurface = f
	local r = T.report
	local rcf = CFrame.new(tableTop + V(r.at[1], 0.04, r.at[2])) * CFrame.Angles(0, math.rad(r.tilt), 0)
	local report = part("Report", V(r.size[1], 0.05, r.size[2]), rcf, PAPER)
	local _, rf = surface(report, Enum.NormalId.Top)
	for k = 1, T.lines do
		local l =
			text(rf, "", if k == 1 then BOLD else TYPE, INK, 0.05 + (k - 1) * (0.9 / T.lines), 0.9 / T.lines * 0.7)
		table.insert(reportLines, l)
	end
	-- the game's props round them, flat (placeholders: the render's are modelled later)
	part("Rifle", V(7, 0.25, 0.35), CFrame.new(tableTop + V(-3, 0.13, -3.6)) * CFrame.Angles(0, math.rad(8), 0), dark)
	part("Helmet", V(1.6, 0.7, 1.6), CFrame.new(tableTop + V(5.5, 0.35, -3.4)), Color3.fromRGB(96, 104, 92))
	part("Glasses", V(1, 0.4, 0.7), CFrame.new(tableTop + V(2.4, 0.2, -3.6)), Color3.fromRGB(40, 38, 34))
	for k = 0, 2 do
		local c = part(
			"Case",
			V(0.25, 0.9, 0.25),
			CFrame.new(tableTop + V(-7 + k * 0.4, 0.13, 3.6)) * CFrame.Angles(0, 0, math.rad(90)),
			Color3.fromRGB(176, 140, 70),
			Enum.Material.Metal
		)
		c.Shape = Enum.PartType.Cylinder
	end
	part("InkPot", V(0.5, 0.5, 0.5), CFrame.new(tableTop + V(2.6, 0.25, 3.8)), Color3.fromRGB(28, 30, 40))
	-- the map board on the tent wall behind the table, facing it
	boardBase = origin + V(0, 0, -B.behind)
	local bcf = CFrame.lookAt(boardBase + V(0, B.size[2] / 2 + 0.6, 0), boardBase + V(0, B.size[2] / 2 + 0.6, 10))
	local board = part("Board", V(B.size[1], B.size[2], 0.4), bcf, wood, Enum.Material.Wood)
	local _, bf = surface(board, Enum.NormalId.Front)
	bf.BackgroundTransparency = 1
	local title = text(bf, "ORDERS · THE NEXT FRONT", BOLD, PAPER, 0.02, 0.09)
	title.TextXAlignment = Enum.TextXAlignment.Center
end

-- the armory (placeholder room): an empty hall, racks with gaps, a stripped field gun, helmets, a workbench, a door
local function buildArmory(o: Vector3)
	local brick, floor, wood, steel =
		Color3.fromRGB(122, 84, 64), Color3.fromRGB(92, 92, 86), Color3.fromRGB(104, 74, 46), Color3.fromRGB(78, 84, 80)
	part("Floor", V(36, 1, 40), CFrame.new(o - V(0, 0.5, 0)), floor, Enum.Material.Concrete)
	for _, w in { { V(36, 14, 1), V(0, 7, -20) }, { V(1, 14, 40), V(-18, 7, 0) }, { V(1, 14, 40), V(18, 7, 0) } } do
		part("Wall", w[1], CFrame.new(o + w[2]), brick, Enum.Material.Brick)
	end
	-- the doorway wall: two halves and a lintel round a lit opening
	part("Wall", V(15, 14, 1), CFrame.new(o + V(-10.5, 7, 20)), brick, Enum.Material.Brick)
	part("Wall", V(15, 14, 1), CFrame.new(o + V(10.5, 7, 20)), brick, Enum.Material.Brick)
	part("Lintel", V(6, 6, 1), CFrame.new(o + V(0, 11, 20)), brick, Enum.Material.Brick)
	local day =
		part("Daylight", V(6, 8, 0.2), CFrame.new(o + V(0, 4, 20.6)), Color3.fromRGB(250, 236, 200), Enum.Material.Neon)
	local sun = Instance.new("SurfaceLight")
	sun.Face, sun.Range, sun.Brightness, sun.Angle = Enum.NormalId.Back, 30, 3, 70
	sun.Parent = day
	part("Roof", V(36, 1, 40), CFrame.new(o + V(0, 14, 0)), wood, Enum.Material.WoodPlanks)
	local shaft = part(
		"Shaft",
		V(3, 14, 3),
		CFrame.new(o + V(4, 7, -6)) * CFrame.Angles(0, 0, math.rad(18)),
		Color3.fromRGB(255, 236, 190),
		Enum.Material.Neon
	)
	shaft.Transparency = 0.93
	-- the rifle racks (gaps where rifles went), the field gun off its carriage, the helmets, the workbench
	for k = 0, 1 do
		part("Rack", V(0.6, 6, 10), CFrame.new(o + V(-17, 3, -4 + k * 12)), wood, Enum.Material.Wood)
		for r = 0, 7 do
			if r % 3 ~= 1 then
				part(
					"Rifle",
					V(0.3, 4.6, 0.3),
					CFrame.new(o + V(-16.4, 2.6, -8 + k * 12 + r * 1.1)) * CFrame.Angles(0, 0, math.rad(-8)),
					Color3.fromRGB(70, 50, 34)
				)
			end
		end
	end
	local barrel = part(
		"Barrel",
		V(9, 1.1, 1.1),
		CFrame.new(o + V(7, 0.6, -1)) * CFrame.Angles(0, math.rad(24), 0),
		steel,
		Enum.Material.Metal
	)
	barrel.Shape = Enum.PartType.Cylinder
	part("Carriage", V(4, 1.6, 2.4), CFrame.new(o + V(9, 0.8, 4)), Color3.fromRGB(86, 92, 72), Enum.Material.Metal)
	local wheel = part(
		"Wheel",
		V(0.5, 4.5, 4.5),
		CFrame.new(o + V(4, 2.2, -8)) * CFrame.Angles(0, 0, math.rad(12)),
		wood,
		Enum.Material.Wood
	)
	wheel.Shape = Enum.PartType.Cylinder
	part("Shelf", V(1.2, 0.3, 10), CFrame.new(o + V(17.2, 5, -2)), wood, Enum.Material.Wood)
	for k = 0, 3 do
		if k ~= 2 then
			part(
				"Helmet",
				V(1.4, 0.7, 1.4),
				CFrame.new(o + V(17.2, 5.5, -6 + k * 2.6)),
				Color3.fromRGB(96, 104, 92),
				Enum.Material.Metal
			)
		end
	end
	part("Workbench", V(8, 0.5, 3), CFrame.new(o + V(-2, 2.6, -18)), wood, Enum.Material.Wood)
	part("Vice", V(0.8, 0.8, 0.8), CFrame.new(o + V(-4.5, 3.2, -17.6)), steel, Enum.Material.Metal)
	for _, x in { -5, 1 } do
		part("Crate", V(2.4, 2, 2.4), CFrame.new(o + V(x, 1, 10)), wood, Enum.Material.WoodPlanks)
	end
	armory = o
end

local function buildSets()
	if set then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "EndScenesSet"
	set = f
	buildTent(v3(Cfg.Stage.tent))
	buildArmory(v3(Cfg.Stage.armory))
	f.Parent = workspace
end

-- the screen: the bars, the hint over the board, a modal button that frees the mouse while signing
local gui: ScreenGui, hint: TextLabel, freeMouse: TextButton
local function buildGui()
	gui = Instance.new("ScreenGui")
	gui.Name = "EndScenes"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = Cfg.DisplayOrder
	gui.Enabled = false
	for i = 0, 1 do
		local bar = Instance.new("Frame")
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Size = UDim2.fromScale(1, Cfg.Bars)
		bar.AnchorPoint = Vector2.new(0, i)
		bar.Position = UDim2.fromScale(0, i)
		bar.Parent = gui
	end
	hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.FontFace = BOLD
	hint.TextColor3 = rgb(GR.text)
	hint.TextScaled = true
	hint.AnchorPoint = Vector2.new(0.5, 0.5)
	hint.Position = UDim2.fromScale(0.5, Cfg.Bars / 2)
	hint.Size = UDim2.fromScale(0.6, Cfg.Bars * 0.45)
	hint.Text = ""
	hint.Parent = gui
	freeMouse = Instance.new("TextButton")
	freeMouse.BackgroundTransparency = 1
	freeMouse.Text = ""
	freeMouse.Size = UDim2.fromOffset(1, 1)
	freeMouse.Modal = true
	freeMouse.Visible = false
	freeMouse.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
end

-- the board's sheets ----------------------------------------------------------------------------------------------------
type Sheet =
	{ key: string?, gui: SurfaceGui, names: Frame, stamp: TextLabel, signed: { [string]: TextLabel }, art: any }
local sheets: { Sheet } = {}

local function clearSheets()
	for _, s in sheets do
		if s.art then
			s.art.destroy()
		end
		s.gui:Destroy()
	end
	table.clear(sheets)
	for _, g in sheetGuis do
		g:Destroy()
	end
	table.clear(sheetGuis)
	local old = set and (set :: Folder):FindFirstChild("Sheets")
	if old then
		old:Destroy()
	end
end

local function buildSheets(offer: { string }, winnerKit: string?)
	clearSheets()
	local B = Cfg.Board
	local holder = Instance.new("Folder")
	holder.Name = "Sheets"
	holder.Parent = set
	local w, h, gap = B.sheet.width, B.sheet.height, B.sheet.gap
	local row = B.slots * w + (B.slots - 1) * gap + gap + B.plan.width
	local x0 = -row / 2 + w / 2
	local y = B.size[2] / 2 + 0.3
	for i = 1, B.slots do
		local key = offer[i]
		local at = boardBase + V(x0 + (i - 1) * (w + gap), y, 0.25)
		local cf = CFrame.lookAt(at, at + V(0, 0, 1))
			* CFrame.Angles(0, 0, math.rad((if i % 2 == 0 then 1 else -1) * B.sheet.tilt))
		local p = Instance.new("Part")
		p.Name = "Sheet" .. i
		p.Anchored, p.CanCollide, p.CanTouch = true, false, false
		p.Size, p.CFrame, p.Color = V(w, h, 0.05), cf, PAPER
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = holder
		local g, f = surface(p, Enum.NormalId.Front, key ~= nil)
		table.insert(sheetGuis, g)
		local m = key and LiveMap.get(key)
		local name = text(f, if m then m.name else "Map " .. i, BOLD, if key then INK else rgb(GR.inkDim), 0.03, 0.09)
		name.TextXAlignment = Enum.TextXAlignment.Center
		local region =
			text(f, if key then Cfg.Vote.Regions[key] or "" else B.placeholder, TYPE, rgb(GR.inkDim), 0.12, 0.05)
		region.TextXAlignment = Enum.TextXAlignment.Center
		local art = Instance.new("Frame")
		art.BackgroundTransparency = 1
		art.Position = UDim2.fromScale(0.05, 0.19)
		art.Size = UDim2.fromScale(0.9, 0.9 * (w / h) * 295 / 1024)
		art.Parent = f
		local names = Instance.new("Frame")
		names.BackgroundTransparency = 1
		names.Position = UDim2.fromScale(0.08, 0.42)
		names.Size = UDim2.fromScale(0.84, 0.54)
		names.Parent = f
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0.01, 0)
		list.Parent = names
		local stamp = text(f, "NEXT", BOLD, PENCIL, 0.5, 0.22)
		stamp.TextXAlignment = Enum.TextXAlignment.Center
		stamp.Rotation = -12
		stamp.Visible = false
		local sheet: Sheet = { key = key, gui = g, names = names, stamp = stamp, signed = {}, art = nil }
		if key then
			sheet.art = SketchMap.new(art, key, { still = true })
			local button = Instance.new("TextButton")
			button.BackgroundTransparency = 1
			button.Text = ""
			button.Size = UDim2.fromScale(1, 1)
			button.Parent = f
			button.Activated:Connect(function()
				if player:GetAttribute("MaySign") == true then
					Net.event("MapVote"):FireServer(key)
				end
			end)
		end
		table.insert(sheets, sheet)
	end
	-- the operations plan, pinned beside the sheets
	local px = x0 + B.slots * (w + gap) - w / 2 + B.plan.width / 2
	local at = boardBase + V(px, y + (h - B.plan.height) / 2, 0.25)
	local p = Instance.new("Part")
	p.Name = "Plan"
	p.Anchored, p.CanCollide, p.CanTouch = true, false, false
	p.Size, p.CFrame, p.Color = V(B.plan.width, B.plan.height, 0.05), CFrame.lookAt(at, at + V(0, 0, 1)), PAPER
	p.Parent = holder
	local _, pf = surface(p, Enum.NormalId.Front)
	local lines = if winnerKit then B.planLines else B.noWinnerLines
	for k, l in lines do
		text(
			pf,
			Rules.text(l, { winner = nationOf(winnerKit) }),
			if k == 1 then BOLD else TYPE,
			INK,
			0.05 + (k - 1) * 0.12,
			0.08
		)
	end
end

-- the signatures on each sheet from the folder's Votes_<key> ("Name:kit|..."), new ones written letter by letter
local function updateSignatures(folder: Instance)
	for _, s in sheets do
		if s.key then
			local raw = folder:GetAttribute(`Votes_{s.key}`)
			local seen: { [string]: boolean } = {}
			for _, entry in (if type(raw) == "string" and raw ~= "" then string.split(raw, "|") else {}) do
				local name, kit = string.match(entry, "^(.-):(.*)$")
				if name then
					seen[name] = true
					if not s.signed[name] then
						local l = Instance.new("TextLabel")
						l.BackgroundTransparency = 1
						l.FontFace = HAND
						l.TextScaled = true
						l.TextColor3 = inkOf(kit)
						l.Size = UDim2.fromScale(1, 0.13)
						l.TextXAlignment = Enum.TextXAlignment.Left
						l.Text = name
						l.MaxVisibleGraphemes = 0
						l.Parent = s.names
						s.signed[name] = l
						local start = os.clock()
						task.spawn(function()
							while l.Parent and l.MaxVisibleGraphemes < #name do
								local k = math.clamp((os.clock() - start) / Cfg.Board.write, 0, 1)
								l.MaxVisibleGraphemes = math.ceil(k * #name)
								task.wait()
							end
						end)
					end
				end
			end
			for name, l in s.signed do
				if not seen[name] then -- (signed another sheet instead)
					l:Destroy()
					s.signed[name] = nil
				end
			end
		end
	end
end

-- the stamping arm: an R6 right arm in the winners' uniform, a wooden stamp in its hand
local arm: Model? = nil
local function stampArm(kit: string?, sheet: Sheet, at: CFrame)
	if arm then
		(arm :: Model):Destroy()
	end
	local A = Cfg.Board.arm
	local k = (U.Kits :: any)[kit or U.Default] or (U.Kits :: any)[U.Default]
	local m = Instance.new("Model")
	m.Name = "StampArm"
	local hum = Instance.new("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.RigType = Enum.HumanoidRigType.R6
	hum.Parent = m
	local torso = Instance.new("Part")
	torso.Name = "Torso"
	torso.Size, torso.Transparency = V(2, 2, 1), 1
	torso.Anchored, torso.CanCollide = true, false
	torso.Parent = m
	local limb = Instance.new("Part")
	limb.Name = "Right Arm"
	limb.Size = V(1, 2, 1)
	limb.Anchored, limb.CanCollide = true, false
	limb.Color = rgb(k.skin)
	limb.Parent = m
	local colors = Instance.new("BodyColors")
	colors.RightArmColor3 = rgb(k.skin)
	colors.Parent = m
	local shirt = Instance.new("Shirt")
	shirt.ShirtTemplate = `rbxassetid://{k.shirt}`
	shirt.Parent = m
	local block = Instance.new("Part")
	block.Name = "Stamp"
	block.Size = v3(A.stamp)
	block.Anchored, block.CanCollide = true, false
	block.Color = Color3.fromRGB(110, 78, 48)
	block.Material = Enum.Material.Wood
	block.Parent = m
	m.Parent = set
	arm = m
	-- the arm lies along the board's normal, its hand (the lower end) toward the sheet, the stamp under the hand
	local function place(out: number)
		local face = at.Position + at.LookVector * (A.stamp[3] / 2 + out)
		local blockCf = CFrame.lookAt(face, face + at.LookVector)
		block.CFrame = blockCf
		limb.CFrame = blockCf * CFrame.new(0, 0, -(A.stamp[3] / 2 + 1)) * CFrame.Angles(math.rad(90), 0, 0)
		torso.CFrame = limb.CFrame * CFrame.new(-1.5, 1, 0)
	end
	task.spawn(function()
		local side = at.RightVector * A.reach
		local t0 = os.clock()
		-- in from the side, over the sheet
		while os.clock() - t0 < A.down + 0.4 do
			local u = math.clamp((os.clock() - t0) / (A.down + 0.4), 0, 1)
			local ease = Rules.ease(u)
			place(A.lift)
			local shift = side * (1 - ease)
			for _, p in { block, limb, torso } do
				p.CFrame += shift
			end
			task.wait()
		end
		-- down: the thump, the stamp left on the sheet
		t0 = os.clock()
		while os.clock() - t0 < A.down do
			place(A.lift * (1 - math.clamp((os.clock() - t0) / A.down, 0, 1)))
			task.wait()
		end
		place(0)
		sheet.stamp.Visible = true
		task.wait(A.hold)
		t0 = os.clock()
		while os.clock() - t0 < A.up do
			place(A.lift * math.clamp((os.clock() - t0) / A.up, 0, 1))
			task.wait()
		end
	end)
end

-- the scenes ------------------------------------------------------------------------------------------------------------
local results: any = nil -- the latest Normal results (Net "MatchResults")
local scene: string? = nil
local sceneAt = 0 -- server time the scene started
local covered = false
local picked: string? = nil
local speechStarted = false

local function lookCf(from: Vector3, to: Vector3): CFrame
	return CFrame.lookAt(from, to)
end

local function tableCam(t: number): CFrame
	local shots = Cfg.Table.shots
	local t0 = 0
	for _, s in shots do
		if t < s.t1 or s == shots[#shots] then
			local u = math.clamp((t - t0) / (s.t1 - t0), 0, 1)
			local e = Rules.ease(u)
			return lookCf(tableTop + v3(s.from):Lerp(v3(s.to), e), tableTop + v3(s.look))
		end
		t0 = s.t1
	end
	return CFrame.new()
end

local function boardCam(t: number): CFrame
	local B = Cfg.Board
	local s = B.shot
	local u = math.clamp(t / FrontCfg.VoteSeconds, 0, 1)
	local cf = lookCf(boardBase + v3(s.from):Lerp(v3(s.to), Rules.ease(u)), boardBase + v3(s.look))
	if t < B.turn then -- (turning round from the table)
		cf = tableCam(Cfg.Table.shots[#Cfg.Table.shots].t1):Lerp(cf, Rules.ease(t / B.turn))
	end
	return cf
end

local function armoryCam(t: number): CFrame
	local A = Cfg.Armory
	local i = math.floor(t / A.cut) % #A.shots + 1
	local s = A.shots[i]
	local u = (t % A.cut) / A.cut
	return lookCf(armory + v3(s.from):Lerp(v3(s.to), u), armory + v3(s.look))
end

local function typeReport(t: number)
	local T = Cfg.Table
	for k, l in reportLines do
		local start = T.typing.lead + (k - 1) * T.typing.type
		local u = math.clamp((t - start) / T.typing.type, 0, 1)
		l.MaxVisibleGraphemes = math.floor(u * #l.Text + 0.5)
	end
end

local function fillReport()
	local r = results or {}
	local winnerKit = r.winner
	local lines = {
		"AFTER-ACTION REPORT",
		`{if r.map then LiveMap.get(r.map).name else ""} · {math.floor((r.length or 0) / 60)} min`,
		if winnerKit then `{string.upper(nationOf(winnerKit))} holds the field` else "NO VICTOR",
	}
	for _, h in { { "Kills", "kills" }, { "Healed", "HP healed" }, { "Built", "HP built" } } do
		local got = r.honours and r.honours[h[1]]
		table.insert(lines, if got then `{got.name} · {got.value} {h[2]}` else `Nobody · {h[2]}`)
	end
	local you = r.you or {}
	table.insert(
		lines,
		`You · {you.Kills or 0} kills · {you.Healed or 0} healed · {you.Built or 0} built · +{you.Earned or 0}`
	)
	for k, l in reportLines do
		l.Text = lines[k] or ""
		l.TextColor3 = if k == #lines then PENCIL else INK
		l.MaxVisibleGraphemes = 0
	end
	-- the played map on the table, this match's captures redrawn on it
	if mapSheet then
		mapSheet.destroy()
		mapSheet = nil
	end
	local key = if type(r.map) == "string" then r.map else LiveMap.key()
	local holder = mapSurface:FindFirstChild("Map") or Instance.new("Frame")
	holder.Name = "Map"
	(holder :: Frame).BackgroundTransparency = 1
	(holder :: Frame).Size = UDim2.fromScale(1, 1)
	holder.Parent = mapSurface
	mapSheet = SketchMap.new(holder :: Frame, key, {})
	mapSheet.replay(r.log or {}, winnerKit ~= nil)
end

local function finish()
	if not scene then
		return
	end
	scene = nil
	RunService:UnbindFromRenderStep("EndScenes")
	gui.Enabled = false
	freeMouse.Visible = false
	if arm then
		(arm :: Model):Destroy()
		arm = nil
	end
	if covered then
		covered = false
		MatchCutscene.cover(false)
	end
	if not MatchCam.running() then
		camera.CameraType = Enum.CameraType.Custom
		local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if h then
			camera.CameraSubject = h
		end
	end
end

local function step()
	local folder = workspace:FindFirstChild(FrontCfg.FolderName)
	if not folder or not scene then
		return
	end
	local t = workspace:GetServerTimeNow() - sceneAt
	local cf
	if scene == "Table" then
		cf = tableCam(t)
		typeReport(t)
	elseif scene == "Vote" then
		cf = boardCam(t)
		updateSignatures(folder)
		local pick = folder:GetAttribute("VotePick")
		if type(pick) == "string" and pick ~= picked then
			picked = pick
			for _, s in sheets do
				if s.key == pick then
					local spoken = folder:GetAttribute(FrontCfg.SpeechAttribute)
					local kitText = if type(spoken) == "string" then string.split(spoken, ",")[1] else "none"
					stampArm(if kitText ~= "none" then kitText else nil, s, (s.gui.Adornee :: BasePart).CFrame)
				end
			end
			freeMouse.Visible = false
			hint.Text = ""
		end
	else
		cf = armoryCam(t)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cf
	camera.FieldOfView = Cfg.Fov
	UserInputService.MouseIconEnabled = scene == "Vote"
end

local function begin(name: string, folder: Instance)
	buildSets()
	local endsAt = folder:GetAttribute("PhaseEndsAt")
	local length = if name == "Table" then FrontCfg.TableSeconds elseif name == "Vote" then FrontCfg.VoteSeconds else 0
	sceneAt = if type(endsAt) == "number" and length > 0 then endsAt - length else workspace:GetServerTimeNow()
	scene = name
	if not covered then
		covered = true
		MatchCutscene.cover(true)
	end
	gui.Enabled = true
	hint.Text = ""
	freeMouse.Visible = false
	local spoken = folder:GetAttribute(FrontCfg.SpeechAttribute)
	local parts = if type(spoken) == "string" then string.split(spoken, ",") else { "none", LiveMap.key() }
	local winnerKit = if parts[1] ~= "none" then parts[1] else nil
	if name == "Table" then
		fillReport()
	elseif name == "Vote" then
		picked = nil
		local offer = folder:GetAttribute("VoteOffer")
		buildSheets(if type(offer) == "string" then string.split(offer, ",") else {}, winnerKit)
		local may = player:GetAttribute("MaySign") == true
		hint.Text = if may then Cfg.Vote.hint else Rules.text(Cfg.Vote.watch, { winner = nationOf(winnerKit) })
		freeMouse.Visible = may
	elseif name == "Loading" and not speechStarted then
		speechStarted = true
		Speech.stop()
		Speech.queue(Rules.partOne(Cfg.Speech, winnerKit, parts[2] or LiveMap.key(), nationOf(winnerKit)), os.clock())
	end
	MatchCutscene.clearFade() -- (the set is up: the fade's colour gives way to it)
	RunService:UnbindFromRenderStep("EndScenes")
	RunService:BindToRenderStep("EndScenes", Enum.RenderPriority.Camera.Value + 3, step)
end

function EndScenes.start()
	buildGui()
	Net.event("MatchResults").OnClientEvent:Connect(function(r: any)
		if type(r) == "table" and r.mode == "Normal" then
			results = r
		end
	end)
	local seen: string? = nil
	task.spawn(function()
		while true do
			local folder = workspace:FindFirstChild(FrontCfg.FolderName)
			local phase = folder and folder:GetAttribute("Phase")
			if phase ~= seen then
				seen = phase :: string?
				if folder and (phase == "Table" or phase == "Vote" or phase == "Loading") then
					begin(phase :: string, folder)
				elseif phase == "Fade" then
					speechStarted = false
				elseif scene then
					-- the countdown takes over (the flight); waiting for players, the armory stays till the narrator ends
					if phase == "Waiting" and scene == "Loading" then
						task.spawn(function()
							while Speech.busy() and scene == "Loading" do
								task.wait(0.2)
							end
							if scene == "Loading" then
								finish()
							end
						end)
					else
						finish()
					end
				end
			end
			task.wait(0.1)
		end
	end)
end

return EndScenes
