--!strict
-- The gunner's map sheet and elevation quadrant (Config/Artillery.Sheet; user 2026-11-03, the aiming plan: "Option C,
-- but move the camera angle too so you can see yourself as well as where you're hitting"), bottom left while I'm on a
-- gun with `sheet` (the field gun), in place of its cut-away panel (src/client/ArtilleryHud):
-- - the sheet: the live map's sketch round the gun (src/client/SketchMap: its sectors, front and points; plain paper on
--   a map without one), the reach cap's circle dashed, the line the gun is laid along, the gun, and a cross where the
--   shell comes down with the shell's wounding reach round it, moving as it is laid;
-- - the quadrant: the gun's elevation stops ticked, the lobs past `split` in amber, the needle at the lay, and under it
--   the elevation, the range and the reload (Config/Hud.Artillery.timer, "Ready" once loaded).
--   ArtillerySheet.start(); ArtillerySheet.landing(at?, flight?): where my gun's shell comes down now (src/client/
--   Artillery), nil while it lands nowhere

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Cfg = require(Shared.Config.Artillery)
local Damage = require(Shared.Config.Damage)
local HudCfg = require(Shared.Config.Hud)
local Palette = require(Shared.Config.Palette)
local SketchCfg = require(Shared.Config.SketchMap) :: any
local LiveMap = require(Shared.LiveMap)
local Rules = require(Shared.Rules.Artillery)
local Ink = require(script.Parent.Ink)
local SketchMap = require(script.Parent.SketchMap)

local ArtillerySheet = {}

local S = Cfg.Sheet
local GR = Palette.UI.Grimoire

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local landAt: Vector3? = nil
local flightOf: number? = nil

function ArtillerySheet.landing(at: Vector3?, flight: number?)
	landAt, flightOf = at, flight
end

-- a stroke frame moved to run from a to b (pixels in its parent)
local function stroke(f: Frame, a: Vector2, b: Vector2, thick: number)
	local d = b - a
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude, thick)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
end

local function frame(parent: Instance, name: string, colour: Color3?, z: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = colour or Color3.new()
	f.BackgroundTransparency = if colour then 0 else 1
	f.ZIndex = z or 1
	f.Parent = parent
	return f
end

local function circle(parent: Instance, name: string, colour: Color3, thick: number, z: number): Frame
	local f = frame(parent, name, nil, z)
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = f
	local edge = Instance.new("UIStroke")
	edge.Color = colour
	edge.Thickness = thick
	edge.Parent = f
	return f
end

local function text(parent: Instance, name: string, size: number, colour: Color3, z: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextSize = size
	l.TextColor3 = colour
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Size = UDim2.fromOffset(0, size * 1.2)
	l.AutomaticSize = Enum.AutomaticSize.X
	l.ZIndex = z
	l.Parent = parent
	return l
end

-- One gun's sheet and quadrant, made as I get on it
type View = {
	model: Model,
	gun: any,
	centre: Vector3, -- the gun's place, the sheet's middle
	pps: number, -- pixels a stud
	map: { destroy: () -> () }?,
	holder: Frame, -- everything of this gun's, gone with it
	lay: Frame,
	cross: { Frame },
	reach: Frame,
	range: TextLabel,
	needle: Frame,
	elevation: TextLabel,
	distance: TextLabel,
	reload: TextLabel,
	quadrant: Frame,
}

local function build(model: Model, gun: any, sheet: Frame, dial: Frame): View
	local w, h = S.size[1], S.size[2]
	local key = model:GetAttribute("Gun") :: any
	local cap = Rules.reachCap(Rules.sectorSpan(LiveMap.map.sectors), Cfg.Reach, key)
	local pps = w / (2 * (cap + S.around))
	local centre = model:GetPivot().Position
	local ink, pencil, amber = rgb(GR.ink), rgb(GR.pencil), rgb(GR.amber)

	local holder = frame(sheet, "Gun")
	holder.Size = UDim2.fromScale(1, 1)

	-- the map round the gun: its sketch's box sized to this scale and slid so the gun sits in the middle
	local mapKey = LiveMap.key()
	local m = SketchCfg.Maps[mapKey]
	local made = nil
	if m then
		local areaW, areaH = (m.x[2] - m.x[1]) * pps, (m.z[2] - m.z[1]) * pps
		local boxW, boxH = areaW / (1 - 2 * m.pad / m.size[1]), areaH / (1 - 2 * m.pad / m.size[2])
		local u, v = (centre.X - m.x[1]) / (m.x[2] - m.x[1]), (centre.Z - m.z[1]) / (m.z[2] - m.z[1])
		local box = frame(holder, "Map")
		box.Size = UDim2.fromOffset(boxW, boxH)
		box.Position = UDim2.fromOffset(
			w / 2 - (m.pad / m.size[1] * boxW + u * areaW),
			h / 2 - (m.pad / m.size[2] * boxH + v * areaH)
		)
		local ok, sketch = pcall(SketchMap.new, box, mapKey, {})
		made = if ok then sketch else nil
	end

	local over = frame(holder, "Over", nil, 5)
	over.Size = UDim2.fromScale(1, 1)
	local mid = Vector2.new(w / 2, h / 2)
	-- the reach cap, dashed
	local around = 2 * math.pi * cap * pps
	local n = math.max(12, math.floor(around / (S.dash + S.gap)))
	for i = 0, n - 1 do
		local a0 = i / n * 2 * math.pi
		local a1 = a0 + S.dash / (S.dash + S.gap) / n * 2 * math.pi
		Ink.segment(
			over,
			mid + Vector2.new(math.cos(a0), math.sin(a0)) * cap * pps,
			mid + Vector2.new(math.cos(a1), math.sin(a1)) * cap * pps,
			S.stroke,
			pencil,
			S.capSee
		).ZIndex =
			5
	end
	local lay = frame(over, "Lay", ink, 6)
	local you = circle(over, "Gun", ink, S.stroke, 7)
	you.BackgroundColor3, you.BackgroundTransparency = ink, 0
	you.Size = UDim2.fromOffset(S.dot, S.dot)
	you.Position = UDim2.fromOffset(mid.X, mid.Y)
	local reach = circle(over, "Reach", pencil, S.stroke, 7)
	local wound = gun.fragments and gun.fragments.wound or gun.zone
	reach.Size = UDim2.fromOffset(math.max(10, 2 * wound * pps), math.max(10, 2 * wound * pps))
	local cross = { frame(over, "CrossA", pencil, 8), frame(over, "CrossB", pencil, 8) }
	local range = text(over, "Range", S.text, ink, 8)
	range.TextStrokeColor3, range.TextStrokeTransparency = rgb(GR.paper), 0.2
	local title = text(over, "Title", S.text * 0.8, ink, 8)
	title.Position = UDim2.fromOffset(S.inset, S.inset / 2)
	title.Text = string.upper(gun.name or key)

	-- the quadrant: the pivot at its bottom left, an arc of ticks from the lowest to the highest elevation
	local D = S.dial
	local q = frame(dial, "Quadrant")
	q.Size = UDim2.fromScale(1, 1)
	local pivot = Vector2.new(D * S.pivot[1], D * S.pivot[2])
	local r = D * S.radius
	local paper = rgb(GR.paper)
	local lo, hi = gun.elevation[1], gun.elevation[2]
	local function at(deg: number, k: number): Vector2
		local a = math.rad(deg)
		return pivot + Vector2.new(math.cos(a), -math.sin(a)) * r * k
	end
	for e = lo, hi, 1 do
		local col = if e > S.split then amber else paper
		Ink.segment(q, at(e, 1), at(math.min(e + 1, hi), 1), S.stroke, col, 0.1)
	end
	for e = math.ceil(lo / S.tick) * S.tick, hi, S.tick do
		local long = e % 15 == 0 or e == S.split
		local col = if e > S.split then amber else paper
		Ink.segment(q, at(e, if long then S.long else S.short), at(e, 1), S.stroke, col, 0.1)
	end
	Ink.segment(q, at(S.split, S.splitMark[1]), at(S.split, S.splitMark[2]), S.bold, amber, 0)
	local function tickLabel(e: number, s: string)
		local l = text(q, `Tick{e}`, S.text * 0.75, paper, 2)
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		local p = at(e, S.label)
		l.Position = UDim2.fromOffset(p.X, p.Y)
		l.Text = s
	end
	tickLabel(lo, `{lo}°`)
	tickLabel(hi, `{hi}°`)
	tickLabel(S.split, "lob")
	-- (a bar twice the needle's length turned about its middle, only its outer half drawn: a Frame turns about its
	-- centre)
	local needle = frame(q, "Needle", nil, 3)
	needle.AnchorPoint = Vector2.new(0.5, 0.5)
	needle.Position = UDim2.fromOffset(pivot.X, pivot.Y)
	needle.Size = UDim2.fromOffset(r * 2, S.bold)
	local half = frame(needle, "Half", rgb(Palette.Artillery.Marker), 3)
	half.Position = UDim2.fromScale(0.5, 0)
	half.Size = UDim2.fromScale(0.5, 1)
	local hub = circle(q, "Hub", rgb(Palette.Artillery.Marker), 1, 4)
	hub.BackgroundColor3, hub.BackgroundTransparency = rgb(Palette.Artillery.Marker), 0
	hub.Size = UDim2.fromOffset(S.dot, S.dot)
	hub.Position = UDim2.fromOffset(pivot.X, pivot.Y)
	-- (the readouts in their own column beside the arc, clear of the needle)
	local x, top = D, D * S.rows[1]
	local elevation = text(q, "Elevation", S.text * 1.6, paper, 4)
	elevation.Position = UDim2.fromOffset(x, top)
	local distance = text(q, "Distance", S.text, paper, 4)
	distance.Position = UDim2.fromOffset(x, top + S.text * S.rows[2])
	local reload = text(q, "Reload", S.text, paper, 4)
	reload.Position = UDim2.fromOffset(x, top + S.text * S.rows[3])

	return {
		model = model,
		gun = gun,
		centre = centre,
		pps = pps,
		map = made,
		holder = holder,
		lay = lay,
		cross = cross,
		reach = reach,
		range = range,
		needle = needle,
		elevation = elevation,
		distance = distance,
		reload = reload,
		quadrant = q,
	}
end

local function destroy(v: View)
	if v.map then
		pcall(v.map.destroy)
	end
	v.holder:Destroy()
	v.quadrant:Destroy()
end

local function update(v: View)
	local w, h = S.size[1], S.size[2]
	local mid = Vector2.new(w / 2, h / 2)
	local function px(p: Vector3): Vector2
		return mid + Vector2.new(p.X - v.centre.X, p.Z - v.centre.Z) * v.pps
	end
	local model, gun = v.model, v.gun
	local pivot = model:GetPivot()
	local _, yaw = pivot:ToOrientation()
	local traverse = (model:GetAttribute("Traverse") :: number?) or 0
	local elevation = (model:GetAttribute("Elevation") :: number?) or gun.elevation[1]
	local layYaw = math.rad(math.deg(yaw) + traverse)
	local land = landAt
	local to = if land
		then px(land)
		else mid + Vector2.new(-math.sin(layYaw), -math.cos(layYaw)) * Rules.range(
			gun.speed,
			elevation + (gun.aimTilt or 0),
			gun.gravity
		) * v.pps
	stroke(v.lay, mid, to, S.stroke)
	for _, f in v.cross do
		f.Visible = land ~= nil
	end
	v.reach.Visible = land ~= nil
	v.range.Visible = land ~= nil
	local metres = nil
	if land then
		local c = S.cross
		stroke(v.cross[1], to + Vector2.new(-c, -c), to + Vector2.new(c, c), S.bold)
		stroke(v.cross[2], to + Vector2.new(-c, c), to + Vector2.new(c, -c), S.bold)
		v.reach.Position = UDim2.fromOffset(to.X, to.Y)
		metres =
			math.round(Vector3.new(land.X - v.centre.X, 0, land.Z - v.centre.Z).Magnitude * Damage.Blast.MetresPerStud)
		v.range.Text = `{metres} m`
		-- (the label beside the cross, kept on the sheet)
		v.range.Position = UDim2.fromOffset(
			math.clamp(to.X + S.cross * 1.6, S.inset / 2, w - S.text * 4),
			math.clamp(to.Y - S.cross - S.text * 1.2, S.inset / 2, h - S.text * 1.3)
		)
	end

	v.needle.Rotation = -elevation
	v.elevation.Text = string.format("%.1f°", elevation)
	v.distance.Text = if metres then `{metres} m · {string.format("%.1f", flightOf or 0)} s` else "no landing"
	local t = workspace:GetServerTimeNow()
	local share = Rules.loaded(t, (model:GetAttribute("ReadyAt") :: number?) or -math.huge, gun.reload)
	v.reload.Text = if share >= 1
		then "Ready"
		else `Loading {string.format(HudCfg.Artillery.timer, math.floor(share * 1000) / 10)}`
	v.reload.TextColor3 = if share >= 1 then rgb(Palette.Artillery.Marker) else rgb(GR.paper)
end

function ArtillerySheet.start()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "ArtillerySheet"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local sheet = frame(gui, "Sheet", rgb(GR.paper))
	sheet.AnchorPoint = Vector2.new(0, 1)
	sheet.Position = UDim2.new(0, S.margin[1], 1, -S.margin[2])
	sheet.Size = UDim2.fromOffset(S.size[1], S.size[2])
	sheet.ClipsDescendants = true
	local edge = Instance.new("UIStroke")
	edge.Color = rgb(GR.ink)
	edge.Thickness = 2
	edge.Parent = sheet

	local dial = frame(gui, "Dial", rgb(Palette.Artillery.Plate))
	dial.BackgroundTransparency = Cfg.Arc.plate
	dial.AnchorPoint = Vector2.new(0, 1)
	dial.Position = UDim2.new(0, S.margin[1] + S.size[1] + S.gapX, 1, -S.margin[2])
	dial.Size = UDim2.fromOffset(S.dial + S.readout, S.dial)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = dial

	local current: View? = nil
	RunService.RenderStepped:Connect(function()
		local model: Model? = nil
		local f = workspace:FindFirstChild(Cfg.Folder)
		if f then
			for _, m in f:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("Gunner") == player.UserId then
					model = m
					break
				end
			end
		end
		local gun = model and (Cfg.Guns :: any)[model:GetAttribute("Gun") :: any]
		if not (gun and gun.sheet) then
			model = nil
		end
		if current and current.model ~= model then
			destroy(current)
			current = nil
		end
		gui.Enabled = model ~= nil
		if not model then
			return
		end
		if not current then
			current = build(model, gun, sheet, dial)
		end
		update(current :: View)
	end)
end

return ArtillerySheet
