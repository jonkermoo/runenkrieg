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
-- legend, and the strip where the played map goes (returned)
local function drawSheet(sf: Frame, px: number): Frame
	local T = Cfg.Table
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
	return strip
end

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
	local strip = drawSheet(sf, px)
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
	-- the small things on the table, each built from its parts: a compass, a pocket watch on its chain, binoculars,
	-- an ink bottle with a dip pen, a pencil
	local BRASS, BLACK = Color3.fromRGB(196, 160, 84), Color3.fromRGB(28, 28, 30)
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
	return tableTop, strip, rf
end

-- the board -------------------------------------------------------------------------------------------------------------
local function pin(folder: Instance, at: Vector3)
	local p = part(folder, "Pin", V(0.14, 0.14, 0.14), CFrame.new(at), PENCIL)
	p.Shape = Enum.PartType.Ball
end

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

-- the board's "VOTE" card (`px` its height in pixels)
local function drawVote(tf: Frame, px: number)
	local inner = box(tf, 0.04, 0.1, 0.92, 0.8, PAPER)
	outline(inner, INK, 3)
	local title = text(tf, Cfg.Board.title.text, SLAB, INK, 0.08, 0.15, 0.84, 0.7, px)
	title.TextXAlignment = Enum.TextXAlignment.Center
end

-- the vote's countdown paper: its label, and the time left (returned)
local function drawTimer(cf2: Frame, px: number): TextLabel
	local label = text(cf2, Cfg.Board.timer.label, SLAB, INK, 0.08, 0.08, 0.84, 0.24, px)
	label.TextXAlignment = Enum.TextXAlignment.Center
	local timer = text(cf2, "", SLAB, PENCIL, 0.08, 0.36, 0.84, 0.54, px)
	timer.TextXAlignment = Enum.TextXAlignment.Center
	return timer
end

local function buildBoard(folder: Folder, o: Vector3): (CFrame, Frame, TextLabel, { CFrame })
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
	local _, tf = surface(plaque, Enum.NormalId.Front, 120)
	drawVote(tf, T.size[2] * 120)
	local C = B.timer
	local clock = part(folder, "Timer", V(C.size[1], C.size[2], 0.04), cf * CFrame.new(-C.x, C.y, -0.13), PAPER)
	pin(folder, (clock.CFrame * CFrame.new(0, C.size[2] / 2 - 0.08, -0.04)).Position)
	local _, cf2 = surface(clock, Enum.NormalId.Front, 120)
	local timer = drawTimer(cf2, C.size[2] * 120)
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
	return cf, tgf, timer, orderAt
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
	if not CommandPost.loadSet(folder, S.asset, origin, S.turn, S.images) then
		return nil
	end
	local papers = S.papers
	local T = Cfg.Table
	local sheet = setPaper(folder, origin, papers.TableSheet, "Sheet")
	local sheetPx = papers.TableSheet.size[2] * T.pixelsPerStud
	local _, sf = surface(sheet, Enum.NormalId.Front, T.pixelsPerStud)
	local strip = drawSheet(sf, sheetPx)
	local report = setPaper(folder, origin, papers.Report, "Report")
	local _, rf = surface(report, Enum.NormalId.Front, T.report.pixelsPerStud)
	local vote = setPaper(folder, origin, papers.Vote, "Vote")
	local _, vf = surface(vote, Enum.NormalId.Front, 120)
	drawVote(vf, papers.Vote.size[2] * 120)
	local clock = setPaper(folder, origin, papers.Timer, "Timer")
	local _, cf2 = surface(clock, Enum.NormalId.Front, 120)
	local timer = drawTimer(cf2, papers.Timer.size[2] * 120)
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
	}
end

function CommandPost.build(folder: Folder, origin: Vector3): Post
	local made = buildSet(folder, origin)
	if made then
		return made
	end
	buildHut(folder, origin)
	local tableTop, strip, report = buildTable(folder, origin)
	local board, telegram, timer, orderAt = buildBoard(folder, origin)
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
		local sheetAspect = post.sheetAspect
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
			o.count.Text = `{n} / {math.max(total, n)}`
		else
			o.count.Text = `0 / {total}`
		end
	end
end

return CommandPost
