--!strict
-- The command post (the approved render, user 2026-11-03; Config/Cutscenes Post / Table / Board): the set the end
-- of a Normal match plays in (src/client/EndScenes runs the scenes and the cameras). A flat-roofed timber hut; the war
-- table in the middle with one sheet over its top (the played map's sketch with this match's captures, the grid, a
-- legend), the game's own models on it and the after-action report on its lower right; the orders board on the back
-- wall: "VOTE" and the time left, one OPERATION ORDER per map on offer with its signature grid, photos on red string,
-- a field telegram with the plan. Built on each client, out of every map's sight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetsCfg = require(Shared.Config.Assets) :: any
local Cfg = require(Shared.Config.Cutscenes)
local Palette = require(Shared.Config.Palette) :: any
local SketchCfg = require(Shared.Config.SketchMap) :: any
local WeaponsCfg = require(Shared.Config.Weapons) :: any
local LiveMap = require(Shared.LiveMap)
local Rules = require(Shared.Rules.Cutscenes)
local Ink = require(script.Parent.Ink)
local SketchMap = require(script.Parent.SketchMap)

local CommandPost = {}

local GR = Palette.UI.Grimoire
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local PAPER, INK, PENCIL, DIM = rgb(GR.paper), rgb(GR.ink), rgb(GR.pencil), rgb(GR.inkDim)
local TYPE = Font.fromEnum(Enum.Font.Code)
local HAND = Font.fromEnum(Enum.Font.IndieFlower)
local SLAB = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Bold)
local V = Vector3.new
local CHAR = 0.62 -- a letter's width over the text size (Code, RobotoMono)
local player = Players.LocalPlayer

local WOOD, DARK, PLANK = Color3.fromRGB(122, 84, 50), Color3.fromRGB(58, 40, 26), Color3.fromRGB(98, 70, 46)
local CORK, STEEL = Color3.fromRGB(150, 112, 72), Color3.fromRGB(70, 72, 76)

local function v3(a: { number }): Vector3
	return V(a[1], a[2], a[3])
end

export type Order = {
	key: string?,
	part: BasePart,
	gui: SurfaceGui,
	grid: Frame,
	count: TextLabel,
	stamp: TextLabel,
	signed: { [string]: TextLabel },
	art: any,
	-- (Field kit) the count's last value and when it last went up, the value rolling out, the paper's place
	n: number,
	rollAt: number,
	countOld: TextLabel,
	rest: CFrame,
}
export type Post = {
	origin: Vector3,
	tableTop: Vector3,
	board: CFrame, -- the board's middle, facing the room
	strip: Frame, -- the played map's place on the table sheet
	report: Frame,
	telegram: Frame,
	timer: TextLabel, -- the vote's time left
	lamp: BasePart,
	folder: Folder,
	orders: { Order },
	orderAt: { CFrame }, -- each order's paper (its front toward the room)
	orderSize: Vector2,
	sheetAspect: number, -- the table sheet's width over its height
	reportPx: number, -- the report's and the telegram's heights in pixels
	telegramPx: number,
	pins: boolean, -- pins drawn for the orders (the parts set; the model has its own)
	-- (Field kit, user 2026-11-03) a place on the table sheet (shares of its face: x right, y down), on its face
	sheetAt: (Vector2) -> Vector3,
	tableKit: Folder, -- the blocks and pennants, laid for each match's map
	blocks: { [string]: Model },
	pennants: { Model },
	doneAt: { [number]: number }, -- when each capture of the replay was first seen drawn (os.clock)
	light: BasePart?, -- the lamp's light (it sways), and where it hangs
	lightAt: CFrame,
	hand: BasePart, -- the stopwatch's hand, and the dial's middle (facing the room)
	dial: CFrame,
	stringFrom: BasePart, -- the red string's ends: its pin under the sign, and the end at the leader
	stringTo: BasePart,
	beam: Beam,
	leader: number?,
	leadAt: number, -- (os.clock) when the string set off for the leader, from `leadFrom`
	leadFrom: Vector3,
	title: TextLabel, -- the sheet's title ("SHEET 1 - <map>")
}

-- pieces ---------------------------------------------------------------------------------------------------------------
local function part(
	parent: Instance,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Size, p.CFrame, p.Color = size, cf, color
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function surface(on: BasePart, face: Enum.NormalId, pps: number, interactive: boolean?): (SurfaceGui, Frame)
	local g = Instance.new("SurfaceGui")
	g.Face = face
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = pps
	g.LightInfluence = 0.35 -- (the lamp mustn't bleach one paper whiter than the next)
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

local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.Parent = parent
	return f
end

-- a line of text `h` of its paper tall (its size fixed from the paper's height in pixels, so lines of one size match)
local function text(
	parent: Instance,
	s: string,
	font: Font,
	color: Color3,
	x: number,
	y: number,
	w: number,
	h: number,
	px: number
): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = font
	l.TextColor3 = color
	l.TextWrapped = false
	l.Text = s
	l.Position = UDim2.fromScale(x, y)
	l.Size = UDim2.fromScale(w, h)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	-- its size: the line's height, shrunk so a long line stays on its paper (the fonts' letters are all about `CHAR`
	-- of the size wide; TextScaled came out at 8 px on the board's papers, Studio 2026-11-03)
	local most = math.max(6, math.floor(h * px * 0.9))
	local wide = l.AbsoluteSize.X
	l.TextSize = if wide > 0 and #s > 0 then math.clamp(math.floor(wide / (CHAR * #s)), 6, most) else most
	return l
end

local function outline(f: GuiObject, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
end

-- where a SurfaceGui on `face` of `p` lies: its x (right) and down directions, the way it faces, its width and height
-- (its last: half the part's thickness through that face)
local function faceAxes(p: BasePart, face: Enum.NormalId): (Vector3, Vector3, Vector3, number, number, number)
	local cf = p.CFrame
	if face == Enum.NormalId.Top then
		-- (a Top-face gui runs its width along the part's -z and its top along -x)
		return cf.LookVector, cf.RightVector, cf.UpVector, p.Size.Z, p.Size.X, p.Size.Y / 2
	end
	return -cf.RightVector, -cf.UpVector, cf.LookVector, p.Size.X, p.Size.Y, p.Size.Z / 2
end

-- a place on `face` of `p` from shares of its gui (x right, y down), `out` studs off it
local function faceAt(p: BasePart, face: Enum.NormalId, at: Vector2, out: number): Vector3
	local x, down, n, w, h, half = faceAxes(p, face)
	return p.Position + x * ((at.X - 0.5) * w) + down * ((at.Y - 0.5) * h) + n * (half + out)
end

-- a paper lying on the table, its text reading from the camera's side (a Top-face gui runs its width along the part's
-- -z and its top along -x: a quarter turn lays it across the table, its size given as (depth, width))
local FLAT = CFrame.Angles(0, -math.pi / 2, 0)
local function lyingPaper(parent: Instance, name: string, at: Vector3, w: number, d: number, yaw: number): Part
	return part(parent, name, V(d, 0.04, w), CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0) * FLAT, PAPER)
end

-- the game's own model `key` (Config/Assets) out of the library, coloured as the game colours it, its longest side
-- `length` studs, its middle at `cf`; a plain block where the library hasn't got it
local function colorsOf(key: string): { [string]: { number } }
	if key == "rifle_g98" then
		return WeaponsCfg.rifle_g98.parts
	elseif key == "staff" then
		return WeaponsCfg.staff_grey.parts
	elseif key == "round_qf18" then
		return Palette.Artillery
	elseif key == "ammo_rifle" then
		local w = WeaponsCfg.rifle_g98.parts
		return { Case = w.Rounds, Bullet = w.Bullets, Casing = w.Casing }
	end
	local e = AssetsCfg.Entries[key]
	local fit = e and e.fit
	local out: { [string]: { number } } = {}
	if fit then
		for name, c in fit.parts or {} do
			out[name] = c
		end
		out.Default = fit.color
	end
	return out
end

local function model(parent: Instance, key: string, length: number, cf: CFrame): Model
	local e = AssetsCfg.Entries[key]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, sub in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(sub)
	end
	local src = f and f:FindFirstChild(key)
	local m: Model
	if src and src:IsA("Model") then
		m = src:Clone()
	else
		m = Instance.new("Model")
		part(m, "Block", V(length * 0.18, length * 0.1, length), CFrame.new(), DARK)
	end
	m.Name = key
	local colors = colorsOf(key)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
			local c = colors[d.Name] or colors.Default
			if c then
				d.Color = rgb(c)
			end
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local _, size = m:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > 0 then
		m:ScaleTo(m:GetScale() * length / longest)
	end
	local bb = m:GetBoundingBox()
	m.WorldPivot = bb
	m:PivotTo(cf)
	m.Parent = parent
	return m
end

-- lays `m` on the surface at height `y` (its lowest point there)
local function settle(m: Model, y: number)
	local bb, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + V(0, y - (bb.Position.Y - size.Y / 2), 0))
end

local function pin(folder: Instance, at: Vector3)
	local p = part(folder, "Pin", V(0.14, 0.14, 0.14), CFrame.new(at), PENCIL)
	p.Shape = Enum.PartType.Ball
end

-- the Field kit (picked from the drafts, user 2026-11-03: Config/Cutscenes Table / Board) ---------------------------------
local BRASS, BRASS_DARK = Color3.fromRGB(196, 160, 84), Color3.fromRGB(150, 116, 52)
local ENAMEL, RED_PIN, NIB = Color3.fromRGB(244, 241, 232), Color3.fromRGB(176, 40, 32), Color3.fromRGB(26, 24, 22)

-- a cylinder `r` round and `long` along `axis` (a unit vector), its middle at `at`
local function rodAlong(
	parent: Instance,
	name: string,
	r: number,
	long: number,
	at: Vector3,
	axis: Vector3,
	color: Color3,
	material: Enum.Material?
): Part
	local side = if math.abs(axis.Y) < 0.9 then V(0, 1, 0) else V(1, 0, 0)
	local y = side:Cross(axis).Unit
	local p = part(parent, name, V(long, r * 2, r * 2), CFrame.fromMatrix(at, axis, y), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(parent: Instance, name: string, r: number, at: Vector3, color: Color3): Part
	local p = part(parent, name, V(r * 2, r * 2, r * 2), CFrame.new(at), color)
	p.Shape = Enum.PartType.Ball
	return p
end

-- the clipboard under the report (a hardboard with a steel clip over its top edge), `report` written on `face`
local function clipboard(folder: Instance, report: BasePart, face: Enum.NormalId)
	local K = Cfg.Table.clipboard
	local x, down, n, w, h, half = faceAxes(report, face)
	local z = x:Cross(n).Unit -- (a part's z along the gui's up or down)
	local thick = 0.016
	local mid = report.Position + down * ((K.margin - K.top) / 2) - n * (half + thick / 2 + 0.002)
	local board = part(
		folder,
		"Clipboard",
		V(w + 2 * K.margin, thick, h + K.margin + K.top),
		CFrame.fromMatrix(mid, x, n, z),
		rgb(K.color),
		Enum.Material.Wood
	)
	board.CastShadow = true
	-- the clip: its body on the board's top margin, its lip just over the paper, two rivets, the wire loop
	local edge = report.Position - down * (h / 2)
	local function slab(name: string, size: Vector3, at: Vector3)
		part(folder, name, size, CFrame.fromMatrix(at, x, n, z), STEEL, Enum.Material.Metal)
	end
	slab("Clip", V(0.8, 0.05, 0.24), edge - down * (K.top * 0.45) + n * (half + 0.03))
	slab("ClipLip", V(0.62, 0.03, 0.1), edge - down * 0.06 + n * (half + 0.02)) -- (short of the paper: its head stays clear)
	for _, sx in { -1, 1 } do
		ball(folder, "Rivet", 0.03, edge - down * (K.top * 0.45) + x * (sx * 0.3) + n * (half + 0.06), BRASS)
	end
	rodAlong(folder, "Loop", 0.025, 0.5, edge - down * (K.top * 0.8) + n * (half + 0.05), x, STEEL, Enum.Material.Metal)
end

-- VOTE stencilled on a plank nailed over the board's VOTE paper `paper` (facing the room), the hint on a paper
-- strip under it; returns where the red string's pin is (under the strip's middle)
local function voteSign(folder: Instance, paper: BasePart): Vector3
	local S = Cfg.Board.sign
	local cf = paper.CFrame
	local w, h = paper.Size.X + S.grow, paper.Size.Y + S.grow
	local plank = part(
		folder,
		"VoteSign",
		V(w, h, S.deep),
		cf * CFrame.new(0, 0, -(paper.Size.Z / 2 + S.deep / 2 + 0.002)),
		rgb(S.color),
		Enum.Material.Wood
	)
	plank.CastShadow = true
	local _, f = surface(plank, Enum.NormalId.Front, 120)
	f.BackgroundColor3 = rgb(S.color)
	-- the wood's grain and the joins between its boards
	local rng = Random.new(5)
	for k = 1, 9 do
		local g = box(f, 0, k / 10 + rng:NextNumber(-0.03, 0.03), 1, 0.012, DARK)
		g.BackgroundTransparency = if k % 3 == 0 then 0.2 else 0.75
	end
	local word = text(f, Cfg.Board.title.text, SLAB, PAPER, 0.08, 0.14, 0.84, 0.72, h * 120)
	word.TextXAlignment = Enum.TextXAlignment.Center
	word.TextTransparency = 0.08
	for _, sx in { -1, 1 } do
		ball(folder, "Nail", 0.05, (cf * CFrame.new(sx * (w / 2 - 0.16), h / 2 - 0.16, -(S.deep + 0.03))).Position, NIB)
	end
	local H = S.hint
	local strip = part(folder, "Hint", V(H.size[1], H.size[2], 0.004), cf * CFrame.new(0, -H.down, -0.006), PAPER)
	local _, hf = surface(strip, Enum.NormalId.Front, 200)
	local l = text(hf, H.text, TYPE, INK, 0.08, 0.12, 0.84, 0.76, H.size[2] * 200)
	l.TextXAlignment = Enum.TextXAlignment.Center
	for _, sx in { -1, 1 } do
		pin(folder, (strip.CFrame * CFrame.new(sx * (H.size[1] / 2 - 0.08), 0, -0.04)).Position)
	end
	return (strip.CFrame * CFrame.new(0, -H.size[2] / 2 + 0.02, -0.05)).Position
end

-- the brass stopwatch hung on the time's paper `paper` (facing the room): its label on the paper, the dial (30 seconds
-- round, the last `warn` red) with the time in a small window (returned), its hand and the dial's middle
local function stopwatch(folder: Instance, paper: BasePart): (TextLabel, BasePart, CFrame)
	local W, warn = Cfg.Board.watch, Cfg.Board.timer.warn
	local cf = paper.CFrame
	local r, deep = W.radius, W.deep
	local _, pf = surface(paper, Enum.NormalId.Front, 120)
	local label = text(pf, W.label, SLAB, INK, 0.06, 0.88, 0.88, 0.1, paper.Size.Y * 120)
	label.TextXAlignment = Enum.TextXAlignment.Center
	local mid = cf * CFrame.new(0, W.up, -(paper.Size.Z / 2 + deep / 2 + 0.004))
	local axis = cf.LookVector
	local behind = (mid * CFrame.new(0, 0, deep * 0.2)).Position
	rodAlong(folder, "WatchBack", r * 1.04, deep * 0.6, behind, axis, BRASS_DARK, Enum.Material.Metal)
	rodAlong(folder, "WatchCase", r, deep, mid.Position, axis, BRASS, Enum.Material.Metal)
	local up = cf.UpVector
	rodAlong(folder, "Crown", 0.05, 0.12, (mid * CFrame.new(0, r + 0.05, 0)).Position, up, BRASS, Enum.Material.Metal)
	rodAlong(
		folder,
		"Bow",
		0.09,
		0.025,
		(mid * CFrame.new(0, r + 0.17, 0)).Position,
		axis,
		BRASS_DARK,
		Enum.Material.Metal
	)
	ball(folder, "Nail", 0.035, (mid * CFrame.new(0, r + 0.22, deep / 2)).Position, NIB)
	-- the dial: a face part, its gui round
	local face = part(folder, "Dial", V(r * 1.8, r * 1.8, 0.002), mid * CFrame.new(0, 0, -(deep / 2 + 0.002)), ENAMEL)
	face.Transparency = 1
	local _, df = surface(face, Enum.NormalId.Front, 400)
	df.BackgroundColor3 = ENAMEL
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = df
	local dpx = r * 1.8 * 400
	for i = 0, 29 do
		-- (clockwise from the top, as the hand turns: the last seconds just past the top)
		local a = math.rad(i * 12)
		local major = i % 5 == 0
		local len = if major then 0.11 else 0.06
		local tick = box(df, 0, 0, if major then 0.014 else 0.008, len, if i < warn then rgb(GR.pencil) else INK)
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(0.5 + math.sin(a) * (0.47 - len / 2), 0.5 - math.cos(a) * (0.47 - len / 2))
		tick.Rotation = i * 12
	end
	for k, v in { 30, 5, 10, 15, 20, 25 } do
		local a = math.rad((k - 1) * 60)
		local n = text(df, tostring(v), SLAB, if v == 5 then rgb(GR.pencil) else INK, 0, 0, 0.16, 0.11, dpx)
		n.AnchorPoint = Vector2.new(0.5, 0.5)
		n.Position = UDim2.fromScale(0.5 + math.sin(a) * 0.3, 0.5 - math.cos(a) * 0.3)
		n.TextXAlignment = Enum.TextXAlignment.Center
	end
	local window = box(df, 0.25, 0.58, 0.5, 0.19, PAPER)
	outline(window, INK, 2)
	local time = text(window, "", SLAB, INK, 0, 0.05, 1, 0.9, 0.19 * dpx)
	time.TextXAlignment = Enum.TextXAlignment.Center
	-- the hand (a needle from the middle) and the cap over its pin
	local dial = mid * CFrame.new(0, 0, -(deep / 2 + 0.008))
	local hand = part(folder, "WatchHand", V(0.028, r * 0.95, 0.008), dial, NIB)
	local cap = (dial * CFrame.new(0, 0, -0.008)).Position
	rodAlong(folder, "HandCap", 0.035, 0.02, cap, axis, BRASS_DARK, Enum.Material.Metal)
	return time, hand, dial
end

-- the red string from the pin under the sign (`from`) to the leading order: a Beam between two pins, hanging
local function redString(folder: Instance, from: Vector3): (BasePart, BasePart, Beam)
	local S = Cfg.Board.string
	local function holder(axis: Vector3): (BasePart, Attachment)
		local p = ball(folder, "StringEnd", 0.05, from, RED_PIN)
		local a = Instance.new("Attachment")
		a.Axis, a.SecondaryAxis = axis, V(0, 0, 1)
		a.Parent = p
		return p, a
	end
	local p0, a0 = holder(V(0, -1, 0))
	local p1, a1 = holder(V(0, 1, 0))
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Color = ColorSequence.new(rgb(S.color))
	beam.Width0, beam.Width1 = S.width, S.width
	beam.CurveSize0, beam.CurveSize1 = S.sag, S.sag
	beam.FaceCamera = true
	beam.Segments = 16
	beam.LightInfluence = 1
	beam.Enabled = false
	beam.Parent = p0
	p1.Transparency = 1
	return p0, p1, beam
end

-- a painted wooden block for a side (its bottom middle its pivot): the body, a lighter top, a paper chevron, a dark
-- base band
local function unitBlock(parent: Instance, color: Color3): Model
	local B = Cfg.Table.blocks
	local w, d, h = B.size[1], B.size[2], B.size[3]
	local m = Instance.new("Model")
	m.Name = "Block"
	part(m, "Body", V(w, h, d), CFrame.new(0, h / 2, 0), color, Enum.Material.Wood).CastShadow = true
	local top = color:Lerp(Color3.new(1, 1, 1), 0.12)
	part(m, "Top", V(w * 0.88, 0.02, d * 0.82), CFrame.new(0, h + 0.005, 0), top, Enum.Material.Wood)
	for _, sx in { -1, 1 } do
		local at = CFrame.new(sx * 0.07, h + 0.018, -0.02) * CFrame.Angles(0, math.rad(-sx * 38), 0)
		part(m, "Chevron", V(0.2, 0.012, 0.04), at, PAPER)
	end
	part(m, "Base", V(w * 1.02, 0.04, d * 1.02), CFrame.new(0, 0.02, 0), color:Lerp(INK, 0.5), Enum.Material.Wood)
	m.WorldPivot = CFrame.new()
	m.Parent = parent
	return m
end

-- a map pin with a pennant (its foot its pivot): the steel pin, its red head, a cloth pennant flying to the right
local function pennant(parent: Instance): Model
	local P = Cfg.Table.pennants
	local m = Instance.new("Model")
	m.Name = "Pennant"
	rodAlong(m, "Pin", 0.018, P.tall, V(0, P.tall / 2, 0), V(0, 1, 0), STEEL, Enum.Material.Metal).CastShadow = true
	ball(m, "Head", 0.045, V(0, P.tall + 0.03, 0), RED_PIN)
	local long, high = P.flag[1], P.flag[2]
	-- (two wedges, their square sides on the pin, meeting at the tip: the flag's plane faces us, its tip to the right)
	for _, sy in { 1, -1 } do
		local wedge = Instance.new("WedgePart")
		wedge.Name = "Flag"
		wedge.Anchored, wedge.CanCollide, wedge.CanQuery, wedge.CanTouch = true, false, false, false
		wedge.Size = V(0.012, high / 2, long)
		wedge.Material = Enum.Material.Fabric
		local mid = V(long / 2, P.tall - high / 4 - (if sy < 0 then high / 2 else 0), 0)
		local flip = CFrame.Angles(0, 0, if sy < 0 then math.pi else 0)
		wedge.CFrame = CFrame.fromMatrix(mid, V(0, 0, 1), V(0, 1, 0)) * flip
		wedge.Parent = m
	end
	m.WorldPivot = CFrame.new()
	m.Parent = parent
	return m
end

-- the hut ---------------------------------------------------------------------------------------------------------------
local function buildHut(folder: Folder, o: Vector3)
	local P = Cfg.Post
	local sx, sy, sz = P.room.size[1], P.room.size[2], P.room.size[3]
	local cz = P.room.z
	local back, front = cz - sz / 2, cz + sz / 2
	part(folder, "Floor", V(sx + 2, 0.4, sz + 2), CFrame.new(o + V(0, -0.2, cz)), PLANK, Enum.Material.WoodPlanks)
	part(folder, "Ceiling", V(sx + 2, 0.4, sz + 2), CFrame.new(o + V(0, sy + 0.2, cz)), PLANK, Enum.Material.WoodPlanks)
	-- plank walls on posts, a sill and a head rail along each
	local walls = {
		{ V(sx, sy, 0.4), V(0, sy / 2, back - 0.2), "x" },
		{ V(sx, sy, 0.4), V(0, sy / 2, front + 0.2), "x" },
		{ V(0.4, sy, sz), V(-sx / 2 - 0.2, sy / 2, cz), "z" },
		{ V(0.4, sy, sz), V(sx / 2 + 0.2, sy / 2, cz), "z" },
	}
	for _, w in walls do
		local wall = part(
			folder,
			"Wall",
			w[1],
			CFrame.new(o + w[2]) * (if w[3] == "z" then CFrame.Angles(0, math.pi / 2, 0) else CFrame.new()),
			WOOD,
			Enum.Material.WoodPlanks
		)
		if w[3] == "z" then
			wall.Size = V(sz, sy, 0.4)
		end
		local along = if w[3] == "x" then sx else sz
		for k = 0, math.floor(along / 5) do
			local t = -along / 2 + k * along / math.floor(along / 5)
			local at = if w[3] == "x" then V(t, sy / 2, w[2].Z) else V(w[2].X, sy / 2, cz + t)
			part(folder, "Post", V(0.7, sy, 0.7), CFrame.new(o + at), DARK, Enum.Material.Wood)
		end
		for _, y in { 0.35, sy - 0.35 } do
			local size = if w[3] == "x" then V(sx, 0.4, 0.6) else V(0.6, 0.4, sz)
			part(folder, "Rail", size, CFrame.new(o + V(w[2].X, y, w[2].Z)), DARK, Enum.Material.Wood)
		end
	end
	for k = 0, 4 do
		part(
			folder,
			"Beam",
			V(sx, 0.6, 0.6),
			CFrame.new(o + V(0, sy - 0.3, back + 1.5 + k * 4.2)),
			DARK,
			Enum.Material.Wood
		)
	end
	-- the rug under the table: a red field inside a darker border and a pale stripe
	part(folder, "Rug", V(14, 0.04, 8.5), CFrame.new(o + V(0, 0.02, 0)), Color3.fromRGB(70, 30, 28))
	part(folder, "RugStripe", V(13.2, 0.045, 7.7), CFrame.new(o + V(0, 0.025, 0)), Color3.fromRGB(196, 168, 120))
	part(folder, "RugField", V(12.8, 0.05, 7.3), CFrame.new(o + V(0, 0.03, 0)), Color3.fromRGB(112, 44, 38))
	-- along the walls: a shelf of books and a crate on the left, a rifle rack and a helmet on the right, a banner
	part(folder, "Shelf", V(1.2, 0.2, 5), CFrame.new(o + V(-sx / 2 + 0.6, 3.6, back + 4)), DARK, Enum.Material.Wood)
	for k = 0, 6 do
		local c = ({ Color3.fromRGB(110, 40, 34), Color3.fromRGB(46, 66, 52), Color3.fromRGB(150, 130, 96) })[k % 3 + 1]
		part(folder, "Book", V(0.9, 1.1, 0.32), CFrame.new(o + V(-sx / 2 + 0.6, 4.25, back + 2 + k * 0.4)), c)
	end
	local function crate(size: Vector3, at: Vector3, color: Color3)
		part(folder, "Crate", size, CFrame.new(o + at), color, Enum.Material.Wood)
		local edge = color:Lerp(DARK, 0.5)
		for _, sx2 in { -1, 1 } do
			for _, sz2 in { -1, 1 } do
				part(
					folder,
					"Batten",
					V(0.16, size.Y + 0.02, 0.16),
					CFrame.new(o + at + V(sx2 * size.X / 2, 0, sz2 * size.Z / 2)),
					edge,
					Enum.Material.Wood
				)
			end
		end
		part(
			folder,
			"Lid",
			V(size.X + 0.04, 0.12, size.Z + 0.04),
			CFrame.new(o + at + V(0, size.Y / 2 - 0.2, 0)),
			edge,
			Enum.Material.Wood
		)
		part(
			folder,
			"Rope",
			V(size.X + 0.06, 0.06, 0.12),
			CFrame.new(o + at + V(0, 0, 0)),
			Color3.fromRGB(150, 128, 88)
		)
	end
	crate(V(2.4, 1.8, 2.2), V(-sx / 2 + 1.6, 0.9, back + 2), Color3.fromRGB(70, 82, 58))
	crate(V(2.2, 2.4, 2.2), V(sx / 2 - 2, 1.2, back + 2), WOOD)
	part(folder, "Rack", V(0.4, 0.3, 3.4), CFrame.new(o + V(sx / 2 - 0.4, 6.3, back + 5.5)), DARK, Enum.Material.Wood)
	for k = 0, 2 do
		local at = o + V(sx / 2 - 0.9, 3.3, back + 4.4 + k * 1.1)
		model(folder, "rifle_g98", 5.6, CFrame.new(at) * CFrame.Angles(math.rad(90), 0, math.rad(-6)))
	end
	-- the flag on the left wall: cloth on a pole with finials, the team's band and a roundel
	local fx, fz = -sx / 2 + 0.2, back + 3.4
	local cloth = part(folder, "Flag", V(0.06, 2.2, 4.4), CFrame.new(o + V(fx, 6.5, fz)), Color3.fromRGB(46, 48, 52))
	part(folder, "Band", V(0.08, 0.45, 4.4), cloth.CFrame, rgb(GR.Name.uniform1 or { 204, 172, 92 }))
	local roundel = part(folder, "Roundel", V(0.1, 1.1, 1.1), cloth.CFrame, Color3.fromRGB(204, 172, 92))
	roundel.Shape = Enum.PartType.Cylinder
	local inner = part(folder, "Roundel", V(0.12, 0.8, 0.8), cloth.CFrame, Color3.fromRGB(46, 48, 52))
	inner.Shape = Enum.PartType.Cylinder
	local pole = part(
		folder,
		"Pole",
		V(4.9, 0.12, 0.12),
		CFrame.new(o + V(fx + 0.05, 7.68, fz)) * CFrame.Angles(0, math.pi / 2, 0),
		DARK
	)
	pole.Shape = Enum.PartType.Cylinder
	for _, dz in { -2.5, 2.5 } do
		local finial = part(
			folder,
			"Finial",
			V(0.22, 0.22, 0.22),
			CFrame.new(o + V(fx + 0.05, 7.68, fz + dz)),
			Color3.fromRGB(196, 160, 84),
			Enum.Material.Metal
		)
		finial.Shape = Enum.PartType.Ball
	end
	-- the duty roster on the right wall, by the board
	local roster = part(
		folder,
		"Roster",
		V(0.04, 2.6, 1.9),
		CFrame.new(o + V(sx / 2 - 0.05, 6.4, back + 3.1)) * CFrame.Angles(0, math.pi, 0),
		PAPER
	)
	local _, rf = surface(roster, Enum.NormalId.Right, 80)
	text(rf, "DUTY ROSTER", SLAB, INK, 0.08, 0.04, 0.84, 0.06, 208)
	for k = 1, 12 do
		box(rf, 0.08, 0.13 + k * 0.065, 0.84, 0.004, DIM)
		text(rf, `Watch {k}`, TYPE, INK, 0.1, 0.09 + k * 0.065, 0.4, 0.04, 208)
	end
end

-- the war table ---------------------------------------------------------------------------------------------------------
-- the table sheet's face (`px` its height in pixels): the trench map's frame and grid, its letters and numbers, the
-- heights' contours, the legend, the scale and the sheet's title (returned, its map named at the report), and the
-- strip where the played map goes (returned)
local CONTOUR = Color3.fromRGB(150, 104, 64)
local function drawSheet(sf: Frame, px: number): (Frame, TextLabel)
	local T = Cfg.Table
	-- (under the map: the contours run on round it, as on the render's sheet)
	Ink.draw(sf, function(holder, w, h)
		local thick = math.max(1, 0.003 * h)
		for _, c in T.contours do
			local cx, cy, rings, rx, ry = c[1] * w, c[2] * h, c[3], c[4] * w, c[5] * w
			for k = rings, 1, -1 do
				local last: Vector2? = nil
				for i = 0, 36 do
					local a = i / 36 * 2 * math.pi
					local j = 1 + 0.08 * math.sin(3 * a + c[1] * 9) + 0.05 * math.sin(5 * a + c[2] * 9)
					local pt = Vector2.new(cx + math.cos(a) * rx * k / rings * j, cy + math.sin(a) * ry * k / rings * j)
					if last then
						Ink.segment(holder, last, pt, if k == rings then thick * 1.5 else thick, CONTOUR)
					end
					last = pt
				end
			end
		end
	end)
	local frame = box(sf, 0.025, 0.05, 0.95, 0.9, PAPER)
	frame.BackgroundTransparency = 1
	outline(frame, INK, 3)
	local cols, rows = T.grid.cols, T.grid.rows
	for c = 1, cols - 1 do
		box(frame, c / cols, 0, 0.0015, 1, DIM).BackgroundTransparency = 0.7
	end
	for r = 1, rows - 1 do
		box(frame, 0, r / rows, 1, 0.003, DIM).BackgroundTransparency = 0.7
	end
	for c = 1, cols do
		local l =
			text(sf, string.char(64 + c), TYPE, INK, 0.025 + (c - 0.5) / cols * 0.95 - 0.02, 0.008, 0.04, 0.035, px)
		l.TextXAlignment = Enum.TextXAlignment.Center
	end
	for r = 1, rows do
		text(sf, tostring(r), TYPE, INK, 0.008, 0.05 + (r - 0.5) / rows * 0.9 - 0.02, 0.02, 0.04, px)
	end
	local strip = box(sf, T.strip.at[1], T.strip.at[2], T.strip.width, 0.5, PAPER)
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
	strip.ZIndex = 2
	local legend = box(sf, 0.05, 0.66, 0.2, 0.24, PAPER)
	outline(legend, INK, 2)
	text(legend, "LEGEND", SLAB, INK, 0.08, 0.06, 0.8, 0.2, 0.24 * px)
	box(legend, 0.08, 0.45, 0.25, 0.035, PENCIL)
	text(legend, "CAPTURED", TYPE, INK, 0.4, 0.36, 0.55, 0.18, 0.24 * px)
	local ring = box(legend, 0.12, 0.66, 0.15, 0.2, PAPER)
	ring.BackgroundTransparency = 1
	ring.SizeConstraint = Enum.SizeConstraint.RelativeYY
	outline(ring, PENCIL, 3)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	text(legend, "THE FRONT", TYPE, INK, 0.4, 0.66, 0.55, 0.18, 0.24 * px)
	-- the scale (five bars, ink and paper by turns) and the sheet's title, clear of the report
	for k = 0, 4 do
		local bar = box(sf, 0.3125 + k * 0.0342, 0.865, 0.0342, 0.021, if k % 2 == 0 then INK else PAPER)
		outline(bar, INK, 1)
	end
	text(sf, "0    500 YDS", TYPE, INK, 0.3125, 0.815, 0.18, 0.04, px)
	local title = text(sf, "SHEET 1", TYPE, INK, 0.493, 0.855, 0.215, 0.045, px)
	return strip, title
end

local function buildTable(folder: Folder, o: Vector3): (Vector3, Frame, Frame, BasePart, TextLabel)
	local T, P = Cfg.Table, Cfg.Post
	local w, d, top = T.size[1], T.size[2], T.top
	local tableTop = o + V(0, top, 0)
	part(folder, "TableTop", V(w, 0.35, d), CFrame.new(tableTop - V(0, 0.175, 0)), WOOD, Enum.Material.Wood)
	-- the rim round the top, iron corner plates, the apron, four legs, drawers on the near side
	for _, r in
		{
			{ V(w + 0.5, 0.3, 0.3), V(0, 0.05, -d / 2 - 0.1) },
			{ V(w + 0.5, 0.3, 0.3), V(0, 0.05, d / 2 + 0.1) },
			{ V(0.3, 0.3, d), V(-w / 2 - 0.1, 0.05, 0) },
			{ V(0.3, 0.3, d), V(w / 2 + 0.1, 0.05, 0) },
		}
	do
		part(folder, "Rim", r[1], CFrame.new(tableTop + r[2]), DARK, Enum.Material.Wood)
	end
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(
				folder,
				"Plate",
				V(0.5, 0.05, 0.5),
				CFrame.new(tableTop + V(sx * (w / 2 + 0.05), 0.22, sz * (d / 2 + 0.05))),
				STEEL,
				Enum.Material.Metal
			)
			local at = V(sx * (w / 2 - 0.5), (top - 0.35) / 2, sz * (d / 2 - 0.5))
			part(folder, "Leg", V(0.6, top - 0.35, 0.6), CFrame.new(o + at), DARK, Enum.Material.Wood)
		end
	end
	part(folder, "Apron", V(w - 0.4, 0.7, d - 0.4), CFrame.new(tableTop - V(0, 0.7, 0)), DARK, Enum.Material.Wood)
	for k = -1, 1 do
		local at = tableTop + V(k * 3.6, -0.7, d / 2 - 0.15)
		part(folder, "Drawer", V(2.6, 0.5, 0.1), CFrame.new(at), WOOD, Enum.Material.Wood)
		part(folder, "Knob", V(0.25, 0.15, 0.12), CFrame.new(at + V(0, 0, 0.1)), STEEL, Enum.Material.Metal)
	end
	-- the sheet over the whole top: the trench-map paper, its grid, the played map's strip, a legend
	local sheet = lyingPaper(folder, "Sheet", tableTop + V(0, 0.02, 0), T.sheet[1], T.sheet[2], 0)
	local px = T.sheet[2] * T.pixelsPerStud -- (the sheet's height in pixels: its depth on the table)
	local _, sf = surface(sheet, Enum.NormalId.Top, T.pixelsPerStud)
	local strip, title = drawSheet(sf, px)
	-- the report on the lower right, nothing on it, on its clipboard
	local R = T.report
	local report = lyingPaper(folder, "Report", tableTop + V(R.at[1], 0.05, R.at[2]), R.size[1], R.size[2], R.tilt)
	local _, rf = surface(report, Enum.NormalId.Top, R.pixelsPerStud)
	clipboard(folder, report, Enum.NormalId.Top)
	-- the game's models round it
	for _, p in P.props do
		local yaw = CFrame.Angles(0, math.rad(p.yaw), 0)
		local m = model(
			folder,
			p.asset,
			p.length,
			CFrame.new(tableTop + V(p.at[1], 1, p.at[2]))
				* yaw
				* (if p.side then CFrame.Angles(0, 0, math.pi / 2) else CFrame.new())
		)
		settle(m, tableTop.Y + 0.04)
	end
	local C = P.casings
	local rng = Random.new(7)
	for _ = 1, C.count do
		local at = tableTop
			+ V(C.at[1] + rng:NextNumber(-1, 1) * C.spread, 1, C.at[2] + rng:NextNumber(-0.4, 0.4) * C.spread)
		local m = model(
			folder,
			"ammo_rifle",
			C.length,
			CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 2 * math.pi), math.pi / 2)
		)
		settle(m, tableTop.Y + 0.04)
	end
	-- the small things on the table, each built from its parts: a compass, a pocket watch on its chain, binoculars,
	-- an ink bottle with a dip pen, a pencil
	local BLACK = Color3.fromRGB(28, 28, 30)
	-- a disc lying flat (its axis up), `r` across the middle, `h` tall, its middle `at` over the table top's middle
	local function disc(name: string, r: number, h: number, at: Vector3, color: Color3, material: Enum.Material?): Part
		local p = part(
			folder,
			name,
			V(h, r * 2, r * 2),
			CFrame.new(tableTop + at) * CFrame.Angles(0, 0, math.pi / 2),
			color,
			material
		)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- a rod lying along the table, from `a` to `b` (over the table top's middle)
	local function rod(name: string, r: number, a: Vector3, b: Vector3, color: Color3, material: Enum.Material?): Part
		local p = part(
			folder,
			name,
			V((b - a).Magnitude, r * 2, r * 2),
			CFrame.lookAt(tableTop + (a + b) / 2, tableTop + b) * CFrame.Angles(0, math.pi / 2, 0),
			color,
			material
		)
		p.Shape = Enum.PartType.Cylinder
		return p
	end
	-- the compass: a brass case, a paper card, a red and a black needle, its pin, the lid's hinge
	local cp = V(-2.4, 0, 0.6)
	disc("CompassCase", 0.42, 0.12, cp + V(0, 0.06, 0), BRASS, Enum.Material.Metal)
	disc("CompassCard", 0.35, 0.02, cp + V(0, 0.125, 0), PAPER)
	for k = 0, 7 do
		local a = k * math.pi / 4
		part(
			folder,
			"Tick",
			V(0.02, 0.01, 0.07),
			CFrame.new(tableTop + cp + V(math.sin(a) * 0.3, 0.14, math.cos(a) * 0.3)) * CFrame.Angles(0, a, 0),
			INK
		)
	end
	part(
		folder,
		"NeedleN",
		V(0.05, 0.02, 0.28),
		CFrame.new(tableTop + cp + V(0.04, 0.15, -0.12)) * CFrame.Angles(0, math.rad(20), 0),
		PENCIL
	)
	part(
		folder,
		"NeedleS",
		V(0.05, 0.02, 0.28),
		CFrame.new(tableTop + cp + V(-0.04, 0.15, 0.12)) * CFrame.Angles(0, math.rad(20), 0),
		BLACK
	)
	local pinHead =
		part(folder, "Pin", V(0.06, 0.06, 0.06), CFrame.new(tableTop + cp + V(0, 0.17, 0)), BRASS, Enum.Material.Metal)
	pinHead.Shape = Enum.PartType.Ball
	part(
		folder,
		"Hinge",
		V(0.16, 0.08, 0.08),
		CFrame.new(tableTop + cp + V(0, 0.08, -0.44)),
		BRASS,
		Enum.Material.Metal
	)
	-- the pocket watch: a brass case, its face and hands, the crown and bow, the chain trailing off
	local wp = V(1.7, 0, 0.5)
	disc("WatchCase", 0.3, 0.1, wp + V(0, 0.05, 0), BRASS, Enum.Material.Metal)
	disc("WatchFace", 0.25, 0.02, wp + V(0, 0.105, 0), PAPER)
	for k = 0, 11 do
		local a = k * math.pi / 6
		part(
			folder,
			"Hour",
			V(0.015, 0.01, 0.04),
			CFrame.new(tableTop + wp + V(math.sin(a) * 0.21, 0.115, math.cos(a) * 0.21)) * CFrame.Angles(0, a, 0),
			INK
		)
	end
	part(
		folder,
		"HandHour",
		V(0.025, 0.01, 0.12),
		CFrame.new(tableTop + wp + V(0.03, 0.12, -0.05)) * CFrame.Angles(0, math.rad(-30), 0),
		INK
	)
	part(
		folder,
		"HandMinute",
		V(0.02, 0.01, 0.18),
		CFrame.new(tableTop + wp + V(-0.06, 0.12, -0.06)) * CFrame.Angles(0, math.rad(45), 0),
		INK
	)
	rod("Crown", 0.05, wp + V(0, 0.05, -0.3), wp + V(0, 0.05, -0.38), BRASS, Enum.Material.Metal)
	local bow = disc("Bow", 0.09, 0.03, wp + V(0, 0.03, -0.45), BRASS, Enum.Material.Metal)
	bow.Transparency = 0
	for k = 1, 10 do
		local u = k / 10
		local link = part(
			folder,
			"Link",
			V(0.05, 0.05, 0.05),
			CFrame.new(tableTop + wp + V(0.25 * math.sin(u * 3), 0.025, -0.5 - u * 0.7)),
			BRASS,
			Enum.Material.Metal
		)
		link.Shape = Enum.PartType.Ball
	end
	-- the binoculars: two barrels with brass rims and eyepieces, the bridge and its focus wheel
	local bp = V(-5.0, 0.17, -2.15)
	for _, dx in { -0.2, 0.2 } do
		rod("Barrel", 0.15, bp + V(dx, 0, -0.32), bp + V(dx, 0, 0.2), BLACK)
		rod("Rim", 0.17, bp + V(dx, 0, -0.38), bp + V(dx, 0, -0.3), BRASS, Enum.Material.Metal)
		rod("Eyepiece", 0.1, bp + V(dx, -0.04, 0.2), bp + V(dx, -0.04, 0.36), BLACK)
	end
	part(folder, "Bridge", V(0.28, 0.08, 0.3), CFrame.new(tableTop + bp + V(0, 0.08, 0)), BLACK)
	rod("Focus", 0.07, bp + V(-0.06, 0.15, 0.05), bp + V(0.06, 0.15, 0.05), BRASS, Enum.Material.Metal)
	-- the ink bottle (square glass, a neck, a cork) and the dip pen by it
	local ip = V(-1.2, 0, 1.3)
	local glass = part(
		folder,
		"Bottle",
		V(0.36, 0.3, 0.36),
		CFrame.new(tableTop + ip + V(0, 0.15, 0)),
		Color3.fromRGB(40, 60, 80),
		Enum.Material.Glass
	)
	glass.Transparency = 0.25
	part(folder, "Ink", V(0.3, 0.16, 0.3), CFrame.new(tableTop + ip + V(0, 0.09, 0)), Color3.fromRGB(18, 20, 40))
	disc("Neck", 0.09, 0.1, ip + V(0, 0.34, 0), Color3.fromRGB(40, 60, 80), Enum.Material.Glass)
	disc("Cork", 0.08, 0.08, ip + V(0, 0.43, 0), Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
	rod("PenHolder", 0.03, ip + V(0.35, 0.03, -0.3), ip + V(0.9, 0.03, 0.2), BLACK)
	rod("Nib", 0.02, ip + V(0.28, 0.03, -0.36), ip + V(0.35, 0.03, -0.3), BRASS, Enum.Material.Metal)
	-- the pencil: a yellow body, the sharpened wood and lead, a ferrule and eraser
	local a0, a1 = V(-0.9, 0.04, 0.6), V(0.3, 0.04, 1.15)
	local dir = (a1 - a0).Unit
	rod("Pencil", 0.04, a0, a1, Color3.fromRGB(214, 168, 52))
	rod("Wood", 0.03, a1, a1 + dir * 0.08, Color3.fromRGB(210, 172, 120), Enum.Material.Wood)
	rod("Lead", 0.012, a1 + dir * 0.08, a1 + dir * 0.12, BLACK)
	rod("Ferrule", 0.042, a0 - dir * 0.06, a0, Color3.fromRGB(180, 180, 176), Enum.Material.Metal)
	rod("Eraser", 0.038, a0 - dir * 0.13, a0 - dir * 0.06, Color3.fromRGB(206, 120, 120))
	return tableTop, strip, rf, sheet, title
end

-- the board -------------------------------------------------------------------------------------------------------------
-- a sepia field photograph on `on`'s front: sky over ground and, by `i`, a church tower, a field gun, a row of
-- soldiers or a biplane in silhouette
local SEPIA =
	{ sky = Color3.fromRGB(196, 176, 140), ground = Color3.fromRGB(120, 100, 74), dark = Color3.fromRGB(52, 42, 32) }
local function photo(on: BasePart, i: number)
	local _, f = surface(on, Enum.NormalId.Front, 200)
	f.BackgroundColor3 = SEPIA.sky
	box(f, 0, 0.62, 1, 0.38, SEPIA.ground)
	local kind = (i - 1) % 4
	if kind == 0 then -- the church tower: its tower, the spire, the nave beside it
		box(f, 0.42, 0.22, 0.14, 0.42, SEPIA.dark)
		local spire = box(f, 0.455, 0.1, 0.07, 0.14, SEPIA.dark)
		spire.Rotation = 0
		box(f, 0.56, 0.42, 0.3, 0.22, SEPIA.dark)
	elseif kind == 1 then -- the field gun: a wheel, the barrel cocked up, the trail
		local wheel = box(f, 0.32, 0.46, 0.22, 0.22, SEPIA.dark)
		wheel.SizeConstraint = Enum.SizeConstraint.RelativeYY
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = wheel
		local barrel = box(f, 0.38, 0.42, 0.42, 0.05, SEPIA.dark)
		barrel.Rotation = -18
		local trail = box(f, 0.12, 0.6, 0.3, 0.04, SEPIA.dark)
		trail.Rotation = 10
	elseif kind == 2 then -- a row of soldiers: heads, bodies, rifles slung
		for k = 0, 4 do
			local x = 0.1 + k * 0.17
			box(f, x, 0.36, 0.1, 0.3, SEPIA.dark)
			local head = box(f, x + 0.015, 0.27, 0.07, 0.08, SEPIA.dark)
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0.5, 0)
			c.Parent = head
			local rifle = box(f, x + 0.08, 0.22, 0.015, 0.3, SEPIA.dark)
			rifle.Rotation = 12
		end
	else -- a biplane in the sky: two wings, the body, the tail
		box(f, 0.2, 0.22, 0.6, 0.04, SEPIA.dark)
		box(f, 0.24, 0.34, 0.52, 0.04, SEPIA.dark)
		box(f, 0.44, 0.24, 0.06, 0.12, SEPIA.dark)
		box(f, 0.3, 0.27, 0.4, 0.05, SEPIA.dark)
		box(f, 0.66, 0.22, 0.04, 0.1, SEPIA.dark)
	end
end

local function buildBoard(folder: Folder, o: Vector3): (CFrame, Frame, TextLabel, { CFrame }, Vector3, BasePart, CFrame)
	local B = Cfg.Board
	local mid = o + v3(B.at)
	-- (facing the room, its own x runs to the room's +x, the viewer's left: places across it are given as the viewer
	-- sees them, negated)
	local cf = CFrame.lookAt(mid, mid - V(0, 0, 1))
	local w, h = B.size[1], B.size[2]
	part(folder, "Cork", V(w, h, 0.2), cf, CORK, Enum.Material.Cardboard)
	for _, f in
		{
			{ V(w + 0.6, 0.3, 0.35), V(0, h / 2, 0) },
			{ V(w + 0.6, 0.3, 0.35), V(0, -h / 2, 0) },
			{ V(0.3, h, 0.35), V(-w / 2, 0, 0) },
			{ V(0.3, h, 0.35), V(w / 2, 0, 0) },
		}
	do
		part(folder, "Frame", f[1], cf * CFrame.new(f[2]), DARK, Enum.Material.Wood)
	end
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			part(
				folder,
				"Plate",
				V(0.45, 0.45, 0.05),
				cf * CFrame.new(sx * w / 2, sy * h / 2, -0.2),
				STEEL,
				Enum.Material.Metal
			)
		end
	end
	-- "VOTE" on a plaque, the time left on a paper beside it
	local T = B.title
	local plaque = part(folder, "Title", V(T.size[1], T.size[2], 0.06), cf * CFrame.new(-T.x, T.y, -0.13), PAPER)
	local stringAt = voteSign(folder, plaque)
	local C = B.timer
	local clock = part(folder, "Timer", V(C.size[1], C.size[2], 0.04), cf * CFrame.new(-C.x, C.y, -0.13), PAPER)
	local timer, hand, dial = stopwatch(folder, clock)
	-- photos pinned round the orders, red string between them
	local photos = {
		{ -4.6, 2.2 },
		{ -2.3, 2.3 },
		{ 0.2, 2.25 },
		{ 2.4, 2.2 },
		{ 4.6, 2.35 },
		{ -5.0, -0.6 },
		{ 5.0, -0.7 },
		{ -4.6, -3.1 },
		{ -2.3, -3.4 },
		{ 1.6, -3.4 },
		{ 4.2, -3.3 },
	}
	local rng = Random.new(11)
	local tops: { Vector3 } = {}
	for i, ph in photos do
		local at = cf * CFrame.new(-ph[1], ph[2], -0.13) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8)))
		part(folder, "Photo" .. i, V(0.75, 0.85, 0.03), at, PAPER)
		local print = part(folder, "Print", V(0.6, 0.55, 0.035), at * CFrame.new(0, 0.07, 0), PAPER)
		photo(print, i)
		tops[i] = (at * CFrame.new(0, 0.35, -0.05)).Position
		pin(folder, tops[i])
	end
	-- (red string only round the outside: along the top, down each side, along the bottom)
	for _, pair in
		{ { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 5 }, { 1, 6 }, { 5, 7 }, { 6, 8 }, { 7, 11 }, { 8, 9 }, { 10, 11 } }
	do
		local a, b = tops[pair[1]], tops[pair[2]]
		part(folder, "String", V(0.03, 0.03, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), PENCIL)
	end
	-- the field telegram (the plan) on the left, a notice on the right
	local tg = part(
		folder,
		"Telegram",
		V(1.6, 1.2, 0.03),
		cf * CFrame.new(4.75, 0.9, -0.14) * CFrame.Angles(0, 0, math.rad(4)),
		PAPER
	)
	local _, tgf = surface(tg, Enum.NormalId.Front, 150)
	pin(folder, (tg.CFrame * CFrame.new(0, 0.55, -0.05)).Position)
	local note = part(
		folder,
		"Notice",
		V(1, 1.3, 0.03),
		cf * CFrame.new(-2.9, -3.5, -0.14) * CFrame.Angles(0, 0, math.rad(-3)),
		PAPER
	)
	local _, nf = surface(note, Enum.NormalId.Front, 150)
	box(nf, 0, 0, 1, 0.18, PENCIL)
	text(nf, "NOTICE", SLAB, PAPER, 0.08, 0.02, 0.84, 0.14, 195)
	for k, l in { "NO LIGHTS", "AFTER DARK", "KEEP YOUR", "MASK READY" } do
		text(nf, l, TYPE, INK, 0.08, 0.22 + k * 0.12, 0.84, 0.09, 195)
	end
	local S = B.sheet
	local orderAt = {}
	for i = 1, B.slots do
		local tilt = (if i % 2 == 0 then 1 else -1) * S.tilt
		orderAt[i] = cf * CFrame.new(-S.xs[i], S.y, -0.14) * CFrame.Angles(0, 0, math.rad(tilt))
	end
	return cf, tgf, timer, orderAt, stringAt, hand, dial
end

-- the modelled set ------------------------------------------------------------------------------------------------------
-- a blank paper of the set (Post.set.papers): a thin part over it, its front face the paper's, for the game's text
local function setPaper(folder: Folder, origin: Vector3, spec: any, name: string): Part
	local front = v3(spec.front).Unit
	local back = -front
	local right = v3(spec.up):Cross(back).Unit
	local up = back:Cross(right)
	-- (a paper's thickness over the set's own, so what lies on it isn't sunk through it)
	local at = origin + v3(spec.at) + front * 0.0012
	local p = part(folder, name, V(spec.size[1], spec.size[2], 0.002), CFrame.fromMatrix(at, right, up, back), PAPER)
	return p
end

-- The set from the library's command_post (nil where the library hasn't got it): its meshes coloured by name, its
-- printed papers given their images, its blank papers covered by the game's own.
-- A modelled set out of the library (Config/Assets `key`), nil where it hasn't got it: its meshes coloured by name
-- (C_RRGGBB flat, G_RRGGBB glowing; a big mesh's pieces C_RRGGBB_<n>), its printed papers given `images` (mesh name -> image id), its blank papers in
-- paper colour, stood with its Origin at `origin`, turned `turn` degrees.
function CommandPost.loadSet(folder: Instance, key: string, origin: Vector3, turn: number, images: any): Model?
	local e = AssetsCfg.Entries[key]
	local f: Instance? = ReplicatedStorage:FindFirstChild("Assets")
	f = f and f:FindFirstChild(e.category)
	for _, sub in string.split(e.folder, "/") do
		f = f and f:FindFirstChild(sub)
	end
	local src = f and f:FindFirstChild(key)
	if not src or not src:IsA("Model") then
		return nil
	end
	local m = src:Clone()
	local zero: BasePart? = nil
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
			d.CastShadow = true
			local kind, hex = string.match(d.Name, "^([CG])_(%x%x%x%x%x%x)")
			if kind and hex then
				d.Color = Color3.fromHex(hex)
				d.Material = if kind == "G" then Enum.Material.Neon else Enum.Material.SmoothPlastic
			elseif d.Name == "Origin" then
				zero = d
				d.Transparency = 1
			elseif string.sub(d.Name, 1, 6) == "Paper_" then
				d.Color = PAPER
				d.Material = Enum.Material.SmoothPlastic
			elseif images[d.Name] and d:IsA("MeshPart") then
				d.TextureID = `rbxassetid://{images[d.Name]}`
				d.Color = Color3.new(1, 1, 1)
				d.Material = Enum.Material.SmoothPlastic
			end
		end
	end
	m.WorldPivot = CFrame.new(if zero then zero.Position else m:GetPivot().Position)
	m:PivotTo(CFrame.new(origin) * CFrame.Angles(0, math.rad(turn), 0))
	m.Parent = folder
	return m
end

local function buildSet(folder: Folder, origin: Vector3): Post?
	local S = Cfg.Post.set
	local set = CommandPost.loadSet(folder, S.asset, origin, S.turn, S.images)
	if not set then
		return nil
	end
	-- (the orders' own papers stand in for the set's blank ones, which would show behind a swinging order)
	for _, d in set:GetDescendants() do
		if d:IsA("BasePart") and string.match(d.Name, "^Paper_Order") then
			d.Transparency = 1
		end
	end
	local papers = S.papers
	local T = Cfg.Table
	local sheet = setPaper(folder, origin, papers.TableSheet, "Sheet")
	local sheetPx = papers.TableSheet.size[2] * T.pixelsPerStud
	local _, sf = surface(sheet, Enum.NormalId.Front, T.pixelsPerStud)
	local strip, title = drawSheet(sf, sheetPx)
	local report = setPaper(folder, origin, papers.Report, "Report")
	local _, rf = surface(report, Enum.NormalId.Front, T.report.pixelsPerStud)
	clipboard(folder, report, Enum.NormalId.Front)
	local stringAt = voteSign(folder, setPaper(folder, origin, papers.Vote, "Vote"))
	local timer, hand, dial = stopwatch(folder, setPaper(folder, origin, papers.Timer, "Timer"))
	local tg = setPaper(folder, origin, papers.Telegram, "Telegram")
	local _, tgf = surface(tg, Enum.NormalId.Front, 180)
	local orderAt = {}
	for i = 1, Cfg.Board.slots do
		local spec = papers[`Order{i}`]
		local front = v3(spec.front).Unit
		local right = v3(spec.up):Cross(-front).Unit
		orderAt[i] = CFrame.fromMatrix(origin + v3(spec.at) + front * 0.0012, right, (-front):Cross(right), -front)
	end
	-- the lights: the lamp's warm pool on the table, the wash on the board, the cool fill
	local P = Cfg.Post
	local function light(at: Vector3, look: Vector3?): Part
		local p =
			part(folder, "Light", V(0.2, 0.2, 0.2), if look then CFrame.lookAt(at, look) else CFrame.new(at), PAPER)
		p.Transparency = 1
		return p
	end
	local lamp = light(origin + v3(P.lamp.at))
	local bulb = Instance.new("PointLight")
	bulb.Range, bulb.Brightness, bulb.Color, bulb.Shadows = P.lamp.range, P.lamp.brightness, rgb(P.lamp.color), true
	bulb.Parent = lamp
	local spot = Instance.new("SpotLight")
	spot.Face, spot.Range, spot.Brightness, spot.Angle =
		Enum.NormalId.Front, P.wash.range, P.wash.brightness, P.wash.angle
	spot.Color = rgb(P.wash.color)
	spot.Parent = light(origin + v3(P.wash.at), origin + v3(papers.Order2.at))
	local fill = Instance.new("PointLight")
	fill.Range, fill.Brightness, fill.Color = P.fill.range, P.fill.brightness, rgb(P.fill.color)
	fill.Parent = light(origin + v3(P.fill.at))
	local from, to, beam = redString(folder, stringAt)
	local kit = Instance.new("Folder")
	kit.Name = "TableKit"
	kit.Parent = folder
	return {
		origin = origin,
		tableTop = origin + V(0, papers.TableSheet.at[2], 0),
		board = orderAt[2],
		strip = strip,
		report = rf,
		telegram = tgf,
		timer = timer,
		lamp = lamp,
		folder = folder,
		orders = {},
		orderAt = orderAt,
		orderSize = Vector2.new(papers.Order1.size[1], papers.Order1.size[2]),
		sheetAspect = papers.TableSheet.size[1] / papers.TableSheet.size[2],
		reportPx = papers.Report.size[2] * T.report.pixelsPerStud,
		telegramPx = papers.Telegram.size[2] * 180,
		pins = false,
		sheetAt = function(share: Vector2): Vector3
			return faceAt(sheet, Enum.NormalId.Front, share, 0)
		end,
		tableKit = kit,
		blocks = {},
		pennants = {},
		doneAt = {},
		light = lamp,
		lightAt = lamp.CFrame,
		hand = hand,
		dial = dial,
		stringFrom = from,
		stringTo = to,
		beam = beam,
		leader = nil,
		leadAt = 0,
		leadFrom = to.Position,
		title = title,
	}
end

function CommandPost.build(folder: Folder, origin: Vector3): Post
	local made = buildSet(folder, origin)
	if made then
		return made
	end
	buildHut(folder, origin)
	local tableTop, strip, report, sheet, title = buildTable(folder, origin)
	local board, telegram, timer, orderAt, stringAt, hand, dial = buildBoard(folder, origin)
	local from, to, beam = redString(folder, stringAt)
	local kit = Instance.new("Folder")
	kit.Name = "TableKit"
	kit.Parent = folder
	local P = Cfg.Post
	local at = origin + v3(P.lamp.at)
	local lamp = part(
		folder,
		"Lamp",
		V(0.2, 1.3, 1.3),
		CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(46, 70, 52),
		Enum.Material.Metal
	)
	lamp.Shape = Enum.PartType.Cylinder
	local cap = part(
		folder,
		"Cap",
		V(0.35, 0.7, 0.7),
		CFrame.new(at + V(0, 0.25, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color3.fromRGB(46, 70, 52),
		Enum.Material.Metal
	)
	cap.Shape = Enum.PartType.Cylinder
	local glow = part(
		folder,
		"Bulb",
		V(0.35, 0.35, 0.35),
		CFrame.new(at - V(0, 0.15, 0)),
		Color3.fromRGB(255, 228, 170),
		Enum.Material.Neon
	)
	glow.Shape = Enum.PartType.Ball
	local cordLength = Cfg.Post.room.size[2] - P.lamp.at[2]
	part(folder, "Cord", V(0.06, cordLength, 0.06), CFrame.new(origin + v3(P.lamp.at) + V(0, cordLength / 2, 0)), DARK)
	local bulb = Instance.new("PointLight")
	bulb.Range, bulb.Brightness, bulb.Color, bulb.Shadows = P.lamp.range, P.lamp.brightness, rgb(P.lamp.color), true
	bulb.Parent = lamp
	local wash = part(folder, "Wash", V(0.2, 0.2, 0.2), CFrame.lookAt(origin + v3(P.wash.at), board.Position), DARK)
	wash.Transparency = 1
	local spot = Instance.new("SpotLight")
	spot.Face, spot.Range, spot.Brightness, spot.Angle =
		Enum.NormalId.Front, P.wash.range, P.wash.brightness, P.wash.angle
	spot.Color = rgb(P.wash.color)
	spot.Parent = wash
	local fillAt = part(folder, "Fill", V(0.2, 0.2, 0.2), CFrame.new(origin + v3(P.fill.at)), DARK)
	fillAt.Transparency = 1
	local fill = Instance.new("PointLight")
	fill.Range, fill.Brightness, fill.Color = P.fill.range, P.fill.brightness, rgb(P.fill.color)
	fill.Parent = fillAt
	return {
		origin = origin,
		tableTop = tableTop,
		board = board,
		strip = strip,
		report = report,
		telegram = telegram,
		timer = timer,
		lamp = lamp,
		folder = folder,
		orders = {},
		orderAt = orderAt,
		orderSize = Vector2.new(Cfg.Board.sheet.width, Cfg.Board.sheet.height),
		sheetAspect = Cfg.Table.sheet[1] / Cfg.Table.sheet[2],
		reportPx = Cfg.Table.report.size[2] * Cfg.Table.report.pixelsPerStud,
		telegramPx = 180,
		pins = true,
		sheetAt = function(share: Vector2): Vector3
			return faceAt(sheet, Enum.NormalId.Top, share, 0)
		end,
		tableKit = kit,
		blocks = {},
		pennants = {},
		doneAt = {},
		light = nil, -- (the parts lamp hangs still)
		lightAt = lamp.CFrame,
		hand = hand,
		dial = dial,
		stringFrom = from,
		stringTo = to,
		beam = beam,
		leader = nil,
		leadAt = 0,
		leadFrom = to.Position,
		title = title,
	}
end

-- the papers ------------------------------------------------------------------------------------------------------------
local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Writes the after-action report from the latest results (Net "MatchResults"): its lines, in typing order, and the
-- red pencil tick beside the result once they're typed (drawn `u` 0..1 of the way). `nation(kit)` names a winner's
-- nation.
function CommandPost.report(post: Post, r: any, nation: (string?) -> string): ({ TextLabel }, (number) -> ())
	local T = Cfg.Table
	local f = post.report
	f:ClearAllChildren()
	local px = post.reportPx
	local head = box(f, 0, 0, 1, 0.09, INK)
	text(head, "AFTER-ACTION REPORT", SLAB, PAPER, 0.06, 0.1, 0.9, 0.8, 0.09 * px)
	local winner = r.winner
	local lines: { TextLabel } = {}
	local function add(s: string, font: Font, color: Color3, y: number, h: number)
		local l = text(f, s, font, color, 0.07, y, 0.86, h, px)
		l.MaxVisibleGraphemes = 0
		table.insert(lines, l)
	end
	local mapName = if r.map then LiveMap.get(r.map).name else ""
	add(string.upper(mapName), SLAB, INK, 0.115, 0.045)
	add(if winner then string.upper(nation(winner)) else "NO VICTOR", SLAB, INK, 0.17, 0.085)
	add(if winner then "HOLDS THE LINE" else "THE LINE STANDS", TYPE, INK, 0.26, 0.045)
	add(`LENGTH {clock(math.floor(r.length or 0))}`, TYPE, INK, 0.31, 0.045)
	box(f, 0.07, 0.37, 0.86, 0.005, INK)
	add("TOP SOLDIERS", SLAB, INK, 0.385, 0.05)
	add(string.format("%-10s%5s%5s%6s", "", "KILL", "HEAL", "BUILT"), SLAB, INK, 0.44, 0.04)
	local top = if type(r.top) == "table" then r.top else {}
	for i = 1, T.top3 do
		local row = top[i]
		local s = if row
			then string.format("%d %-8s%5d%5d%6d", i, string.sub(row.name, 1, 8), row.Kills, row.Healed, row.Built)
			else `{i} -`
		add(s, TYPE, INK, 0.44 + i * 0.055, 0.045)
	end
	local you = r.you or {}
	local band = box(f, 0.05, 0.665, 0.9, 0.06, Color3.fromRGB(232, 206, 120))
	band.BackgroundTransparency = 0.35
	add(string.format("%-10s%5d%5d%6d", "YOU", you.Kills or 0, you.Healed or 0, you.Built or 0), SLAB, INK, 0.67, 0.05)
	add(`+{you.Earned or 0} battle points`, TYPE, PENCIL, 0.735, 0.045)
	-- the tick: a short stroke down, a long one up (pixels of its box)
	local tickBox = box(f, 0.84, 0.165, 0.12, 0.09, PAPER)
	tickBox.BackgroundTransparency = 1
	tickBox.ZIndex = 3
	local canvas = Ink.canvas(tickBox)
	local drawn = -1
	local function tick(u: number)
		u = math.clamp(u, 0, 1)
		if u == drawn then
			return
		end
		drawn = u
		canvas.set(function(holder, w, h)
			local a, b, c =
				Vector2.new(0.05 * w, 0.55 * h), Vector2.new(0.38 * w, 0.92 * h), Vector2.new(0.98 * w, 0.04 * h)
			local thick = math.max(2, 0.12 * h)
			local first = 0.3 -- (the share of the stroke the short one takes)
			if u > 0 then
				Ink.segment(holder, a, a:Lerp(b, math.clamp(u / first, 0, 1)), thick, PENCIL)
			end
			if u > first then
				Ink.segment(holder, b, b:Lerp(c, (u - first) / (1 - first)), thick, PENCIL)
			end
		end)
	end
	tick(0)
	-- the played map on the sheet, this match's captures redrawn on it
	local key = if type(r.map) == "string" then r.map else LiveMap.key()
	post.strip:ClearAllChildren()
	local m = SketchCfg.Maps[key]
	if m then
		-- across the sheet; a taller map no taller than `most`, narrower and in the middle
		local S = T.strip
		local w = S.width
		local h = w * post.sheetAspect * m.size[2] / m.size[1]
		if h > S.most then
			w, h = w * S.most / h, S.most
		end
		post.strip.Position = UDim2.fromScale(S.at[1] + (S.width - w) / 2, S.at[2])
		post.strip.Size = UDim2.fromScale(w, h)
	end
	post.title.Text = `SHEET 1 - {string.upper(mapName)}`
	-- the blocks and pennants are laid again for this map
	post.tableKit:ClearAllChildren()
	table.clear(post.blocks)
	table.clear(post.pennants)
	table.clear(post.doneAt)
	return lines, tick
end

-- the telegram's plan for this match's winner
function CommandPost.plan(post: Post, winner: string?)
	local B = Cfg.Board
	local f = post.telegram
	f:ClearAllChildren()
	local lines = if winner then B.planLines else B.noWinnerLines
	for k, l in lines do
		text(
			f,
			Rules.text(l, { winner = string.upper(winner or "") }),
			if k == 1 then SLAB else TYPE,
			INK,
			0.06,
			0.06 + (k - 1) * 0.17,
			0.9,
			if k == 1 then 0.14 else 0.11,
			post.telegramPx
		)
	end
end

function CommandPost.clearOrders(post: Post)
	for _, o in post.orders do
		if o.art then
			o.art.destroy()
		end
		o.gui:Destroy()
		o.part:Destroy()
	end
	table.clear(post.orders)
end

-- One OPERATION ORDER per slot (`offer`: the maps on offer, an empty slot "to be announced"); `sign(key)` when this
-- player clicks one.
function CommandPost.orders(post: Post, offer: { string }, sign: (string) -> ())
	CommandPost.clearOrders(post)
	local B = Cfg.Board
	local S = B.sheet
	local w, h = post.orderSize.X, post.orderSize.Y
	local px = h * S.pixelsPerStud
	for i = 1, B.slots do
		local key = offer[i]
		local cf = post.orderAt[i]
		local p = part(post.folder, "Order" .. i, V(w, h, if post.pins then 0.03 else 0.002), cf, PAPER)
		if post.pins then
			pin(post.folder, (cf * CFrame.new(-w / 2 + 0.12, h / 2 - 0.1, -0.04)).Position)
			pin(post.folder, (cf * CFrame.new(w / 2 - 0.12, h / 2 - 0.1, -0.04)).Position)
		end
		local g, f = surface(p, Enum.NormalId.Front, S.pixelsPerStud, key ~= nil)
		local head = box(f, 0, 0, 1, 0.07, INK)
		text(head, "OPERATION ORDER", SLAB, PAPER, 0.06, 0.15, 0.6, 0.7, 0.07 * px)
		local no = text(head, `No.{i}`, SLAB, PAPER, 0.7, 0.15, 0.24, 0.7, 0.07 * px)
		no.TextXAlignment = Enum.TextXAlignment.Right
		text(f, "OBJECTIVE", SLAB, INK, 0.06, 0.08, 0.5, 0.03, px)
		local m = key and LiveMap.get(key)
		text(f, if m then string.upper(m.name) else B.placeholder[1], SLAB, INK, 0.06, 0.115, 0.88, 0.045, px)
		local clip = box(f, 0.06, 0.175, 0.62, 0.15, PAPER)
		outline(clip, INK, 2)
		local order: Order = {
			key = key,
			part = p,
			gui = g,
			grid = nil :: any,
			count = nil :: any,
			stamp = nil :: any,
			signed = {},
			art = nil,
			n = 0,
			rollAt = -math.huge,
			countOld = nil :: any,
			rest = cf,
		}
		if key and SketchCfg.Maps[key] then
			local sm = SketchCfg.Maps[key]
			clip.Size = UDim2.fromScale(0.62, 0.62 * (w / h) * sm.size[2] / sm.size[1])
			order.art = SketchMap.new(clip, key, { still = true })
		else
			clip.Position = UDim2.fromScale(0.1, 0.19)
			clip.Size = UDim2.fromScale(0.8, 0.1)
			local l = text(clip, B.placeholder[2], SLAB, INK, 0, 0.25, 1, 0.5, 0.1 * px)
			l.TextXAlignment = Enum.TextXAlignment.Center
		end
		local orders = if key then Cfg.Vote.Orders[key] or {} else { B.placeholder[3] }
		for k, l in orders do
			text(f, if key then `{k}. {l}` else l, TYPE, INK, 0.06, 0.335 + (k - 1) * 0.035, 0.88, 0.028, px)
		end
		box(f, 0.05, 0.455, 0.9, 0.003, INK)
		text(f, "SIGNED, FOR THE FRONT:", TYPE, INK, 0.06, 0.47, 0.6, 0.03, px)
		local countBox = box(f, 0.66, 0.465, 0.28, 0.04, INK)
		countBox.ClipsDescendants = true -- (its digits roll up through it)
		local count = text(countBox, "0 / 0", SLAB, PAPER, 0, 0.1, 1, 0.8, 0.04 * px)
		count.TextXAlignment = Enum.TextXAlignment.Center
		order.count = count
		local old = text(countBox, "", SLAB, PAPER, 0, -1, 1, 0.8, 0.04 * px)
		old.TextXAlignment = Enum.TextXAlignment.Center
		order.countOld = old
		-- the signature grid: `cols` columns of `rows` lines, filled down each column
		local grid = box(f, 0.05, 0.52, 0.9, 0.45, PAPER)
		grid.BackgroundTransparency = 1
		local G = B.grid
		for r = 1, G.rows do
			box(grid, 0, r / G.rows - 0.004, 1, 0.003, DIM).BackgroundTransparency = 0.5
		end
		for c = 1, G.cols - 1 do
			box(grid, c / G.cols, 0, 0.003, 1, DIM).BackgroundTransparency = 0.7
		end
		order.grid = grid
		local stamp = text(f, "NEXT", SLAB, PENCIL, 0.15, 0.43, 0.7, 0.14, px)
		stamp.TextXAlignment = Enum.TextXAlignment.Center
		stamp.Rotation = -12
		stamp.ZIndex = 3
		outline(stamp, PENCIL, 5)
		stamp.Visible = false
		order.stamp = stamp
		if key then
			local button = Instance.new("TextButton")
			button.BackgroundTransparency = 1
			button.Text = ""
			button.Size = UDim2.fromScale(1, 1)
			button.ZIndex = 4
			button.Parent = f
			button.Activated:Connect(function()
				sign(key)
			end)
		end
		table.insert(post.orders, order)
	end
end

-- The signatures on each order from the folder's Votes_<key> ("Name:kit|..."), in signing order down the grid, new
-- ones written letter by letter in `ink(kit)`; each count out of `total` (the winners present).
function CommandPost.signatures(post: Post, folder: Instance, total: number, ink: (string?) -> Color3)
	local G = Cfg.Board.grid
	for _, o in post.orders do
		if o.key then
			local raw = folder:GetAttribute(`Votes_{o.key}`)
			local seen: { [string]: boolean } = {}
			local n = 0
			for _, entry in (if type(raw) == "string" and raw ~= "" then string.split(raw, "|") else {}) do
				local name, kit = string.match(entry, "^(.-):(.*)$")
				if name and n < G.cols * G.rows then
					n += 1
					seen[name] = true
					local label = o.signed[name]
					if not label then
						local made = Instance.new("TextLabel")
						made.BackgroundTransparency = 1
						made.FontFace = HAND
						made.TextScaled = true
						made.TextColor3 = ink(kit)
						made.TextXAlignment = Enum.TextXAlignment.Left
						made.Text = name
						made.MaxVisibleGraphemes = 0
						made.Size = UDim2.fromScale(1 / G.cols - 0.02, 1 / G.rows - 0.01)
						made.Parent = o.grid
						o.signed[name] = made
						local start = os.clock()
						task.spawn(function()
							while made.Parent and made.MaxVisibleGraphemes < #name do
								local k = math.clamp((os.clock() - start) / Cfg.Board.write, 0, 1)
								made.MaxVisibleGraphemes = math.ceil(k * #name)
								task.wait()
							end
						end)
						label = made
					end
					local col, row = (n - 1) // G.rows, (n - 1) % G.rows
					label.Position = UDim2.fromScale(col / G.cols + 0.01, row / G.rows)
				end
			end
			for name, l in o.signed do
				if not seen[name] then -- (signed another order instead)
					l:Destroy()
					o.signed[name] = nil
				end
			end
			local shown = `{n} / {math.max(total, n)}`
			if n > o.n then -- (a new signature: the count rolls up)
				o.countOld.Text = o.count.Text
				o.rollAt = os.clock()
			end
			o.n = n
			o.count.Text = shown
		else
			o.count.Text = `0 / {total}`
		end
	end
end

-- the Field kit's moves ------------------------------------------------------------------------------------------------
local function sideColour(kit: string?): Color3
	local c = kit and GR.Wash[kit]
	return if c then rgb(c):Lerp(INK, 0.2) else PAPER
end

-- The war table each frame (`t` seconds into the phase): the painted blocks and the pin pennants follow the replay on
-- `sheet` (the played map's SketchMap), the lamp's light sways. `folder` names each side's kit (its West / East).
function CommandPost.stepTable(post: Post, sheet: any, folder: Instance, t: number)
	local T = Cfg.Table
	local P = Cfg.Post
	if post.light then
		local W = P.sway
		post.light.CFrame = post.lightAt + V(W.x * math.sin(t * W.rates[1]), 0, W.z * math.cos(t * W.rates[2]))
	end
	if not sheet or not sheet.state then
		return
	end
	local places, caps = sheet.state()
	if #places == 0 then
		return
	end
	local kits = { West = folder:GetAttribute("West") :: string?, East = folder:GetAttribute("East") :: string? }
	-- the image's shares onto the sheet (the strip's place on it)
	local sp, ss = post.strip.Position, post.strip.Size
	local function onSheet(at: Vector2): Vector3
		return post.sheetAt(Vector2.new(sp.X.Scale + at.X * ss.X.Scale, sp.Y.Scale + at.Y * ss.Y.Scale))
	end
	if #post.pennants ~= #places then
		post.tableKit:ClearAllChildren()
		table.clear(post.pennants)
		table.clear(post.blocks)
		for i = 1, #places do
			post.pennants[i] = pennant(post.tableKit)
		end
		for _, side in { "West", "East" } do
			post.blocks[side] = unitBlock(post.tableKit, sideColour(kits[side]))
		end
	end
	-- where each side's block rests: by its front point, on the side it faces the enemy from
	local B, PN = T.blocks, T.pennants
	local function rest(i: number, side: string): Vector3
		local s = if side == "West" then 1 else -1
		return onSheet(places[i].at) + V(s * B.rest[1], 0, B.rest[2])
	end
	local owners: { string } = {}
	for i, p in places do
		owners[i] = p.start
	end
	local function front(side: string): Vector3
		local i = Rules.frontPoint(owners, side :: any)
		if i then
			return rest(i, side)
		end
		-- (a side holding nothing: its block off the map's edge beyond its last HQ)
		local edge = if side == "West" then 1 else #places
		return onSheet(places[edge].at) + V(if side == "West" then -B.off else B.off, 0, B.rest[2])
	end
	local pos = { West = front("West"), East = front("East") }
	local lift = { West = 0, East = 0 }
	local flips: { [number]: { k: number, before: string } } = {}
	local now = os.clock()
	for k, c in caps or {} do
		if c.q <= 0 then
			break
		end
		local taker, other = c.side, if c.side == "West" then "East" else "West"
		if c.q < 1 then
			-- the taker's block slides with the pencil, bowed as the arrow is, lifting at the middle
			local e = Rules.ease(c.q)
			local bend = onSheet((c.a:Lerp(c.mid, e)):Lerp(c.mid:Lerp(c.b, e), e)) - onSheet(c.a:Lerp(c.b, e))
			pos[taker] = pos[taker]:Lerp(rest(c.index, taker), e) + V(bend.X, 0, bend.Z)
			lift[taker] = B.lift * math.sin(math.pi * c.q)
			break
		end
		flips[c.index] = { k = k, before = owners[c.index] }
		owners[c.index] = taker
		post.doneAt[k] = post.doneAt[k] or now
		pos[taker] = rest(c.index, taker)
		-- the side pushed off its point slides back to its new front
		local u = Rules.ease(math.clamp((now - post.doneAt[k]) / B.back, 0, 1))
		pos[other] = pos[other]:Lerp(front(other), u)
	end
	for side, m in post.blocks do
		local at = pos[side]
		local face = if side == "West" then 0 else math.pi
		m:PivotTo(CFrame.new(at + V(0, lift[side], 0)) * CFrame.Angles(0, face, 0))
	end
	-- the pennants: each its point's holder's colour; at a capture it lifts, changes at the top, and drops back
	for i, m in post.pennants do
		local holder, up = owners[i], 0
		local f = flips[i]
		if f then
			local u = math.clamp((now - post.doneAt[f.k]) / PN.flip, 0, 1)
			up = PN.lift * math.sin(math.pi * u)
			if u < 0.5 then
				holder = f.before
			end
		end
		local colour = sideColour(kits[holder])
		for _, d in m:GetChildren() do
			if d.Name == "Flag" and d:IsA("BasePart") then
				d.Color = colour
			end
		end
		m:PivotTo(CFrame.new(onSheet(places[i].at) + V(PN.at[1], up, PN.at[2])))
	end
end

-- The board each frame: the stopwatch's hand round the time `left` of `total`, the red string to the leading order,
-- the counts rolling up; after the pick (`picked` its key, `since` seconds ago) the losing orders swing on one pin.
function CommandPost.stepBoard(post: Post, left: number, total: number, picked: string?, since: number)
	local B = Cfg.Board
	local angle = Rules.watchAngle(left, total)
	post.hand.CFrame = post.dial * CFrame.Angles(0, 0, math.rad(angle)) * CFrame.new(0, post.hand.Size.Y * 0.32, 0)
	local now = os.clock()
	-- the counts' digits, rolling up through their boxes
	for _, o in post.orders do
		local u = Rules.ease(math.clamp((now - o.rollAt) / B.roll, 0, 1))
		o.count.Position = UDim2.fromScale(0, 0.1 + (1 - u))
		o.countOld.Position = UDim2.fromScale(0, 0.1 - u)
		o.countOld.Visible = u < 1
	end
	-- the string: off to a clear new leader from where its end was
	local counts = {}
	for i, o in post.orders do
		counts[i] = if o.key then o.n else 0
	end
	local lead = Rules.leader(counts, post.leader)
	local function pinOf(i: number): Vector3
		local o = post.orders[i]
		return (o.part.CFrame * CFrame.new(0, o.part.Size.Y / 2 - 0.1, -0.05)).Position
	end
	if lead ~= post.leader then
		post.leadFrom = if post.leader then post.stringTo.Position else post.stringFrom.Position
		post.leader, post.leadAt = lead, now
	end
	post.beam.Enabled = lead ~= nil
	post.stringTo.Transparency = if lead then 0 else 1
	if lead and post.orders[lead] then
		local u = Rules.overshoot(math.clamp((now - post.leadAt) / B.string.slide, 0, 1))
		post.stringTo.Position = post.leadFrom:Lerp(pinOf(lead), u)
	end
	-- the losing orders swing once on their outer top pin and come to rest
	for i, o in post.orders do
		local swing = if picked and o.key ~= picked then Rules.swing(B.lose, since - B.lose.after) else 0
		local outer = if i < #post.orders / 2 + 0.5 then 1 else -1 -- (the viewer's left order hangs on its left pin)
		local w, h = o.part.Size.X, o.part.Size.Y
		local hinge = o.rest * CFrame.new(outer * (w / 2 - 0.12), h / 2 - 0.1, 0)
		o.part.CFrame = hinge * CFrame.Angles(0, 0, math.rad(swing * outer)) * hinge:Inverse() * o.rest
	end
end

-- A new vote: no string until someone leads.
function CommandPost.resetBoard(post: Post)
	post.leader = nil
	post.beam.Enabled = false
	post.stringTo.Transparency = 1
	post.stringTo.Position = post.stringFrom.Position
end

return CommandPost
