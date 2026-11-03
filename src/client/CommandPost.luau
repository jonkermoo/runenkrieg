--!strict
-- The command post (the approved render, user 2026-11-03; Config/Cutscenes Post / Table / Board): the set the end
-- of a Normal match plays in (src/client/EndScenes runs the scenes and the cameras). A flat-roofed timber hut; the war
-- table in the middle with one sheet over its top (the played map's sketch with this match's captures, the grid, a
-- legend), the game's own models on it and the after-action report on its lower right; the orders board on the back
-- wall: "ORDERS · THE NEXT FRONT", one OPERATION ORDER per map on offer with its signature grid, photos on red string,
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
}
export type Post = {
	origin: Vector3,
	tableTop: Vector3,
	board: CFrame, -- the board's middle, facing the room
	strip: Frame, -- the played map's place on the table sheet
	report: Frame,
	telegram: Frame,
	lamp: BasePart,
	folder: Folder,
	orders: { Order },
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
	g.LightInfluence = 0.75
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
	l.TextSize = math.max(6, math.floor(h * px * 0.9))
	l.TextWrapped = false
	l.Text = s
	l.Position = UDim2.fromScale(x, y)
	l.Size = UDim2.fromScale(w, h)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Center
	l.Parent = parent
	return l
end

local function outline(f: GuiObject, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
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
	part(
		folder,
		"Rug",
		V(14, 0.05, 8.5),
		CFrame.new(o + V(0, 0.03, 0)),
		Color3.fromRGB(104, 42, 36),
		Enum.Material.Fabric
	)
	-- along the walls: a shelf of books and a crate on the left, a rifle rack and a helmet on the right, a banner
	part(folder, "Shelf", V(1.2, 0.2, 5), CFrame.new(o + V(-sx / 2 + 0.6, 3.6, back + 4)), DARK, Enum.Material.Wood)
	for k = 0, 6 do
		local c = ({ Color3.fromRGB(110, 40, 34), Color3.fromRGB(46, 66, 52), Color3.fromRGB(150, 130, 96) })[k % 3 + 1]
		part(folder, "Book", V(0.9, 1.1, 0.32), CFrame.new(o + V(-sx / 2 + 0.6, 4.25, back + 2 + k * 0.4)), c)
	end
	part(
		folder,
		"Crate",
		V(2.4, 1.8, 2.2),
		CFrame.new(o + V(-sx / 2 + 1.6, 0.9, back + 2)),
		Color3.fromRGB(70, 82, 58),
		Enum.Material.Wood
	)
	part(
		folder,
		"Crate",
		V(2.2, 2.4, 2.2),
		CFrame.new(o + V(sx / 2 - 2, 1.2, back + 2)),
		WOOD,
		Enum.Material.WoodPlanks
	)
	part(folder, "Rack", V(0.4, 0.3, 3.4), CFrame.new(o + V(sx / 2 - 0.4, 6.3, back + 5.5)), DARK, Enum.Material.Wood)
	for k = 0, 2 do
		local at = o + V(sx / 2 - 0.9, 3.3, back + 4.4 + k * 1.1)
		model(folder, "rifle_g98", 5.6, CFrame.new(at) * CFrame.Angles(math.rad(90), 0, math.rad(-6)))
	end
	local banner = part(
		folder,
		"Banner",
		V(0.1, 2.2, 4.6),
		CFrame.new(o + V(-sx / 2 + 0.15, 6.6, back + 3.4)),
		Color3.fromRGB(38, 40, 44),
		Enum.Material.Fabric
	)
	part(
		folder,
		"Stripe",
		V(0.12, 0.5, 4.6),
		banner.CFrame,
		rgb(GR.Name.uniform1 or { 204, 172, 92 }),
		Enum.Material.Fabric
	)
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
		text(rf, `Watch {k}`, TYPE, DIM, 0.1, 0.09 + k * 0.065, 0.4, 0.035, 208)
	end
end

-- the war table ---------------------------------------------------------------------------------------------------------
local function buildTable(folder: Folder, o: Vector3): (Vector3, Frame, Frame)
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
	-- fields under the paper's lower half, the colour of washed pencil
	for _, b in { { 0.3, 0.68, 0.18, 0.12 }, { 0.52, 0.74, 0.2, 0.14 }, { 0.14, 0.8, 0.1, 0.1 } } do
		local f = box(sf, b[1], b[2], b[3], b[4], Color3.fromRGB(196, 204, 150))
		f.BackgroundTransparency = 0.45
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	local strip = box(sf, T.strip.at[1], T.strip.at[2], T.strip.width, 0.5, PAPER)
	strip.Name = "Strip"
	strip.BackgroundTransparency = 1
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
	-- the report on the lower right, nothing on it
	local R = T.report
	local report = lyingPaper(folder, "Report", tableTop + V(R.at[1], 0.05, R.at[2]), R.size[1], R.size[2], R.tilt)
	local _, rf = surface(report, Enum.NormalId.Top, R.pixelsPerStud)
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
	-- a compass, a pocket watch, binoculars, an ink pot and a pencil
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
	disc("Compass", 0.45, 0.12, V(-4.0, 0.1, -0.2), Color3.fromRGB(200, 170, 96), Enum.Material.Metal)
	disc("Glass", 0.38, 0.13, V(-4.0, 0.11, -0.2), Color3.fromRGB(226, 232, 230), Enum.Material.Glass)
	disc("Watch", 0.32, 0.12, V(-3.6, 0.1, 1.0), Color3.fromRGB(200, 170, 96), Enum.Material.Metal)
	disc("Ink", 0.25, 0.4, V(-1.1, 0.24, 1.2), Color3.fromRGB(24, 26, 34), Enum.Material.Glass)
	for _, dx in { -0.35, 0.35 } do
		local b = part(
			folder,
			"Binocular",
			V(1.1, 0.5, 0.5),
			CFrame.new(tableTop + V(-5.0 + dx, 0.27, -2.2)) * CFrame.Angles(0, math.pi / 2, 0),
			Color3.fromRGB(30, 30, 30)
		)
		b.Shape = Enum.PartType.Cylinder
	end
	part(
		folder,
		"Pencil",
		V(0.08, 0.08, 1.3),
		CFrame.new(tableTop + V(-0.6, 0.06, 1.0)) * CFrame.Angles(0, math.rad(25), 0),
		Color3.fromRGB(30, 30, 30)
	)
	part(
		folder,
		"Block",
		V(0.7, 0.18, 0.5),
		CFrame.new(tableTop + V(1.3, 0.1, -2.35)) * CFrame.Angles(0, math.rad(12), 0),
		PENCIL
	)
	return tableTop, strip, rf
end

-- the board -------------------------------------------------------------------------------------------------------------
local function pin(folder: Instance, at: Vector3)
	local p = part(folder, "Pin", V(0.14, 0.14, 0.14), CFrame.new(at), PENCIL)
	p.Shape = Enum.PartType.Ball
end

local function buildBoard(folder: Folder, o: Vector3): (CFrame, Frame)
	local B = Cfg.Board
	local mid = o + v3(B.at)
	local cf = CFrame.lookAt(mid, mid + V(0, 0, 1))
	local w, h = B.size[1], B.size[2]
	part(folder, "Cork", V(w, h, 0.2), cf, CORK, Enum.Material.Fabric)
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
	-- "ORDERS · THE NEXT FRONT" on a plaque
	local plaque =
		part(folder, "Title", V(B.title.size[1], B.title.size[2], 0.06), cf * CFrame.new(0, B.title.y, -0.13), PAPER)
	local _, tf = surface(plaque, Enum.NormalId.Front, 120)
	local inner = box(tf, 0.02, 0.1, 0.96, 0.8, PAPER)
	outline(inner, INK, 3)
	local title = text(tf, "ORDERS  ·  THE NEXT FRONT", SLAB, INK, 0, 0.15, 1, 0.7, B.title.size[2] * 120)
	title.TextXAlignment = Enum.TextXAlignment.Center
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
		local at = cf * CFrame.new(ph[1], ph[2], -0.13) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8)))
		part(folder, "Photo" .. i, V(0.75, 0.85, 0.03), at, Color3.fromRGB(236, 230, 214))
		local shade = 70 + rng:NextInteger(0, 30)
		part(
			folder,
			"Print",
			V(0.6, 0.55, 0.035),
			at * CFrame.new(0, 0.07, 0),
			Color3.fromRGB(shade, shade - 4, shade - 12)
		)
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
		cf * CFrame.new(-4.75, 0.9, -0.14) * CFrame.Angles(0, 0, math.rad(4)),
		Color3.fromRGB(226, 200, 150)
	)
	local _, tgf = surface(tg, Enum.NormalId.Front, 150)
	tgf.BackgroundColor3 = Color3.fromRGB(226, 200, 150)
	pin(folder, (tg.CFrame * CFrame.new(0, 0.55, -0.05)).Position)
	local note = part(
		folder,
		"Notice",
		V(1, 1.3, 0.03),
		cf * CFrame.new(4.9, -2.1, -0.14) * CFrame.Angles(0, 0, math.rad(-3)),
		PAPER
	)
	local _, nf = surface(note, Enum.NormalId.Front, 150)
	box(nf, 0, 0, 1, 0.18, PENCIL)
	text(nf, "NOTICE", SLAB, PAPER, 0.08, 0.02, 0.84, 0.14, 195)
	for k, l in { "NO LIGHTS", "AFTER DARK", "KEEP YOUR", "MASK READY" } do
		text(nf, l, TYPE, INK, 0.08, 0.22 + k * 0.12, 0.84, 0.09, 195)
	end
	return cf, tgf
end

function CommandPost.build(folder: Folder, origin: Vector3): Post
	buildHut(folder, origin)
	local tableTop, strip, report = buildTable(folder, origin)
	local board, telegram = buildBoard(folder, origin)
	local P = Cfg.Post
	local lamp = part(
		folder,
		"Lamp",
		V(1.1, 0.55, 1.1),
		CFrame.new(origin + v3(P.lamp.at)),
		Color3.fromRGB(46, 58, 44),
		Enum.Material.Metal
	)
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
		lamp = lamp,
		folder = folder,
		orders = {},
	}
end

-- the papers ------------------------------------------------------------------------------------------------------------
local function clock(seconds: number): string
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- Writes the after-action report from the latest results (Net "MatchResults"): its lines, in typing order, and the
-- stamp to show once they're typed. `nation(kit)` names a winner's nation.
function CommandPost.report(post: Post, r: any, nation: (string?) -> string): ({ TextLabel }, TextLabel)
	local T = Cfg.Table
	local f = post.report
	f:ClearAllChildren()
	local px = T.report.size[2] * T.report.pixelsPerStud
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
	add(`SECTOR    {string.upper(mapName)}`, TYPE, DIM, 0.12, 0.035)
	add(if winner then string.upper(nation(winner)) else "NO VICTOR", SLAB, INK, 0.17, 0.075)
	add(if winner then "HOLDS THE LINE" else "THE LINE STANDS", TYPE, INK, 0.255, 0.04)
	add(`LENGTH    {clock(math.floor(r.length or 0))}`, TYPE, DIM, 0.3, 0.035)
	box(f, 0.07, 0.36, 0.86, 0.004, INK)
	add("TOP SOLDIERS", SLAB, INK, 0.385, 0.045)
	add(string.format("%-12s%6s%5s%6s", "", "KILLS", "HEAL", "BUILT"), TYPE, DIM, 0.44, 0.03)
	local top = if type(r.top) == "table" then r.top else {}
	for i = 1, T.top3 do
		local row = top[i]
		local s = if row
			then string.format("%d %-10s%6d%5d%6d", i, string.sub(row.name, 1, 10), row.Kills, row.Healed, row.Built)
			else `{i} -`
		add(s, TYPE, INK, 0.44 + i * 0.05, 0.035)
	end
	local you = r.you or {}
	local band = box(f, 0.05, 0.66, 0.9, 0.05, Color3.fromRGB(232, 206, 120))
	band.BackgroundTransparency = 0.35
	add(string.format("%-12s%6d%5d%6d", "YOU", you.Kills or 0, you.Healed or 0, you.Built or 0), TYPE, INK, 0.665, 0.04)
	add(`+{you.Earned or 0} battle points`, TYPE, PENCIL, 0.72, 0.035)
	local stamp = text(f, if winner then "VICTORY" else "STALEMATE", SLAB, PENCIL, 0.35, 0.82, 0.58, 0.1, px)
	stamp.TextXAlignment = Enum.TextXAlignment.Center
	stamp.Rotation = -12
	outline(stamp, PENCIL, 3)
	stamp.Visible = false
	-- the played map on the sheet, this match's captures redrawn on it
	local key = if type(r.map) == "string" then r.map else LiveMap.key()
	post.strip:ClearAllChildren()
	local m = SketchCfg.Maps[key]
	if m then
		local w = post.strip.Size.X.Scale
		local sheetAspect = T.sheet[1] / T.sheet[2]
		post.strip.Size = UDim2.fromScale(w, w * sheetAspect * m.size[2] / m.size[1])
	end
	return lines, stamp
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
			180
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
	local px = S.height * S.pixelsPerStud
	for i = 1, B.slots do
		local key = offer[i]
		local tilt = (if i % 2 == 0 then 1 else -1) * S.tilt
		local cf = post.board * CFrame.new(S.xs[i], S.y, -0.14) * CFrame.Angles(0, 0, math.rad(tilt))
		local p = part(post.folder, "Order" .. i, V(S.width, S.height, 0.03), cf, PAPER)
		pin(post.folder, (cf * CFrame.new(-S.width / 2 + 0.12, S.height / 2 - 0.1, -0.04)).Position)
		pin(post.folder, (cf * CFrame.new(S.width / 2 - 0.12, S.height / 2 - 0.1, -0.04)).Position)
		local g, f = surface(p, Enum.NormalId.Front, S.pixelsPerStud, key ~= nil)
		local head = box(f, 0, 0, 1, 0.07, INK)
		text(head, "OPERATION ORDER", SLAB, PAPER, 0.06, 0.15, 0.6, 0.7, 0.07 * px)
		local no = text(head, `No.{i}`, SLAB, PAPER, 0.7, 0.15, 0.24, 0.7, 0.07 * px)
		no.TextXAlignment = Enum.TextXAlignment.Right
		text(f, "OBJECTIVE", TYPE, DIM, 0.06, 0.085, 0.5, 0.025, px)
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
		}
		if key and SketchCfg.Maps[key] then
			local sm = SketchCfg.Maps[key]
			clip.Size = UDim2.fromScale(0.62, 0.62 * (S.width / S.height) * sm.size[2] / sm.size[1])
			order.art = SketchMap.new(clip, key, { still = true })
		else
			clip.Position = UDim2.fromScale(0.1, 0.19)
			clip.Size = UDim2.fromScale(0.8, 0.1)
			local l = text(clip, B.placeholder[2], TYPE, DIM, 0, 0.25, 1, 0.5, 0.1 * px)
			l.TextXAlignment = Enum.TextXAlignment.Center
		end
		local orders = if key then Cfg.Vote.Orders[key] or {} else { B.placeholder[3] }
		for k, l in orders do
			text(
				f,
				if key then `{k}. {l}` else l,
				TYPE,
				if key then INK else DIM,
				0.06,
				0.335 + (k - 1) * 0.035,
				0.88,
				0.028,
				px
			)
		end
		box(f, 0.05, 0.455, 0.9, 0.003, INK)
		text(f, "SIGNED, FOR THE FRONT:", TYPE, INK, 0.06, 0.47, 0.6, 0.03, px)
		local countBox = box(f, 0.66, 0.465, 0.28, 0.04, INK)
		local count = text(countBox, "0 / 0", SLAB, PAPER, 0, 0.1, 1, 0.8, 0.04 * px)
		count.TextXAlignment = Enum.TextXAlignment.Center
		order.count = count
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
		local stamp = text(f, "NEXT", SLAB, PENCIL, 0.15, 0.6, 0.7, 0.14, px)
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
			o.count.Text = `{n} / {math.max(total, n)}`
		end
	end
end

return CommandPost
